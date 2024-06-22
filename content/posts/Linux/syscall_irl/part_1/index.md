---
title: "syscall_irl - Part I: Calling Convention"
subtitle: "Deep dive into Linux system call, based on Linux-6.7 and glibc-2.38"
date: 2024-01-18T21:30:45+08:00
lastmod: 2024-01-18T21:30:45+08:00
draft: false
description: "A full picture of Linux system call"
tags:
  - Operating System
  - Linux
  - Kernel
categories:
  - Linux
series:
  - syscall_irl
hiddenFromHomePage: false
hiddenFromSearch: false
featuredImage: ""
featuredImagePreview: ""
avatarURL : "favicon.svg"
toc:
  enable: true
math:
  enable: true
lightgallery: false
license: "CC BY-NC-ND"
---
<!-- Summary -->

In the Linux world, **syscall** in most case is the only way for userspace programs to interact with kernel, and utilize the full power that the Linux kernel offers.

In this series, we will take a deep dive into Linux system call, not theriotically, but practically. We will start from the very beginning, and gradually build up a full picture of Linux system call.

<!--more-->

<!-- Main Content -->

## Intro

It's easy to do a syscall in C code, like the following:

```c
// write.c
#include <unistd.h>
int main() {
    write(1, "Hello World!\n", 13);
    return 0;
}

/*
$ gcc -o write write.c && ./write
Hello, World!
*/
```

This simple example does only one thing: print `"Hello World!"` to file descriptor `1`, which stands for `stdout`. But what if I want to do the same thing in other language?

