---
title: "BigPond Never Died: Root RCE in TP-Link's Legacy WAN Stack"
date: 2026-08-23 19:50:00 +0200
categories: [Vulnerability Research, Embedded Systems]
tags: [tp-link, firmware, command-injection, bigpond, embedded-linux]
description: "An obsolete ISP feature remained in Archer C20 v6 firmware and let BPA configuration reach a root shell through system()."
---

I bought an ordinary consumer router - a TP-Link Archer C20 v6 - and took it apart to look for bugs I could exploit. It was nothing exotic: the sort of cheap box people put behind an ISP connection and forget about.

The plan was simple: inspect the firmware, map the exposed attack surface, and see what the vendor had left behind.

## Mapping the Target

You know the drill. Before trying to break anything, we need a map of the box: its firmware version, which processes started at boot, which services were exposed, and **where configuration data went after it left the web interface**.

First up: enumerate the services exposed by the router. The target was reachable over `wlan0`.

We used Nmap to scan the full TCP range:

```bash
witchtape@kraken:~$ ip -br a show dev wlan0
wlan0            UP             192.168.1.100/24 fe80::76de:f026:a756:2f12/64 

witchtape@kraken:~$ nmap -p- -Pn -n 192.168.1.1                       
Starting Nmap 7.99 ( https://nmap.org ) at 2026-08-23 20:26 +0200
Nmap scan report for 192.168.1.1
Host is up (0.016s latency).
Not shown: 65529 closed tcp ports (reset)
PORT      STATE SERVICE
80/tcp    open  http
1900/tcp  open  upnp
7547/tcp  open  cwmp
20001/tcp open  microsan
MAC Address: 3C:64:CF:7B:83:31 (TP-Link Systems)

Nmap done: 1 IP address (1 host up) scanned in 18.46 seconds
                                                                                                                                                                                                                   
witchtape@kraken:~$
```

The scan exposed an HTTP administration interface. When we first booted the router, we set the administrator password to `Password123!`; logging in then confirmed the exact hardware and firmware build under test:

![TP-Link Archer C20 v6 status page showing firmware Build 251031](/assets/img/archer-web-panel-fw.png)

