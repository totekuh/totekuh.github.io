---
title: Memory Corruption Vulnerabilities
date: 2023-08-26 04:20:00
#categories: [TOP_CATEGORIE, SUB_CATEGORIE]
#tags: [TAG]     # TAG names should always be lowercase
---

## Integer Overflow

### Description 

Making a number too big for its data type causes it to wrap around and start from a low value again. 

This can lead to incorrect memory allocation and buffer overflows. Integer overflows are often overlooked but can be very impactful. 

They can serve as the initial step in a chain of exploits, leading to more severe vulnerabilities.

### Example

```c
unsigned int size = UINT_MAX;
size += 1;  // Wraps around
char *buffer = malloc(size);
```

### Functions to Look For

Arithmetic operations (+, -, *, /), `malloc()`

### Exploit Development

- Difficulty 3/10 - "Almost too easy." 

Exploiting integer overflows usually involves manipulating calculations to cause buffer overflows or incorrect memory allocations.

---

## Buffer Overflow

### Description

Writing more data into a memory space than it can hold causes it to spill over into adjacent memory. 

This is one of the oldest and most common vulnerabilities. It's often the first thing taught in ethical hacking courses. 

Despite its age, it remains prevalent in modern software, from legacy systems to newly developed applications.

### Example

```c
char buffer[10];
strcpy(buffer, "TooLongString");
```

### Functions to Look For 

`strcpy()`, `strcat()`, `gets()`

### Exploit Development

- Difficulty 4/10 - "Like a walk in the park."

Exploits often involve injecting a payload into the buffer and redirecting the program's execution to it. 

A classic exploit that remains prevalent despite its age.

---

## Double Free

### Description

Freeing the same memory block twice can corrupt memory and lead to other issues. 

This is less common but can be very dangerous if exploited. 

Double frees can mess up the memory allocator's internal structures, leading to unpredictable behavior. 
They can also serve as a stepping stone to more complex exploits.

### Example

```c
int *ptr = malloc(10 * sizeof(int));
free(ptr);
free(ptr);  // Oops
```

### Functions to Look For

`free()`, `delete`

### Exploit Development

- Difficulty 5/10 - "Moderate effort needed." 

Exploits aim to corrupt the memory allocator's metadata, leading to arbitrary code execution or information leaks. 
Requires a deep understanding of heap structures.

---

## Stack Buffer Overflow

### Description

A special case of buffer overflow that happens in the stack, potentially overwriting important control data like function return addresses. 
Often leads to arbitrary code execution. 

Stack overflows have been a favorite among exploit developers for decades. 

They are a well-trodden path in the world of cybersecurity, often exploited in Capture The Flag (CTF) challenges.

### Example

```c
void function(char *input) {
    char buffer[50];
    strcpy(buffer, input);
}
```

### Functions to Look For

`strcpy()`, `sprintf()`, `strcat()`

### Exploit Development

- Difficulty 6/10 - "Requires some effort but doable." 

Often exploited by overwriting the return address on the stack, redirecting the program to execute a malicious payload. 

---

## Format String Vulnerability

### Description

Using unfiltered user input as a format string can read from or write to memory. 

This can be exploited to leak sensitive information or even write to arbitrary memory locations. 

Although less common these days, format string vulnerabilities still appear in legacy code and can be a goldmine for adversaries looking to leak information or manipulate memory.

### Example

```c
char *user_input = "%x %x %x";
printf(user_input);  // Should be printf("%s", user_input);
```

### Functions to Look For

`printf()`, `sprintf()`, `snprintf()`

### Exploit Development

- Difficulty 6/10 - "Requires some effort but doable." 

Exploits can read from or write to arbitrary memory locations. 
Complexity often lies in crafting the right format string, making it versatile but challenging.

---

## Heap Buffer Overflow

### Description

Like a stack buffer overflow, but in the heap, which is dynamically allocated memory. 
Heap overflows can also lead to code execution, but are generally harder to exploit. 

The heap is less predictable than the stack, making this a more complex vulnerability to exploit. 
Heap overflows often require a deep understanding of memory management and the specific heap implementation used.

### Example

```c
char *buffer = malloc(10);
strcpy(buffer, "TooLongString");
```

### Functions to Look For

`strcpy()`, `strcat()`, `memcpy()`

### Exploit Development

- Difficulty 7/10 - "Expect hours of pain." 

Generally harder to exploit due to heap unpredictability. 
Requires a deep understanding of heap internals and often involves multiple steps for successful exploitation.

---

## Use-After-Free

### Description

Using a memory pointer after you've already freed it can lead to unpredictable behavior. 

This can be exploited to execute arbitrary code. 
Modern systems have some protections, but skilled adversaries can bypass them. 

Use-After-Free vulnerabilities often require a multi-step exploitation process and may involve chaining multiple vulnerabilities together for a successful exploit.

### Example

```c
int *ptr = malloc(10 * sizeof(int));
free(ptr);
*ptr = 42;  // Bad idea
```

### Functions to Look For

`free()`, `delete`, `realloc()`

### Exploit Development

- Difficulty 8/10 - "A real headache." 

Often involves reallocating the freed memory with attacker-controlled data. 
Complex and may require chaining multiple vulnerabilities for a successful exploit.
