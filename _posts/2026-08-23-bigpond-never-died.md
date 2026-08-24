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

### Entering the Configuration Manager

The HTTP server handed the request to `rdp_setObj()`, so that was the first `libcmm` export to inspect:

```bash
witchtape@kraken:~/archer-251031$ fd -t f -g '*rdp_setObj.c' re/libcmm-decomp/functions
re/libcmm-decomp/functions/0002514c_9808a16fdd766c532760b34f_rdp_setObj.c
```

The raw Ghidra export remains the source of record. Rather than edit it by hand, we added a tiny wrapper that asks Codex for a separate review copy while keeping the model read-only:

```python
#!/usr/bin/env python3
"""Write a Codex-assisted review copy of one Ghidra decompilation."""

from __future__ import annotations

import argparse
import shlex
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Rewrite a Ghidra C export as a separate readable review copy."
    )
    parser.add_argument("source", type=Path, help="Ghidra-generated .c file")
    parser.add_argument("-o", "--output", required=True, type=Path, help="review-copy path")
    parser.add_argument("--force", action="store_true", help="replace an existing output file")
    args = parser.parse_args()

    source = args.source.resolve()
    output = args.output.resolve()

    if not source.is_file():
        parser.error(f"source is not a file: {source}")
    if source == output:
        parser.error("output must be a separate review copy")
    if output.exists() and not args.force:
        parser.error(f"output exists: {output} (pass --force to replace it)")
    if not output.parent.is_dir():
        parser.error(f"output directory does not exist: {output.parent}")

    prompt = (
        f"Read only {source.name}.\n"
        "Rewrite it as clean C-like pseudocode. Preserve logic, constants, and calls; "
        "add brief comments; output code only."
    )
    command = [
        "codex",
        "exec",
        "-C",
        str(source.parent),
        "--sandbox",
        "read-only",
        "--skip-git-repo-check",
        "--ignore-user-config",
        "--ignore-rules",
        "--ephemeral",
        "-o",
        str(output),
        prompt,
    ]

    print("+", shlex.join(command))
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
```

We invoke it as follows:
```bash
witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
  re/libcmm-decomp/functions/0002514c_9808a16fdd766c532760b34f_rdp_setObj.c \
  -o re/rdp_setObj.clean.c
```

The generated review copy sits beside the untouched Ghidra output. It does not add evidence; it makes the same control flow readable enough to review without losing the original:

![Codex-assisted review copy of rdp_setObj beside the raw Ghidra decompilation](/assets/img/archer-rdp-setobj-clean-vs-raw.png)

`rdp_setObj()` is still generic machinery. The next function worth opening is `rsl_setObj()`: it receives the resolved OID and completed object, so it should show how `libcmm` dispatches a configuration object to its actual implementation.

We beautify the next target:
```bash
witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
    re/libcmm-decomp/functions/*rsl_setObj.c \
    -o re/rsl_setObj.clean.c
```

The cleaned view made that dispatch explicit. `rsl_setObj()` masks the object identifier to 16 bits, uses it to index `g_rsl_objFuncTable`, and invokes that entry's `setObj` function pointer. Only after the object-specific setter succeeds does it call `dm_setObj()` and queue deferred work:

![Cleaned rsl_setObj beside the raw Ghidra output](/assets/img/archer-rsl-setobj-clean-vs-raw.png)

We had reached the table boundary. The next job was to resolve the `WAN_IP_CONN` string to its numeric OID, then use that OID to identify the corresponding `setObj` entry.

### Finding the OID Table

The web frontend gave us the object name, `WAN_IP_CONN`; `rsl_setObj()` showed that the backend dispatches by a numeric OID. The resolver tells us where those two representations meet, but not how the table is laid out. We first needed to locate `g_oidStringTable` itself:

```bash
witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
  re/libcmm-decomp/functions/*rsl_getOidByStr.c \
  -o re/rsl_getOidByStr.clean.c

witchtape@kraken:~/archer-251031$ rich re/rsl_getOidByStr.clean.c
```

