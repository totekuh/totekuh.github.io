---
title: Rootkits Types & Detection
date: 2023-09-26 04:20:00
categories: [Attack Chain, Persistence]
tags: [malware, rootkit]     # TAG names should always be lowercase
---

Let's delve deeper into each type of rootkit, exploring typical infection vectors and common detection methods.

A rootkit is a collection of software tools used to gain and maintain unauthorized, privileged access to a computer system. 

Rootkits can operate at various levels, from application-level to the kernel level, and are difficult to detect using standard methods.

## Kernel-level Rootkits

### Description

Kernel-level rootkits insert themselves into the operating system's kernel. 

Because the kernel has full control over the system, these rootkits are incredibly powerful and difficult to detect and remove.

### Infection Vectors

- Exploiting kernel-level vulnerabilities
- Bundled with malicious drivers
- Privilege escalation attacks

### Detection

- Integrity checks of the kernel code
- Anomaly-based intrusion detection systems (IDS)
- External hardware-based monitoring

---

## Application-level Rootkits

### Description

These rootkits work at the application layer and typically mimic or replace legitimate application binaries. 

They are easier to detect compared to kernel-level rootkits because they don't operate in privileged mode.

### Infection Vectors

- Trojanized applications
- Software bundling
- User-installed rogue applications

### Detection

- Regular antivirus scans
- Monitoring for unexpected application behavior
- Filesystem checks for known malicious binaries

---

## Hypervisor-level Rootkits

### Description

Hypervisor-level rootkits operate between the hardware and the operating system, making them extremely stealthy as they can intercept calls made between the hardware and the OS.

### Infection Vectors

- Compromised virtual machine images
- Vulnerabilities in existing hypervisors
- Malicious hardware devices that install a rogue hypervisor

### Detection

- Timing-based detection techniques
- Secure Boot checks
- Attestation-based security measures

---

## Bootkit Rootkits

### Description

These rootkits compromise the system's bootloader. 

They are loaded before the operating system, making them difficult to detect using standard tools within the OS.

### Infection Vectors

- Infecting master boot record (MBR)
- Utilizing vulnerabilities in UEFI/BIOS
- External storage devices that inject malicious code

### Detection

- Checking digital signatures of bootloader components
- Integrity checks of the MBR and VBR
- Live booting and scanning from a clean system

---

## Library-level Rootkits

### Description

Library-level rootkits replace or modify dynamic link library files (DLLs) used by legitimate programs, making them relatively stealthy.

### Infection Vectors

- Malicious software updates
- DLL preloading attacks
- In-memory injection attacks

### Detection

- Monitoring for unauthorized changes in DLL files
- Behavioral analysis of running applications
- Code signing checks on libraries

---

## Firmware Rootkits

### Description

These rootkits embed themselves in the system's firmware, such as the BIOS/UEFI or embedded controllers, making them persist even after OS reinstallation.

### Infection Vectors

- Supply chain attacks
- Rogue firmware updates
- Physical access to the hardware

### Detection

- Firmware integrity checks
- Hardware-based security solutions like TPM
- Forensic analysis of the firmware code