Most languages simply reused the same library that C uses, which is called `libc`. There are many implementations of `libc`, but the most popular one is [GNU C Library](https://www.gnu.org/software/libc/), or `glibc` for short. `glibc` is the default `libc` implementation for most Linux distributions, there are also other implementations like [musl](https://musl.libc.org/) that provides different features.

You may also heard that Go can do syscall without `libc`[^1] because it has its own runtime that can do syscall directly, so Go program could be built *totally static* and can run without any dependency. That makes Go program very portable, especially suitable for ops-tools that need to run on different environments.

So it seems that syscall can be language-agnostic, and there must be some common protocols that all languages can follow, that is, the [**ABI**](https://en.wikipedia.org/wiki/Application_binary_interface).

In the context of syscall, the most significant part of ABI is [**Calling Convention**](https://en.wikipedia.org/wiki/Calling_convention), which basically defines what to do when you want to do a procedure call in the binary level.

With following the calling convention, we can not only do syscall in different languages, and can also call procedures written in another language. The latter case is even more often because most languages do syscall by calling a C syscall wrapper defined in `libc`.

Before we dive into the details of syscall, let's take a look at some normal procedure calls first and see what calling convention looks like.

### Example: `sum3`

```c
// sum3.c
int sum3(int a, int b, int c) {
    return a + b + c;
}
int main(void) {
    int sum = sum3(1, 2, 3);
    return 0;
}
```

The `main` function in this simple C program calls a function `sum3` to calculate the sum of three integers, and save the result to variable `sum`. Let's compile and disassemble it to see what assembly code it generates:

```asm
# gcc -O0 -o sum3 sum3.c && objdump -d --no-show-raw-insn sum3
# ...
0000000000001119 <sum3>:
    1119:	push   %rbp
    111a:	mov    %rsp,%rbp
    111d:	mov    %edi,-0x4(%rbp)
    1120:	mov    %esi,-0x8(%rbp)
    1123:	mov    %edx,-0xc(%rbp)
    1126:	mov    -0x4(%rbp),%edx
    1129:	mov    -0x8(%rbp),%eax
    112c:	add    %eax,%edx
    112e:	mov    -0xc(%rbp),%eax
    1131:	add    %edx,%eax
    1133:	pop    %rbp
    1134:	ret

0000000000001135 <main>:
    1135:	push   %rbp
    1136:	mov    %rsp,%rbp
    1139:	sub    $0x10,%rsp
    113d:	mov    $0x3,%edx
    1142:	mov    $0x2,%esi
    1147:	mov    $0x1,%edi
    114c:	call   1119 <sum3>
    1151:	mov    %eax,-0x4(%rbp) # sum = %eax
    1154:	mov    $0x0,%eax
    1159:	leave
    115a:	ret
# ...
```

As we can see, in the `main` function, first the parameters `(1,2,3)` are placed in registers `%edi`, `%esi`, `%edx` respectively, then does the `call` instruction with `1119`, the address of `sum3`, as operand, and finally the return value is placed in register `%eax`.

So let's conclude: **first, place parameters in registers in a proper order, then execute the `call` instruction with the address of the function you want to call as operand. After the function returns, you can get the return value from register `%eax`.**

### Example: `bigret`

But here comes a question: since all parameters and return value are placed in registers in this example, and registers are typically only 64-bit in size, what if we want to pass a parameter or return a value that is larger than 64-bit, like a `struct`? Let's find out with some experiments:

```c
// bigret.c
typedef unsigned long long u64;

struct big {
    u64 a, b, c;
};

struct big ret_big(u64 a, u64 b, u64 c) {
    return (struct big){a, b, c};
}

int main(void) {
    struct big big = ret_big(1, 2, 3);
    return 0;
}
```

Again, compile and disassemble:

```asm
# gcc -O0 -o bigret bigret.c && objdump -d --no-show-raw-insn bigret
# ...
0000000000001139 <ret_big>:
    1139:	push   %rbp
    113a:	mov    %rsp,%rbp
    113d:	mov    %rdi,-0x28(%rbp)
    1141:	mov    %rsi,-0x30(%rbp)
    1145:	mov    %rdx,-0x38(%rbp)
    1149:	mov    %rcx,-0x40(%rbp)
    114d:	mov    -0x28(%rbp),%rax
    1151:	mov    -0x30(%rbp),%rdx
    1155:	mov    %rdx,(%rax)
    1158:	mov    -0x28(%rbp),%rax
    115c:	mov    -0x38(%rbp),%rdx
    1160:	mov    %rdx,0x8(%rax)
    1164:	mov    -0x28(%rbp),%rax
    1168:	mov    -0x40(%rbp),%rdx
    116c:	mov    %rdx,0x10(%rax)
    1170:	mov    -0x28(%rbp),%rax
    1174:	pop    %rbp
    1175:	ret

0000000000001176 <main>:
    1176:	push   %rbp
    1177:	mov    %rsp,%rbp
    117a:	sub    $0x20,%rsp
    117e:	mov    %fs:0x28,%rax
    1187:	mov    %rax,-0x8(%rbp)
    118b:	xor    %eax,%eax
    118d:	lea    -0x20(%rbp),%rax
    1191:	mov    $0x3,%ecx
    1196:	mov    $0x2,%edx
    119b:	mov    $0x1,%esi
    11a0:	mov    %rax,%rdi
    11a3:	call   1139 <ret_big>
    11a8:	mov    $0x0,%eax
    11ad:	mov    -0x8(%rbp),%rdx
    11b1:	sub    %fs:0x28,%rdx
    11ba:	je     11c1 <main+0x4b>
    11bc:	call   1030 <__stack_chk_fail@plt>
    11c1:	leave
    11c2:	ret
# ...
```

Hmm...interesting, it looks like an address is passed as the first parameter to `ret_big` implicitly, and the return value is the same address. Let's see what's going on step by step:

In `main`:

1. `117a: sub $0x20,%rsp`: we all know that the stack grows from higher address to lower address, so subtract the stack pointer `$rsp`(register stack pointer) by `0x20(32)` actually allocate `32` bytes on stack, which in address range from `%rbp-0x20` to `%rbp`. We can see it as an `u64[4]` array.
2. `117e: mov %fs:0x28,%rax`: read a value from address `%fs+0x28` to `%rax`.
3. `1187: mov %rax,-0x8(%rbp)`: save the read value on stack at address `(%rbp-0x8)`, or `arr[3]`.
4. `118b: xor %eax,%eax`: set `%eax` to `0`.
5. `118d: lea -0x20(%rbp),%rax`: load the address of `%rbp-0x20` to `%rax`, which is `&arr[0]`.
6. `1191` - `11a0`: place parameters in registers in order with shifting by one position, since `$eax` is the first parameter now.
7. `113a call 1139 <ret_big>`: call `ret_big`.

The code in `ret_big` is a little verbose, but if we recompile it with flag `-O1`, it instantly become much simpler:

```asm
0000000000001119 <ret_big>:
    1119:	mov    %rdi,%rax
    111c:	mov    %rsi,(%rdi)
    111f:	mov    %rdx,0x8(%rdi)
    1123:	mov    %rcx,0x10(%rdi)
    1127:	ret
```

Since the first parameter `$rdi` is the address of the array `arr` that we allocated before, and the three parameters we passed to `ret_big` are placed in registers `$rsi`, `$rdx`, `$rcx` respectively, this code simply copy the three parameters to the array `arr` in order:

1. `111c: mov %rsi,(%rdi)`: `arr[0] = %rdi`.
2. `111f: mov %rdi,0x8(%rdi)`: `arr[1] = %rsi`.
3. `1123: mov %rcx,0x10(%rdi)`: `arr[2] = %rdx`.
4. `1127: ret`: return `arr`

Now it's clear, **if we want to return a large chunk of data which can not fit in a register, we pass an address for the return value and let the function save it at that address.**

Since we just pass an address, it might happen that the function write more data than we expected, which will cause [**buffer overflow**](https://en.wikipedia.org/wiki/Buffer_overflow) that may results in a segment error or worse, an [**ACE**](https://en.wikipedia.org/wiki/Arbitrary_code_execution). So how can we prevent this from happening?

### Canary: The Guardian of Stack

You might notice that the fourth instruction in `main`(step 3) put a secret value on stack at the location `arr[3]`, which is the last element of the array `arr` we allocated.

Most buffer overflow attacks are based on the fact that the attacker can take an unbounded string as input, and if we use `\0` as the input delimiter, then the program will write the user input along the buffer and overwrite the memory that doesn't belong to the buffer, which may stores the return address.

After `ret_big` returns, the `main` instantly check if the secret value is changed, that is, instructions from `11ad` to `11ba`. If the secret value is not changed, it means the following memory contents are also not changed too, so the program thinks it's safe and will jump to instruction at `<main+0x4b>`, which is `11c1`, and returns normally. But if not, it will assume the memory after that value is altered, and will call `__stack_chk_fail` to terminate the program to prevent more damages from happening.

This secret value is called [**Canary**](https://en.wikipedia.org/wiki/Buffer_overflow_protection#Canaries), and it is a common technique to defend buffer overflow attacks. This terminology itself is a reference to the historic practice of using canaries in coal mines to warn miners toxic gases, which is another somber story[^2].

## Calling Convention

There are many details defined by calling convention, since we are focusing on syscall topic, only the following details are important to us:

 - **Where parameters are placed.**
 - **The order in which parameters are passed.**
 - **How the stack changes during the call**
 - **How return values are delivered back to the caller.**
 - **Which registers are guaranteed to have the same value before and after the call.**

From the two examples above, we already know the first three, and rest of them is defined in the following specification(defines at `arch/x86/entry/calling.h` in Linux kernel source code):

```plain
x86 function call convention, 64-bit:
-------------------------------------
 arguments           |  callee-saved      | extra caller-saved | return
[callee-clobbered]   |                    | [callee-clobbered] |
---------------------------------------------------------------------------
rdi rsi rdx rcx r8-9 | rbx rbp [*] r12-15 | r10-11             | rax, rdx [**]

( rsp is obviously invariant across normal function calls. (gcc can 'merge'
  functions when it sees tail-call optimization possibilities) rflags is
  clobbered. Leftover arguments are passed over the stack frame.)

[*]  In the frame-pointers case rbp is fixed to the stack frame.

[**] for struct return values wider than 64 bits the return convention is a
     bit more complex: up to 128 bits width we return small structures
     straight in rax, rdx. For structures larger than that (3 words or
     larger) the caller puts a pointer to an on-stack return struct
     [allocated in the caller's stack frame] into the first argument - i.e.
     into rdi. All other arguments shift up by one in this case.
     Fortunately this case is rare in the kernel.
```

Normally, the `callee-saved` means the caller can assume that the value of the register is not changed after the call, so the function itself should save the origin value of the register before using it for other purposes. And the `callee-clobbered` means the caller can not assume that so it need to manually save it before the call if it want to use it after the call.

Now we have a necessary understanding of calling convention, let's go deeper and see how syscall is implemented.
[syscall_irl - Part II: Userspace Stub]({{< ref "posts/Linux/syscall_irl/part_2" >}})

[^1]: https://github.com/golang/sys/blob/master/unix/README.md
[^2]: https://en.wikipedia.org/wiki/Sentinel_species#Toxic_gases