There is no hash or parser hiding here. The resolver walks `g_oidStringTable` from OID `1` through `265`, compares each string exactly, and returns the matching index:

![Cleaned rsl_getOidByStr beside the raw Ghidra output](/assets/img/archer-rsl-getoid-clean-vs-raw.png)

The next step was to find the table data in the exported symbols and inspect its entries:

```bash
witchtape@kraken:~/archer-251031$ readelf -Ws re/libcmm.so | rg 'g_oidStringTable$'
   760: 000f1800  1064 OBJECT  GLOBAL DEFAULT   17 g_oidStringTable
```

The table begins at `0x000f1800` in the ELF and spans `0x428` bytes, ending at `0x000f1c28`. To translate that virtual address into a file offset, we checked the section that contains it:

```bash
witchtape@kraken:~/archer-251031$ readelf -W -S re/libcmm.so | rg ' \.data\s'
  [17] .data             PROGBITS        000ef080 0df080 0041a0 00  WA  0   0 16
```

`.data` begins at virtual address `0x000ef080` and file offset `0x000df080`, a delta of `0x10000`. Therefore the table's file offset is `0x000df080 + (0x000f1800 - 0x000ef080) = 0x000e1800`.

It contains little-endian 32-bit pointers, so we rendered one decoded word per line and numbered the entries from zero:

![Indexed g_oidStringTable pointer dump](/assets/img/archer-oid-string-table-dump.png)

To identify the relevant table entry, we first recovered the address of the target string from the library:

```bash
witchtape@kraken:~/archer-251031$ strings -a -t x re/libcmm.so | rg ' WAN_IP_CONN$'
  cbcf4 WAN_IP_CONN
```

We could then search that address, padded to an eight-digit word, in the indexed table. The matching row would be the `WAN_IP_CONN` OID and the bridge to its setter:

```bash
witchtape@kraken:~/archer-251031$ xxd -e -g4 -c4 -s $((0xe1800)) -l 0x428 re/libcmm.so |
  nl -v0 -ba |
  rg '000cbcf4'
```

The match lands on row `97`, giving `WAN_IP_CONN` the OID `97` (`0x61`):

![WAN_IP_CONN found at OID 97 in g_oidStringTable](/assets/img/archer-wan-ip-conn-oid.png)

We could now use that OID to inspect entry `97` in `g_rsl_objFuncTable` and identify the object-specific setter.

### Finding the Object Dispatch Table

We first located the table that `rsl_setObj()` indexes for its callback:

```bash
witchtape@kraken:~/archer-251031$ readelf -Ws re/libcmm.so | rg 'g_rsl_objFuncTable$'
   924: 000ee6bc  2128 OBJECT  GLOBAL DEFAULT   16 g_rsl_objFuncTable
```

The record size comes directly from `rsl_setObj()`'s table access: `g_rsl_objFuncTable + obj * 8 + 4`. The multiplication gives an eight-byte stride; the `+ 4` selects the second 32-bit word. The symbol's `0x850`-byte size therefore gives `0x850 / 8 = 266` records. OID `97`'s setter slot is `0x000ee6bc + 97 * 8 + 4 = 0x000ee9c8`.

Before reading that slot from disk, we mapped its containing section from virtual address to file offset:

```bash
witchtape@kraken:~/archer-251031$ readelf -W -S re/libcmm.so | rg ' \.data\.rel\.ro\s'
  [16] .data.rel.ro      PROGBITS        000ee014 0de014 001064 00  WA  0   0  4
```

The same `0x10000` delta applies here. The full OID `97` record starts at virtual address `0x000ee9c4`, which maps to file offset `0x000de9c4`; the setter is its second word at `0x000de9c8`. We dumped both words together:

```bash
witchtape@kraken:~/archer-251031$ xxd -e -g4 -c4 -s $((0xde9c4)) -l 8 re/libcmm.so
000de9c4: 00000000  ....
000de9c8: 00000000  ....
```

Both words are zero in the on-disk image, but this is a dynamically linked shared object. The next question was whether ELF relocations fix up those slots when `libcmm.so` is loaded. We queried the relocation entries for the exact record:

