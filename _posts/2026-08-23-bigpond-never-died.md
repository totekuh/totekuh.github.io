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

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root-0/etc/resolv.conf -> /var/tmp/resolv.conf; changing link target to /dev/null for security purposes.

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root-0/etc/passwd -> /var/passwd; changing link target to /dev/null for security purposes.

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root-0/etc/TZ -> /var/tmp/TZ; changing link target to /dev/null for security purposes.

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/etc/resolv.conf -> /var/tmp/resolv.conf; changing link target to /dev/null for security purposes.

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/etc/passwd -> /var/passwd; changing link target to /dev/null for security purposes.

WARNING: Symlink points outside of the extraction directory: /home/witchtape/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted/squashfs-root/etc/TZ -> /var/tmp/TZ; changing link target to /dev/null for security purposes.
1442304       0x160200        Squashfs filesystem, little endian, version 4.0, compression:xz, size: 6242568 bytes, 752 inodes, blocksize: 262144 bytes, created: 2025-10-31 03:16:01

WARNING: One or more files failed to extract: either no utility was found or it's unimplemented

witchtape@kraken:~/archer-251031$ cd _Archer_C20_EU_V6_251031.bin.extracted
witchtape@kraken:~/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted$ ls
 squashfs-root   squashfs-root-0   squashfs-root-1   160200.squashfs   20400   20400.7z
witchtape@kraken:~/archer-251031/_Archer_C20_EU_V6_251031.bin.extracted$ ls squashfs-root
 bin   dev   etc   lib   mnt   proc   sbin   sys   usr   var   web   linuxrc
```

## Targeting the Web Interface

The web interface was the obvious first target because it exposed the largest authenticated attack surface.

We began with a simple search for HTTP-related files in the extracted root filesystem. The results gave us one obvious candidate for the web service: `usr/bin/httpd`.

![Searching the extracted root filesystem for HTTP-related files and preserving the httpd binary for analysis](/assets/img/archer-httpd-triage.png)

Before reversing it, we copied `httpd` into a dedicated working directory and recorded its SHA-256: `0169bcd6a77229793d11f601ce28b45c805325afe346895374a50fc9bfef15356b`.
