---
title: The GOT Overwrite Attack
date: 2023-09-08 04:20:00
#categories: [TOP_CATEGORIE, SUB_CATEGORIE]
#tags: [TAG]     # TAG names should always be lowercase
---

Modifying the Global Offset Table (GOT) is one of the common techniques to hook functions in Linux ELF binaries. 
Understanding GOT, PLT, and how dynamic linking works is crucial for this. 

Below's a brief rundown.

## Dynamic Linking

In dynamically linked executables, function calls to external libraries (like `libc`, `libm`, etc.) aren't resolved until the program starts running. 
This is in contrast to statically linked executables, where all library code is included in the binary at compile-time.

### Procedure Linkage Table (PLT) and Global Offset Table (GOT)

When a program starts, the dynamic linker resolves these external functions, usually lazily (i.e., the first time each function is called).

- **Procedure Linkage Table (PLT)**: This is basically a collection of stubs for external functions. When an external function is called, the call actually goes to its stub in the PLT. This stub then jumps to the actual function address, which is stored in the GOT. The first time a PLT stub is called, it redirects to a piece of code that asks the dynamic linker to resolve the actual address of the function and store it in the GOT. Subsequent calls will jump directly to the actual function thanks to the updated GOT entry.
- **Global Offset Table (GOT)**: This is a table used to hold addresses of external functions and variables. Initially, GOT entries point back to code in the PLT. These are updated (or "resolved") to point to the actual function or variable addresses the first time they are accessed.

### Hooking via GOT

If you can change an entry in the GOT to point to your function instead of the original one, then calls to the original function will transparently get redirected to your hook. 

This is typically done in one of two ways:

- **Preloading**: With `LD_PRELOAD`, you can insert a custom dynamic library before others, which can override certain function calls, causing them to be resolved to your implementations rather than the original ones. But this needs to be set up before the program starts.
- **Manual Injection**: If the program is already running, you can attach a debugger or use `ptrace` to change the GOT entry for the function, making it point to your hook function loaded into the process address space.

## The Basic Concept

The main idea behind a GOT overwrite attack is to replace a legitimate function address in the GOT with the address of malicious code (often called "shellcode"). 

This could be achieved through various means like buffer overflows, format string vulnerabilities, or other memory corruption issues. 

Once the GOT entry is overwritten, the next call to that function will jump to your malicious code instead.

## Anatomy of a GOT Overwrite Attack

- **Find a Vulnerability**: First, you'll need a way to corrupt memory, such as a buffer overflow or format string vulnerability.
- **Locate GOT Entry**: Use tools like `objdump`, `readelf`, or dynamic analysis to locate the GOT entry for the target function you want to overwrite.
- **Bypass Protections**: Modern systems employ various countermeasures like ASLR (Address Space Layout Randomization), stack canaries, and non-executable stacks. Techniques like information leakage or ROP (Return-Oriented Programming) could be used to bypass these.
- **Overwrite GOT**: Exploit the vulnerability to overwrite the GOT entry of the target function with the address of your shellcode or a ROP gadget.
- **Trigger the Call**: Once the GOT entry is overwritten, the next call to the target function will execute your code.

## Why it Matters

- **Stealth**: GOT overwrite attacks are often less detectable by intrusion detection/prevention systems compared to more brute-force methods like overwriting the return address on the stack.
- **Persistence**: Once a GOT entry is overwritten, every subsequent call to that function will execute the malicious code, making the attack persistent across multiple function invocations.
- **Fine-grained Control**: Unlike overwriting a return address, which affects the program flow immediately, a GOT overwrite only takes effect the next time the overwritten function is called, giving you more control over when your payload is executed.

## Countermeasures

- **RELRO**: Read-only RELRO makes the GOT read-only after initialization, preventing overwrites.
- **ASLR**: Randomizes the base addresses of loaded libraries, making it harder to predict the location of specific functions.
- **CFI**: Control Flow Integrity mechanisms can prevent the jumping to unexpected addresses, thus mitigating the effect of a GOT overwrite.