```bash
witchtape@kraken:~/archer-251031$ readelf -r re/libcmm.so |
  rg '000ee9c4|000ee9c8'
```

The relocations resolve both words of OID `97`'s record: its getter is `rsl_getWanIpConnObj`, and its setter is `rsl_setWanIpConnObj` at `0x00047e48`.

![Relocations resolving the WAN_IP_CONN getter and setter](/assets/img/archer-wan-ip-conn-relocations.png)

We had reached the object-specific setter. The next step was to locate its decompiled source:

```bash
witchtape@kraken:~/archer-251031$ fd -t f -g '*rsl_setWanIpConnObj.c' re/libcmm-decomp/functions
re/libcmm-decomp/functions/00057e48_e12f99bbee691d7b477cc3ed_rsl_setWanIpConnObj.c
```

### Reading the WAN Setter

This was the first object-specific code on the traced path, so we generated a separate review copy before reading it:

```bash
witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
  re/libcmm-decomp/functions/00057e48_e12f99bbee691d7b477cc3ed_rsl_setWanIpConnObj.c \
  -o re/rsl_setWanIpConnObj.clean.c
```

The setter first derives the WAN access mode and connection type from the submitted object:

![WAN setter deriving the access mode and connection type](/assets/img/archer-wan-setter-connection-type.png)

It then passes the object and both values into a downstream handler:

![WAN setter passing the object and connection type to its handler](/assets/img/archer-wan-setter-handler-call.png)

The handler is selected by the requested operation, not by the connection type. For the `ACT_SET` operation (`2`), the setter chooses `wan_conn_wanIpConn_handleSetOpt`; the BigPond connection type remains an argument passed to that routine.

```bash
witchtape@kraken:~/archer-251031$ rg -n -F -C 12 'case 2:' \
    re/rsl_setWanIpConnObj.clean.c
159-
160-    rsl_dhcpc_addHostnamePrefix(newObj);
161-    rsl_dhcpc_escapeHostname(newObj + 0x7f, 0x3f);
162-
163-    switch (operation) {
164-    case 3:
165-        printf(STR_BASE + 0x1ba0, STR_BASE - 0x3bf8, 0x2dc);
166-        printf(STR_BASE + 0x32ec);
167-        fputc('\n', stdout);
168-        handler = wan_conn_wanIpConn_handleAddOpt;
169-        break;
170-
171:    case 2:
172-        printf(STR_BASE + 0x1ba0, STR_BASE - 0x3bf8, 0x2e4);
173-        printf(STR_BASE + 0x3314);
174-        fputc('\n', stdout);
175-        handler = wan_conn_wanIpConn_handleSetOpt;
176-        break;
177-
178-    case 4:
179-        printf(STR_BASE + 0x1ba0, STR_BASE - 0x3bf8, 0x2e9);
180-        printf(STR_BASE + 0x333c);
181-        fputc('\n', stdout);
182-        handler = wan_conn_wanIpConn_handleDelOpt;
183-        break;
```

We located that set handler and prepared it for review:

```bash
witchtape@kraken:~/archer-251031$ fd -t f -g '*wanIpConn_handleSetOpt.c'
re/libcmm-decomp/functions/0004ff88_4749a70b4f0edadd9e342322_wan_conn_wanIpConn_handleSetOpt.c

witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
    re/libcmm-decomp/functions/0004ff88_4749a70b4f0edadd9e342322_wan_conn_wanIpConn_handleSetOpt.c \
    -o re/wanIpConn_handleSetOpt.clean.c
```

This was not the BPA-specific code we were looking for. The handler is shared WAN lifecycle machinery: it begins by asking `wan_conn_wanIpConn_getConnectionInfo()` to derive connection state, then validates and applies the configuration.

![The shared WAN set handler entering connection-state lookup](/assets/img/archer-wan-set-handler-generic.png)

Rather than follow its generic bring-up logic, we followed that first helper and the `wanType` argument it receives.
