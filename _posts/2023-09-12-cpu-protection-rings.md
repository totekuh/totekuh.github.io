---
title: CPU Protection Rings
date: 2023-09-12 04:20:00
categories: [OS Internals]
tags: [cpu]     # TAG names should always be lowercase
---

Central Processing Unit (CPU) protection rings are a hierarchical model that computer systems use to manage different levels of access and permissions for software and processes. 

Originating from the Multics operating system, this architecture has become a cornerstone for modern computing. 

## High-Level Overview: What is a CPU Ring?

In computing, a CPU ring is essentially a layer of protection or privilege level that determines how much access a particular piece of code has to the system's hardware and software resources. 

The classical ring architecture consists of four rings, numbered `0` through `3`, with Ring 0 being the most privileged and Ring 3 the least. 

These rings act as barriers or fences, making sure that less trusted code cannot easily compromise the integrity or security of the entire system.

## Ring 0: Kernel Mode

### Features

- **Unrestricted Hardware Access**: The kernel has the power to perform direct memory access (DMA), control over CPU clock cycles, and even the ability to reset hardware components, providing complete control over the machine.
- **System Calls Execution**: The kernel has its own set of system calls, known as "privileged instructions," which can be used to change CPU modes, control hardware, and more. These are not exposed to higher rings.
- **Memory Management**: This goes beyond basic page mapping; the kernel can allocate, deallocate, or relocate memory blocks as it sees fit. It can also enforce memory protection schemes and execute cache coherency protocols.
- **Interrupt Handling**: Includes advanced features like Nested Vectored Interrupt Controllers (NVIC), which prioritize and nest interrupts for more efficient processing.
- **Task Scheduling**: In addition to various algorithms, it also employs real-time scheduling capabilities and can dynamically adjust scheduling based on system load.
- **Syscall List**: Ring 0 has its own unique system calls, which are inaccessible and not exposed to other rings, providing an extra layer of security.

### Security Risks

- **Full System Compromise**: A flaw at this level may lead to arbitrary code execution, subversion of any security mechanisms, and even installation of persistent rootkits that survive system reboots.
- **Data Exposure**: The kernel's ability to read any portion of physical or virtual memory puts all data at risk, including encrypted filesystems which could be read in decrypted form if the keys are in memory.
- **Resource Starvation**: An adversary gaining control at this level can selectively disable interrupts, effectively freezing other tasks, leading to DoS conditions.
- **Security Policy Bypass**: Security frameworks that operate at Ring 0, such as SELinux, could be completely disabled by malicious code operating at this level.

### Examples

- **Kernel Exploits**: Well-known exploits like EternalBlue target vulnerabilities within the Windows kernel, enabling privilege escalation and remote code execution.
- **Hardware Vulnerabilities**: Attacks like Spectre exploit the speculative execution features of modern CPUs, requiring patches at the Ring 0 level to mitigate.

---

## Ring 1: Special Drivers

### Features

- **Limited Hardware Access**: Ring 1 code can interact with hardware but generally requires Ring 0 to broker these interactions. This is a half-privileged level useful for certain drivers.
- **Driver Isolation**: Code here often includes proprietary or third-party drivers that require more privilege than user-mode code but are not trusted enough for Ring 0.
- **Syscall List**: This ring has a selective list of system calls, specifically whitelisted by the Ring 0 kernel to perform its functions, such as DMA transfers on specific hardware.

### Security Risks

- **Elevated Privilege Attacks**: Because this ring can call a subset of privileged instructions, poorly coded or insecure drivers can become targets for privilege escalation attacks.
- **Security Boundary Bypass**: If an adversary can break out of Ring 1, they are one step closer to compromising Ring 0, making this a vital security boundary.

### Examples

- **Virtual Machine Monitors (VMMs)**: In some architectures, VMMs operate at Ring 1 to efficiently manage virtual machines while isolating them from the host OS.
- **High-performance Drivers**: Some real-time operating systems use Ring 1 to host drivers that need quick access to hardware but don't require full Ring 0 privileges.

---

## Ring 2: System Services

### Features

- **Limited Hardware Access**: Similar to Ring 1 but with more restrictions. Generally, it can't perform any hardware tasks that could affect the system's overall stability or security.
- **System Service Isolation**: Typically hosts less critical system services like print spoolers, event loggers, or some types of networking tasks.
- **Syscall List**: Has a set of system calls it can access, more expansive than Ring 3, but still significantly limited compared to Ring 0 and 1.

### Security Risks

- **Privilege Escalation**: Vulnerabilities can allow an adversary to move from Ring 3 to Ring 2, gaining increased access to syscalls and potentially using this as a staging area for further attacks.
- **Data Integrity**: An adversary with access to this ring could tamper with less critical system services, leading to data corruption or unauthorized data access.

### Examples

- **Filesystem Management**: Non-core filesystem tasks like file indexing services might operate here.
- **Background Services**: Things like software updaters may operate in this ring to keep a low profile and avoid affecting system stability.

---

## Ring 3: User Mode

### Features

- **No Direct Hardware Access**: Totally isolated from hardware; any hardware-level operation has to be requested through system calls to higher privilege rings.
- **User Programs**: All the regular user-level applications like browsers, word processors, and even simpler things like calculators run here.
- **Syscall Interface**: A carefully controlled set of system calls are exposed to Ring 3, which it can use to request services from the kernel (Ring 0).
- **Isolation**: Even within Ring 3, processes are isolated from each other through techniques like Address Space Layout Randomization (ASLR).

### Security Risks

- **Limited Damage**: An exploit here can affect user data and can be used to launch attacks on more privileged rings, but typically can't directly access system-level resources.
- **Sandboxing**: Modern operating systems use techniques like sandboxing to limit the impact of exploits at this level even further.

### Examples

- **User-level Malware**: Trojans, ransomware, and other forms of malware often start their lifecycle executing in Ring 3 before attempting privilege escalation.
- **Common Software**: Almost all the software that you interact with on a daily basis runs in this ring, from your web browser to your favorite games.