With the target identified, we went looking for the matching firmware image. TP-Link still hosts [`Archer C20(EU)_V6_251031`](https://www.tp-link.com/nordic/support/download/archer-c20/v6/), the same build reported by the router.

That gave us a clean starting point for the offline work.

We proceeded by downloading the firmware:

```bash
witchtape@kraken:~$ mkdir archer-251031
witchtape@kraken:~$ cd archer-251031
witchtape@kraken:~/archer-251031$ wget 'https://static.tp-link.com/upload/firmware/2025/202511/20251114/Archer%20C20%28EU%29_V6_251031.zip' -O Archer_C20_EU_V6_251031.zip
--2026-08-23 21:28:47--  https://static.tp-link.com/upload/firmware/2025/202511/20251114/Archer%20C20%28EU%29_V6_251031.zip
Resolving static.tp-link.com (static.tp-link.com)... 99.84.152.37, 99.84.152.87, 99.84.152.21, ...
Connecting to static.tp-link.com (static.tp-link.com)|99.84.152.37|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 7891785 (7.5M) [application/octet-stream]
Saving to: ‘Archer_C20_EU_V6_251031.zip’

Archer_C20_EU_V6_251031.zip                          100%[=====================================================================================================================>]   7.53M  6.64MB/s    in 1.1s    

2026-08-23 21:28:48 (6.64 MB/s) - ‘Archer_C20_EU_V6_251031.zip’ saved [7891785/7891785]

witchtape@kraken:~/archer-251031$ unzip Archer_C20_EU_V6_251031.zip                                                   
Archive:  Archer_C20_EU_V6_251031.zip
  inflating: Archer_C20v6_EU_0.9.1_4.19_up_boot[251031-rel40519]_2025-10-31_11.16.35.bin  
  inflating: GPL License Terms.pdf   
  inflating: How to upgrade firmware of TP-Link Wi-Fi Router.pdf
witchtape@kraken:~/archer-251031$ sha256sum Archer_C20_EU_V6_251031.bin 
6d94f0501831c25e7de4ffe7437fecde8df192a15da1378e7b120dd9d331b57b  Archer_C20_EU_V6_251031.bin
```

## Decompiling the Firmware

We started with the usual first pass. `file` saw only raw data, which is normal for a vendor firmware image.

```bash
witchtape@kraken:~/archer-251031$ file Archer_C20_EU_V6_251031.bin
Archer_C20_EU_V6_251031.bin: data
```

Next, we handed it to `binwalk` to find the image boundaries and carve out anything worth looking at.

![Binwalk locating the bootloader, kernel, and SquashFS root filesystem](/assets/img/archer-binwalk-layout.png)

`binwalk` finds an LZMA kernel at `0x20400` and the XZ SquashFS root filesystem at `0x160200`; that rootfs is where the real work begins.

We extracted the image with `binwalk -e` , which carved out the kernel and the SquashFS root filesystem for inspection:

```bash
witchtape@kraken:~/archer-251031$ binwalk -e Archer_C20_EU_V6_251031.bin

DECIMAL       HEXADECIMAL     DESCRIPTION
--------------------------------------------------------------------------------
132096        0x20400         LZMA compressed data, properties: 0x5D, dictionary size: 8388608 bytes, uncompressed size: 3441784 bytes

...

witchtape@kraken:~/archer-251031$ cd _Archer_C20_EU_V6_251031.bin.extracted
witchtape@kraken:~/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted$ ls
 squashfs-root   squashfs-root-0   squashfs-root-1   160200.squashfs   20400   20400.7z
witchtape@kraken:~/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted$ ls squashfs-root
 bin   dev   etc   lib   mnt   proc   sbin   sys   usr   var   web   linuxrc
```

## Targeting the Web Interface

The web interface was the obvious first target because it exposed the largest authenticated attack surface.

We began with a simple search for HTTP-related files in the extracted root filesystem. The results gave us one obvious candidate for the web service: `usr/bin/httpd`.

Before reversing it, we copied `httpd` into a dedicated working directory and recorded its SHA-256: `0169bcd6a77229793d11f601ce28b45c805325afe346895374a50fc9bfef15356b`.

With the binary isolated, we first checked the shared libraries it needs at runtime:

![Listing httpd runtime dependencies with readelf](/assets/img/archer-httpd-dependencies.png)

`httpd` was not self-contained, but the dependency list alone did not tell us where the interesting logic lived. We started by reversing the web server itself.

Rather than work through a stripped MIPS binary one function at a time, we used [`ghidra-decomp`](https://github.com/totekuh/ghidra-decomp) to bulk-decompile `httpd` into a searchable corpus.

![Bulk decompilation of httpd with ghidra-decomp](/assets/img/archer-httpd-bulk-decomp.png)

The export included per-function pseudocode, a combined source file, and indexes for strings, imports, exports, symbols, cross-references, and the call graph:

```bash
witchtape@kraken:~/archer-251031$ ls re/httpd-decomp
 assembly    all_functions.c   exports.json     imports.json    metadata.json   sections.json   symbols.json   xrefs.jsonl
 functions   callgraph.json    functions.json   manifest.json   program.gzf     strings.json    types.json
```

Our first sweep of the exported function names surfaced a large web-facing attack surface: CGI initializers, request handlers, authentication, OID lookup, configuration, backup, and firmware-update code.

![First sweep of HTTP handler, authentication, CGI, and OID-related functions](/assets/img/archer-httpd-first-sweep.png)

## From Panel to Backend

With the decompiled code in hand, we could stop treating the panel as a black box. We chose the BigPond form and began tracing its submitted fields through the backend, looking for a path from user-controlled configuration to process execution.

The legacy BigPond option was still exposed under **Network → WAN**:

![WAN settings page, with Network and WAN selected](/assets/img/archer-bpa-wan-navigation.png)

Selecting **BigPond Cable** from the connection-type menu revealed the legacy configuration path:

![BigPond Cable shown in the WAN connection-type menu](/assets/img/archer-bpa-wan-selector.png)

The resulting form gave us the inputs to follow: username, password, authentication server, authentication domain, and the connection settings.

![BigPond Cable WAN configuration form](/assets/img/archer-bpa-wan-fields.png)

The WAN page lives in `web/main/ethWan.htm`; its common request machinery is in `web/js/lib.js`. Both were minified, so we made formatted copies before going any further:

![Creating formatted copies of the WAN page and its JavaScript helper](/assets/img/archer-frontend-beautify.png)

### Following Auth Server

The **Auth Server** label led to the BigPond WAN page and its DOM identifier, `bpa_authserver`:

```bash
witchtape@kraken:~/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root$ rg -n -i 'Auth Server' web | cut -c1-200
web/main/ethWan.htm:214: <p><b class="item L T" id="t_bpa_authServer">Auth Server:</b><input type="text" class="text" size="15" id="bpa_authserver" maxlength="63" /></p>
```

With the formatted copy, we could search the field directly:

```bash
witchtape@kraken:~/archer-251031$ rg -n -C 3 'bpa_authserver' re/frontend/ethWan.pretty.htm
987-        $.loadHelpFrame("BpaCfgHelpRpm.htm");
988-        $.id("bpa_username").value = wan_bpa_list.X_TP_BpaUsername;
989-        $.id("bpa_pwd").value = wan_bpa_list.X_TP_BpaPassword;
990:        $.id("bpa_authserver").value = wan_bpa_list.X_TP_BpaAuthServer;
991-        $.id("bpa_authdomain").value = wan_bpa_list.X_TP_BpaAuthDomain;
--
2184:        if ($.id("bpa_authserver").value == "") {
2185-            $.alert(ERR_WAN_BPA_AUTHSERVER_INVAD);
2186:            element = $.id("bpa_authserver");
2187-            if (element) {
2188-                element.focus();
2189-                element.select()
2190-            }
2191-            return false
2192-        }
2193:        wan_bpa_listarg.X_TP_BpaAuthServer = $.id("bpa_authserver").value;
```

That gave us the field's configuration name. When the page loads, it reads `X_TP_BpaAuthServer` into the form; when it saves, it copies the user value back into the BPA configuration object.

We now had a concrete field to follow. Before tracing the staged `wan_bpa_listarg` object any further, we needed to identify what submits the form. The page's Save button gave us the next function name:

```bash
witchtape@kraken:~/archer-251031$ rg -n -C 2 'id="saveBtn"' re/frontend/ethWan.pretty.htm
3141-    <p class="bl"></p>
3142-    <p class="tail" id="tail">
3143:        <input type="button" id="saveBtn" class="button L T T_save" value="Save" onclick="doSave(0);" />
3144-    </p>
3145-</div>
```

### Committing the BPA Object

With the submission handler identified, we inspected the BigPond branch of `doSave()`. It does not use a special request handler: it queues the complete BPA configuration object as a set operation on `WAN_IP_CONN`, then hands the queued operations to the common request executor:

```bash
witchtape@kraken:~/archer-251031$ rg -n -F -C 8 'wan_bpa_listarg.enable = 1;' re/frontend/ethWan.pretty.htm
2457-                                }
2458-                                if (dynEnable == 1) {
2459-                                    $.act(ACT_SET, WAN_IP_CONN, dynStk, null, ["enable=0"])
2460-                                }
2461-                                if ((ethEnable == 0) && (bpaEnable == 1)) {
2462-                                    $.act(ACT_SET, WAN_IP_CONN, bpaStk, null, ["enable=0"])
2463-                                }
2464-                                if (!$.exe()) {
2465:                                wan_bpa_listarg.enable = 1;
2466-                                $.act(ACT_SET, WAN_ETH_INTF, pStk, null, ["X_TP_lastUsedIntf=bpa_eth3_d", "X_TP_lastUsedName=" + wan_bpa_list.name]);
2467:                                $.act(ACT_SET, WAN_IP_CONN, bpaStk, null, wan_bpa_listarg)
2468-                            } else {
2469-                                return
2470-                            }
```

The generic `$.act()` helper queues the operation type, OID, stack, parent stack, and attributes in `$.as`:

```bash
witchtape@kraken:~/archer-251031$ rg -n -F -C 8 '$.as.push([type, null, oid, stack, pStack, attrs' re/frontend/lib.pretty.js
959-                        attrs = $.ansi(attrs)
960-                    }
961-                case ACT_DEL:
962-                case ACT_OP:
963-                    break;
964-                default:
965-                    return false
966-            }
967:            $.as.push([type, null, oid, stack, pStack, attrs, attrs ? attrs.match(/\r\n/g).length : 0]);
968-            $.ds.push(ret);
969-            return ret
970-        },
971-        exe: function(hook, unerr, securityLevel) {
972-            var url = "/cgi?";
973-            var data = "";
```

Line 971 defines `$.exe()`. It is the frontend's queue-flush routine: it drains `$.as`, builds the CGI request, and sends it. Although it starts with `/cgi?`, that is not the route this firmware takes.

The feature configuration enables the GDPR request wrapper:

```bash
witchtape@kraken:~/archer-251031$ rg -o 'INCLUDE_LOGIN_GDPR_ENCRYPT=[0-9]+' _Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/web/js/oid_str.js
INCLUDE_LOGIN_GDPR_ENCRYPT=1
```

The BigPond Save handler calls `$.exe()` without a third `securityLevel` argument. In JavaScript, `undefined != 0` is true, so the wrapper selects `/cgi_gdpr?`:

```bash
witchtape@kraken:~/archer-251031$ rg -n -F -C 3 '$.exe(function(err)' re/frontend/ethWan.pretty.htm
2474-                }
2475-            }
2476-        }
2477:        $.exe(function(err) {
2478-            if (!err) {

witchtape@kraken:~/archer-251031$ rg -n -F -C 2 'url = "/cgi_gdpr?"' re/frontend/lib.pretty.js
978-            if (INCLUDE_LOGIN_GDPR_ENCRYPT && securityLevel != 0) {
979-                try {
980:                    url = "/cgi_gdpr?"
981-                } catch (e) {}
982-            }
```

The GDPR branch keeps the same object descriptor, but moves the action type into the encrypted request data rather than appending it to the URL:

```bash
witchtape@kraken:~/archer-251031$ sed -n '997,1013p' re/frontend/lib.pretty.js
            if (INCLUDE_LOGIN_GDPR_ENCRYPT && url.match("/cgi_gdpr") != null) {
                while (obj = $.as.shift()) {
                    tmpdata += obj[0] + (obj[1] ? "=" + obj[1] : "") + "&";
                    data += "[" + obj[2] + "#" + obj[3] + "#" + obj[4] + "]" + index + "," + obj[6] + "\r\n" + obj[5];
                    index++
                }
                tmpdata = tmpdata.substr(0, tmpdata.length - 1);
                tmpdata = tmpdata + "\r\n" + data;
                data = tmpdata
            } else {
                while (obj = $.as.shift()) {
                    url += obj[0] + (obj[1] ? "=" + obj[1] : "") + "&";
                    data += "[" + obj[2] + "#" + obj[3] + "#" + obj[4] + "]" + index + "," + obj[6] + "\r\n" + obj[5];
                    index++
                }
            }
            url = url.substr(0, url.length - 1);
```

The action type is not an inference: `lib.js` defines `ACT_SET` as `2`.

```bash
witchtape@kraken:~/archer-251031$ rg -o 'ACT_SET = [0-9]+' re/frontend/lib.pretty.js
ACT_SET = 2
```

`ACT_SET` is therefore serialized as `2` in the GDPR payload. We now had a precise backend string to hunt for, so we searched the decompiled HTTP server:

![Searching the decompiled HTTP server for the GDPR route](/assets/img/archer-httpd-gdpr-search.png)

The search gave us a likely handler and an initialization routine. The latter tells us whether they are actually connected:

![The GDPR route registered to its handler](/assets/img/archer-httpd-gdpr-route-registration.png)

### Cleaning the Handler

The handler was 471 lines of decompiler output. We made a separate readable copy for review, leaving the original export intact:

![Generating a cleaned analyst copy of the GDPR CGI handler](/assets/img/archer-httpd-gdpr-cleanup-final.png)

### Following the Set Path

We did not need to read the whole damn thing at once. The frontend had already told us that `ACT_SET` was `2`, so we started at the matching branch in the cleaned handler:

![Cleaned SET dispatch in the GDPR CGI handler](/assets/img/archer-httpd-clean-set-dispatch.png)

The handler resolves the submitted object name, then passes that name and the parsed object data to `rdp_setObj()`. We cross-checked the cleaned branch against the original Ghidra output before following the call further:

![Raw Ghidra SET dispatch used to cross-check the cleaned copy](/assets/img/archer-httpd-raw-set-dispatch.png)

The next question was where those two functions actually lived. We first checked their dynamic-symbol entries in `httpd`:

```bash
witchtape@kraken:~/archer-251031$ readelf -Ws re/httpd | rg 'rdp_setObj$|rsl_getOidByStr$'
   269: 00419640     0 FUNC    GLOBAL DEFAULT  UND rsl_getOidByStr
   274: 004195f0     0 FUNC    GLOBAL DEFAULT  UND rdp_setObj
```

![Undefined RDP symbols in httpd](/assets/img/archer-httpd-rdp-und.png)

`UND` means *undefined in this ELF*: `httpd` calls these functions, but does not implement them. The dynamic loader must resolve them from one of the shared libraries loaded with the process.

We then searched the extracted library directory for a library exporting either symbol:

![Searching the extracted libraries for the RDP symbol owner](/assets/img/archer-libcmm-symbol-owner.png)

`libcmm.so` was the only match, so that was where the BigPond configuration path continued.

### Decompiling libcmm

We copied the matching library into the working directory and bulk-decompiled it for the next pass:

![Copying and bulk-decompiling libcmm.so](/assets/img/archer-libcmm-decomp.png)
