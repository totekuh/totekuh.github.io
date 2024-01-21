---
title: Import By Hash
date: 2023-11-13 04:20:00
categories: [Attack Chain, Payload Execution]
tags: [malware, buffer-overflow, windows]     # TAG names should always be lowercase
---

## Introduction

Adversaries continually develop methods to evade detection.
One such advanced technique is the "Import by Hash" method, primarily used in crafting stealthy malware.

This technique is more a form of obfuscation. 

Instead of directly referencing essential Windows API functions in the malware's code, which makes them easily identifiable, the Import by Hash method dynamically resolves these functions at runtime using unique hashes.

This process not only significantly complicates static analysis of the binary, it also provides a way to dynamically load any DLL into the process memory space by using the `LoadLibraryA` API from `kernel32.dll` and call any function from there.

![Import By Hash](/assets/img/import-by-hash.jpg)

## How It Works

- **Hash Generation**: A hashing algorithm is used to generate a unique hash value for each required Windows API function name. 
- **Runtime Resolution**: At execution time, your shellcode iterates through available APIs, computing their hashes and matching them with the pre-generated ones. Once a match is found, the corresponding API function is invoked.

## Advantages

- **Evasion**: Makes initial static analysis and detection more challenging.
- **Portability**: Ensures compatibility across different Windows versions. Since the method doesn't rely on hardcoded addresses, it's adaptable to various system environments.

## Links

- [https://www.ired.team/offensive-security/defense-evasion/windows-api-hashing-in-malware](https://www.ired.team/offensive-security/defense-evasion/windows-api-hashing-in-malware)
