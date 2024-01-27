---
title: ARM TrustZone
date: 2023-09-26 04:20:00
categories: [OS Internals]
tags: [arm, secureos, tee, cpu]     # TAG names should always be lowercase
---

## Introduction

ARM's TrustZone technology aims to enhance security by providing a safe execution environment for sensitive code, separated from the standard "Normal World." TrustZone achieves this by dividing system resources into secure and non-secure partitions.

- **Secure World**: A highly privileged environment where sensitive code like cryptographic algorithms and key storage run.
- **Normal World**: The general-purpose, less-privileged environment where the operating system and user applications operate.

## Switching Between Worlds

Switching between the secure and normal worlds is done through a "world switch," facilitated by specific instructions and often controlled by the monitor mode.

## Exception Levels (ELs)

ARM CPUs have Exception Levels (ELs) from EL0 to EL3, with EL3 being the most privileged. ELs are crucial in understanding security boundaries:

- `EL3`: Highly privileged, usually the first code to execute during the boot process.
- `EL2`: Used for virtualization and also has its security implications.
- `EL1`: The OS Kernel often runs here.
- `EL0`: User-level applications.

You can switch between these levels by taking an exception/interrupt or returning from one. 

For instance, ARM's `eret` instruction can be used to switch ELs even in the absence of an actual interrupt.

## AArch64 Internals

AArch64 is the 64-bit state introduced in the ARMv8-A architecture. 

The AArch64 architecture includes features that allow better performance, including more general-purpose registers and improved exception handling.

- **System Registers**: Such as CurrentEL to identify the current EL.
- **Instructions**: Such as mrs to read system registers and msr to write to them.

## Attack Vectors

- **Secure API Exploits**: Secure APIs are often used for communication between worlds. Incomplete validation or bugs can lead to critical vulnerabilities.
- **World Switching**: Vulnerabilities might exist in the world switch mechanism, allowing an adversary to execute code in the secure world from the normal world.
- **Exception Level Elevation**: Errors in switching or managing ELs can lead to privilege escalation. Monitoring instructions like eret can be critical here.
- **Secure Boot Flaws**: Since EL3 is the first to execute, vulnerabilities here can compromise the entire system.
- **Trusted Applications (TAs)**: These are essentially secure world software components. Vulnerabilities in TAs can compromise secure data.

## Tools and Techniques

- **Reverse Engineering Tools**: IDA Pro, Ghidra for analyzing secure world binaries.
- **Virtualization**: QEMU for simulating TrustZone environments.
- **Debuggers**: JTAG for low-level debugging.
- **Static Analysis Tools**: For analyzing API calls, data flows, etc.

## Further Study Areas

- **ARM Architecture Reference Manuals**: To understand AArch64 instructions and features.
- **TrustZone API Documentation**: To delve deeper into secure APIs.
- **CVE Databases**: To understand past vulnerabilities in TrustZone and related components.
