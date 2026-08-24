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

We started with a full TCP scan of the router:

```bash
witchtape@kraken:~$ nmap -p- -Pn -n 192.168.1.1                       
PORT      STATE SERVICE
80/tcp    open  http
1900/tcp  open  upnp
7547/tcp  open  cwmp
20001/tcp open  microsan
```

The scan exposed an HTTP administration interface. When we first booted the router, we set the administrator password to `Password123!`; logging in then confirmed the exact hardware and firmware build under test:

![TP-Link Archer C20 v6 status page showing firmware Build 251031](/assets/img/archer-web-panel-fw.png)

With the target identified, we went looking for the matching firmware image. TP-Link still hosts [`Archer C20(EU)_V6_251031`](https://www.tp-link.com/nordic/support/download/archer-c20/v6/), the same build reported by the router.

That gave us a clean starting point for the offline work.

We downloaded the image and recorded its digest:

```bash
witchtape@kraken:~/archer-251031$ wget 'https://static.tp-link.com/upload/firmware/2025/202511/20251114/Archer%20C20%28EU%29_V6_251031.zip' -O Archer_C20_EU_V6_251031.zip
witchtape@kraken:~/archer-251031$ unzip Archer_C20_EU_V6_251031.zip                                                   
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

We extracted the image with `binwalk -e`, which carved out the kernel and the SquashFS root filesystem for inspection:

```bash
witchtape@kraken:~/archer-251031$ binwalk -e Archer_C20_EU_V6_251031.bin
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

The export gave us searchable pseudocode plus string, symbol, cross-reference, and call-graph indexes. Our first sweep surfaced CGI initializers, request handlers, authentication, OID lookup, configuration, backup, and firmware-update code.

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

The Save control calls `doSave(0)`, giving us the submission path to inspect.

### Committing the BPA Object

With the submission handler identified, we inspected the BigPond branch of `doSave()`. It does not use a special request handler: it queues the complete BPA configuration object as a set operation on `WAN_IP_CONN`, then hands the queued operations to the common request executor:

```bash
wan_bpa_listarg.enable = 1;
$.act(ACT_SET, WAN_IP_CONN, bpaStk, null, wan_bpa_listarg)
```

The generic `$.act()` helper queues the operation type, OID, stack, parent stack, and attributes in `$.as`:

```bash
$.as.push([type, null, oid, stack, pStack, attrs, attrs ? attrs.match(/\r\n/g).length : 0]);
```

`$.exe()` flushes that queue. This build enables the GDPR wrapper, and `doSave()` calls `$.exe()` without a `securityLevel`; because `undefined != 0`, the request goes to `/cgi_gdpr?` rather than `/cgi?`. The wrapper retains the object descriptor and serializes the action type into the encrypted request body:

```bash
if (INCLUDE_LOGIN_GDPR_ENCRYPT && securityLevel != 0)
    url = "/cgi_gdpr?";

data += "[" + obj[2] + "#" + obj[3] + "#" + obj[4] + "]" +
        index + "," + obj[6] + "\r\n" + obj[5];
```

`lib.js` defines `ACT_SET` as `2`, so the BPA object reaches the backend as an encrypted set request. We now had a precise backend string to hunt for, so we searched the decompiled HTTP server:

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

The raw Ghidra export remained the source of record. Our small read-only Codex wrapper wrote a separate C-like review copy; it preserved calls and constants, but never replaced the original. We invoked it as follows:
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

The web frontend gave us the name `WAN_IP_CONN`; `rsl_setObj()` dispatches by a numeric OID. `rsl_getOidByStr()` is a linear lookup over `g_oidStringTable`, returning the index of an exact match:

![Cleaned rsl_getOidByStr beside the raw Ghidra output](/assets/img/archer-rsl-getoid-clean-vs-raw.png)

The table is a 1,064-byte array of 32-bit pointers. `readelf` places it at virtual address `0x000f1800`; the containing `.data` section has a `0x10000` VMA-to-file-offset delta, putting the table at file offset `0x000e1800`.

```bash
witchtape@kraken:~/archer-251031$ readelf -Ws re/libcmm.so | rg 'g_oidStringTable$'
   760: 000f1800  1064 OBJECT  GLOBAL DEFAULT   17 g_oidStringTable
```

![The exported OID string table symbol](/assets/img/archer-oid-string-table-symbol.png)

We rendered one decoded word per line and numbered the entries from zero:

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

`rsl_setObj()` accesses `g_rsl_objFuncTable + obj * 8 + 4`: eight-byte records, with the second word as the setter. OID `97` therefore selects slot `0x000ee9c8`.

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

Both words are zero in the on-disk shared object; dynamic relocations populate them at load time. We queried those relocations directly:

```bash
witchtape@kraken:~/archer-251031$ readelf -r re/libcmm.so |
  rg '000ee9c4|000ee9c8'
```

The relocations resolve both words of OID `97`'s record: its getter is `rsl_getWanIpConnObj`, and its setter is `rsl_setWanIpConnObj` at `0x00047e48`.

![Relocations resolving the WAN_IP_CONN getter and setter](/assets/img/archer-wan-ip-conn-relocations.png)

This led directly to the object-specific setter, `rsl_setWanIpConnObj()`.

### Reading the WAN Setter

This was the first object-specific code on the traced path, so we generated a separate review copy before reading it.

The setter first derives the WAN access mode and connection type from the submitted object:

![WAN setter deriving the access mode and connection type](/assets/img/archer-wan-setter-connection-type.png)

It then passes the object and both values into a downstream handler:

![WAN setter passing the object and connection type to its handler](/assets/img/archer-wan-setter-handler-call.png)

The handler is selected by the requested operation, not by the connection type. For `ACT_SET` (`2`), it chooses `wan_conn_wanIpConn_handleSetOpt`; the BigPond connection type remains an argument passed to that routine. We generated a review copy of the selected handler.

This was not the BPA-specific code we were looking for. The handler is shared WAN lifecycle machinery: it begins by asking `wan_conn_wanIpConn_getConnectionInfo()` to derive connection state, then validates and applies the configuration.

![The shared WAN set handler entering connection-state lookup](/assets/img/archer-wan-set-handler-generic.png)

That was enough to rule it out as the BPA dispatch point. We stopped following generic setup code and moved to the IPv4 connection routine, where the selected connection type is dispatched.
