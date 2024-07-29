---
title: "Syscall_irl"
subtitle: "Deep dive into Linux system call, based on Linux-6.6.6 and glibc-2.38"
date: 2024-07-28T22:51:05+08:00
lastmod: 2024-07-28T22:51:05+08:00
draft: false
description: "A full journey of Linux syscall from userspace to kernel"
tags:
  - Operating System
  - Linux
  - Kernel
categories:
series:

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

In the Linux world, **syscall** is typically the primary mechanism for userspace programs to interact with the kernel and leverage the full capabilities of the Linux kernel.

In this blog post, we will explore Linux system calls in-depth, not just theoretically but also through practical examples. We will start from the fundamentals and gradually build a comprehensive understanding of Linux system calls.

<!--more-->

<!-- Main Content -->

## Intro

It's straightforward to make a system call in C, as demonstrated by this simple example of the `write` system call:

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

This simple example does only one thing: to print `"Hello World!"` to `stdout`(file descriptor `1`). But what if I want to do the same thing in other programming language?

Most languages simply reuse the same standard library that C uses, which is called the C standard library or `libc`. While there are several implementations of `libc`, the most popular one is the [GNU C Library](https://www.gnu.org/software/libc/), commonly known as `glibc`. Glibc is the default `libc` implementation for most Linux distributions. But there are also other `libc` implementations, such as [musl](https://musl.libc.org/), which provide different features and capabilities. `musl` is commonly used for creating portable applications that doesn't rely on the version of `glibc` that comes with the distribution.

You may have also heard that Go can perform system calls without reply on `libc`[^1], that is because it has its own runtime that can directly interact with the system call interface. This allows Go programs to be built as fully static binaries, which can run without any external dependencies. This feature makes Go programs highly portable, especially suitable for running in containerized environments.

### Application Binary Interface

It seems that system calls can be language-agnostic, and there must be some common protocols that all languages can follow. This common interface is known as the [Application Binary Interface (ABI)](https://en.wikipedia.org/wiki/Application_binary_interface).

In the context of system calls, the most significant part of ABI is the [**Calling Convention**](https://en.wikipedia.org/wiki/Calling_convention), which essentially defines the low-level rules for how a procedure call is performed in the binary code.

Since Linux is primarily written in C, the system call interface is designed to be compatible with the C calling convention, which is also the most common calling convention used globally. By adhering to the C calling convention, developers can not only perform system calls in different programming languages, they can also call procedures written in another language, because most languages use C calling convention for their [FFI](https://en.wikipedia.org/wiki/Foreign_function_interface) feature. The latter case is even more common, as most languages won't interact with the system call interface directly in binary level, but by calling a C-based system call wrapper defined in the `libc`. We can say that the C calling convention is the lingua franca of the programming world.

Before delving into the details of system calls, let's first take a look at some normal procedure calls and examine what the calling convention entails.

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

The `main` function in this simple C program calls a function `sum3` to calculate the sum of three integers, and saves the result to the variable `sum`. Let's compile and disassemble the program to examine the generated assembly code:

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

As we can see, in the `main` function, the parameters `(1, 2, 3)` are first placed in the registers `%edi`, `%esi`, and `%edx` respectively. Then, the `call` instruction is executed, with the address `1119` (the address of the `sum3` function) as the operand. Finally, the return value is placed in the `%eax` register.

To summarize: First, the parameters are placed in the appropriate registers in a specific order, then the call instruction is executed with the address of the function to be called as the operand. After the function returns, the return value can be retrieved from the `%eax` register.

### Example: `bigret`

But here arises an important question: since all parameters and the return value are placed in registers in this example, and registers are typically only 64-bit in size, what if we want to pass a parameter or return a value that is larger than 64-bit, like a `struct`? Let's conduct some experiments to find out.

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

Hmm, that's quite interesting. It appears that an address is implicitly passed as the first parameter to the `ret_big` function, and the return value is also at the same address. Let's examine this step-by-step:

In the `main` function:

1. `117a: sub $0x20,%rsp`: allocate `32` bytes on the stack by subtracting `0x20(32)` from the stack pointer register `%rsp`. This can be viewed as declare an `uint64_t[4]` array on stack.
2. `117e: mov %fs:0x28,%rax`: read a value from address `%fs+0x28` and store it in the register `%rax`.
3. `1187: mov %rax,-0x8(%rbp)`: save the read value on the stack at the address `(%rbp-0x8)`, which corresponds to `arr[3]`.
4. `118b: xor %eax,%eax`: clear register `%eax` to `0`.
5. `118d: lea -0x20(%rbp),%rax`: load the address of `%rbp-0x20`(`&arr[0]`) to `%rax`.
6. `1191` - `11a0`: place the parameters in the registers in the correct order, with a shift by one position, since `$eax` is now the first parameter.
7. `113a call 1139 <ret_big>`: call `ret_big`.

The code in the `ret_big` function appears a bit verbose, but if we recompile it with the `-O1` optimization flag, it becomes much simpler:

```asm
0000000000001119 <ret_big>:
    1119:	mov    %rdi,%rax
    111c:	mov    %rsi,(%rdi)
    111f:	mov    %rdx,0x8(%rdi)
    1123:	mov    %rcx,0x10(%rdi)
    1127:	ret
```

Since the first parameter `$rdi` is the address of the array `arr` that we allocated earlier, and the three parameters we passed to `ret_big` are placed in the registers `$rsi`, `$rdx`, and `$rcx` respectively, this optimized code simply copies the three parameters to the array `arr` in order:

1. `111c: mov %rsi,(%rdi)`: `arr[0] = %rdi`.
2. `111f: mov %rdi,0x8(%rdi)`: `arr[1] = %rsi`.
3. `1123: mov %rcx,0x10(%rdi)`: `arr[2] = %rdx`.
4. `1127: ret`: return `arr`

Now it's clear. If we want to return a large data structure that cannot fit into a single register, we can pass the address of a buffer as the return value parameter and let the function save the data at that address.

However, this approach introduces a potential risk of [**buffer overflow**](https://en.wikipedia.org/wiki/Buffer_overflow), as the function might write more data than the allocated buffer can accommodate. This could result in a segment fault error, or even worse, an [Arbitrary Code Execution](https://en.wikipedia.org/wiki/Arbitrary_code_execution) vulnerability. So, how can we prevent this from happening?

### Canary: The Guardian of the stack

You might notice that in the `main` function(step 3), the fourth instruction places a secret value on the stack at the location `arr[3]`, which is the last element of the array `arr` we allocated.

Most buffer overflow attacks exploit the fact that the attacker can provide an unbounded string as input, and if the program uses a null character (`\0`) as the input delimiter, it will write the user input along the buffer and overwrite the memory that does not belong to the buffer, which may contain the return address.

After `ret_big` returns, the `main` function immediately checks if the secret value has been changed (instructions from `11ad` to `11ba`). If the secret value remains unchanged, it means the memory contents following it have also not been altered, so the program considers it safe and jumps to the instruction at `<main+0x4b>`(`11c1`), and returns normally. However, if the secret value has been changed, the program assumes the memory after that value has been altered too, and it will call the `__stack_chk_fail` function to terminate the program and prevent further damage.

> This secret value is a random number known as a [**Canary**](https://en.wikipedia.org/wiki/Buffer_overflow_protection#Canaries), and it is a common technique used to defend against buffer overflow attacks. The term "Canary" is a reference to the historic practice of using canaries in coal mines to warn miners of toxic gases, which is another somber story[^2].

### x86_64 Calling Convention

There are many details defined by the calling convention, but for the purpose of our discussion on system calls, the following specifications are the most important:

 - **Where parameters are placed.**
 - **The order in which parameters are passed.**
 - **How the stack changes during the call**
 - **How return values are delivered back to the caller.**
 - **Which registers are guaranteed to have the same value before and after the call.**

From the two examples above, we already know the first three, and remain of them is defined in the following specification, you can also find it at [here](https://elixir.bootlin.com/linux/v6.6.6/source/arch/x86/entry/calling.h):

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

Normally, the *callee-save*" means the caller can assume that the value of the register is not changed after the function call, so the callee function itself is responsible for saving the original value in these registers before using it for other purposes. On the other hand, the *callee-clobbered* means the caller cannot assume the register value is preserved, so the caller needs to manually them before the function call if it wants to use it afterwards.

Now that we have a necessary understanding of the calling convention, let's go deeper and examine how system calls are implemented.

## Userspace Stub

So how does *syscall* happens, actually? If you look up the definition of the `write`, you will see the following function signature:

```c
/* Write N bytes of BUF to FD.  Return the number written, or -1.

   This function is a cancellation point and therefore not marked with
   __THROW.  */
extern ssize_t write (int __fd, const void *__buf, size_t __n) __wur
    __attr_access ((__read_only__, 2, 3));
```

But we still don't know exactly what happens when we call it. All we know is that it's like a normal C function: we call it, and everything gets done.

### `write` in userspace


Since the source code of `libc` is open to everyone, we can look up how `write` is implemented. But before doing that, let's use `gdb` to find out what actually happens.

```c
// write.c
#include <unistd.h>
int main() {
    write(1, "Hello, World!\n", 14);
    return 0;
}
```

After compiling this simple code with `gcc -O1 -g -o write write.c`[^3], we get an executable named `write`. All it does is print the string "Hello, World!".

```plain
$ ./write
Hello, World!
```

Now we'll use `gdb` to run the executable again.

```plain
$ gdb write
...(Messages printed at start)
(gdb)
```

First, set a breakpoint at the `main` symbol to stop at the entry point. Then enable the `disassemble-next-line` option and run the program.

```gdb
(gdb) b main
Breakpoint 1 at 0x1139: file write.c, line 3.
(gdb) set disassemble-next-line on
(gdb) show disassemble-next-line
Debugger's willingness to use disassemble-next-line is on.
(gdb) r
Starting program: ./write

Breakpoint 1, main () at write.c:3
3       int main() {
=> 0x0000555555555139 <main+0>: 48 83 ec 08             sub    $0x8,%rsp
```

We can see from the assembly code that the stack grows by `0x8` bytes, giving `main` a stack size of `0x8` bytes. However, that's not our focus. Let's execute this program instruction-by-instruction using `si` (step instruction).

```gdb
(gdb) si
4         write(1, "Hello, World!\n", 14);
=> 0x000055555555513d <main+4>: ba 0e 00 00 00          mov    $0xe,%edx
   0x0000555555555142 <main+9>: 48 8d 35 bb 0e 00 00    lea    0xebb(%rip),%rsi        # 0x555555556004
   0x0000555555555149 <main+16>:        bf 01 00 00 00          mov    $0x1,%edi
   0x000055555555514e <main+21>:        e8 dd fe ff ff          call   0x555555555030 <write@plt>
```

From the last blog, we know that arguments are passed by registers in the order of `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and `r9`. We can see that `rdi`, `rsi`, `edx` are assigned to `0x1(1)`, `%rip + 0xebb` (which is annotated as `0x555555556004`), and `0xe(14)` respectively. That's exactly what we passed to the `write` function. The second argument(`"Hello, World!\n"`) is passed by pointer though, we can verify this by checking what resides at this pointer:

```gdb
(gdb) x/s 0x555555556004
0x555555556004: "Hello, World!\n"
```

OK, now that we understand argument passing, let's dive into the `write` function.

```gdb
(gdb) s
__GI___libc_write (fd=fd@entry=1, buf=buf@entry=0x555555556004, nbytes=nbytes@entry=14) at ../sysdeps/unix/sysv/linux/write.c:25

```

We can even see what is passed to which parameter thanks to the GDB debuginfod feature, but we already know that, so let's print out the assembly code of the `__GI___libc_write`[^4]:

```gdb
(gdb) x/16i $pc
=> 0x7ffff7e9b4f0 <__GI___libc_write>:  endbr64
   0x7ffff7e9b4f4 <__GI___libc_write+4>:        cmpb   $0x0,0xe0b45(%rip)        # 0x7ffff7f7c040 <__libc_single_threaded>
   0x7ffff7e9b4fb <__GI___libc_write+11>:       je     0x7ffff7e9b510 <__GI___libc_write+32>
   0x7ffff7e9b4fd <__GI___libc_write+13>:       mov    $0x1,%eax
   0x7ffff7e9b502 <__GI___libc_write+18>:       syscall
   0x7ffff7e9b504 <__GI___libc_write+20>:       cmp    $0xfffffffffffff000,%rax
   0x7ffff7e9b50a <__GI___libc_write+26>:       ja     0x7ffff7e9b560 <__GI___libc_write+112>
   0x7ffff7e9b50c <__GI___libc_write+28>:       ret
   0x7ffff7e9b50d <__GI___libc_write+29>:       nopl   (%rax)
   0x7ffff7e9b510 <__GI___libc_write+32>:       push   %rbp
   0x7ffff7e9b511 <__GI___libc_write+33>:       mov    %rsp,%rbp
   0x7ffff7e9b514 <__GI___libc_write+36>:       sub    $0x20,%rsp
   0x7ffff7e9b518 <__GI___libc_write+40>:       mov    %rdx,-0x18(%rbp)
   0x7ffff7e9b51c <__GI___libc_write+44>:       mov    %rsi,-0x10(%rbp)
   0x7ffff7e9b520 <__GI___libc_write+48>:       mov    %edi,-0x8(%rbp)
   0x7ffff7e9b523 <__GI___libc_write+51>:       call   0x7ffff7e20d90 <__GI___pthread_enable_asynccancel>
```

Well, it's quite verbose, but we only need to focus on two lines:

```gdb
   0x7ffff7e9b4fd <__GI___libc_write+13>:       mov    $0x1,%eax
   0x7ffff7e9b502 <__GI___libc_write+18>:       syscall
```

These codes simply set the `eax` register to `0x1` and then execute the `syscall` instruction.

```gdb
(gdb) x/i $pc
=> 0x7ffff7e9b502 <__GI___libc_write+18>:       syscall
(gdb) si
Hello, World!
(gdb)
```

After the `syscall` instruction returns, we can see "Hello, World!" from the GDB console. The entire process can be summarized in three steps:

1. Pass the arguments following the C Calling Convention.
2. Set the `rax` register (or `eax` in 32-bit mode) to a number specified as the *syscall number* in Linux documentation.
3. Execute the `syscall` instruction[^5].

This is surprisingly simple, we can just set an extra register `rax` to the required syscall number, replace the `call` instruction with `syscall`, and an normal C function call becomes a syscall. We can even create our own `write` function with just the two lines of assembly code above.

However, there is actually another small difference in the calling convention: for syscalls, the fourth argument is passed via register `r10` instead of `rcx`. This is because `syscall` need to store the address of the next userspace instruction in register `rcx`, so after returning from kernel, execution can continue at that saved address.

### Glibc syscall stub

Previously, we use GDB to understand what happens with `write` under the hood.  Now, let's examine the code to see how `write` is implemented. You can skip this chapter if you're not familiar with or interested in C macro magic.

The following code is based on `glibc-2.38`, which you can download from the [GNU FTP server](https://ftp.gnu.org/gnu/glibc/glibc-2.38.tar.xz). The definition of `write` isn't straightforward; it involves expanding complex macros dynamically. After manually expanding these magic-like macros, the simplified `write.c` looks like this:

```c
define __glibc_unlikely

/* NB: This also works when X is an array.  For an array X,  type of
   (X) - (X) is ptrdiff_t, which is signed, since size of ptrdiff_t
   == size of pointer, cast is a NOP.   */
#define TYPEFY1(X) __typeof__ ((X) - (X))
/* Explicit cast the argument.  */
#define ARGIFY(X) ((TYPEFY1 (X)) (X))
/* Create a variable 'name' based on type of variable 'X' to avoid
   explicit types.  */
#define TYPEFY(X, name) __typeof__ (ARGIFY (X)) name

typedef int ssize_t;
typedef unsigned int size_t;

extern int __libc_single_threaded;
extern int __libc_errno;

int __pthread_enable_asynccancel();
void __pthread_disable_asynccancel(int);

#define __NR_write 1

#define internal_syscall3(number, arg1, arg2, arg3)			\
({									\
    unsigned long int resultvar;					\
    TYPEFY (arg3, __arg3) = ARGIFY (arg3);			 	\
    TYPEFY (arg2, __arg2) = ARGIFY (arg2);			 	\
    TYPEFY (arg1, __arg1) = ARGIFY (arg1);			 	\
    register TYPEFY (arg3, _a3) asm ("rdx") = __arg3;			\
    register TYPEFY (arg2, _a2) asm ("rsi") = __arg2;			\
    register TYPEFY (arg1, _a1) asm ("rdi") = __arg1;			\
    asm volatile (							\
    "syscall\n\t"							\
    : "=a" (resultvar)							\
    : "0" (number), "r" (_a1), "r" (_a2), "r" (_a3)			\
    : "memory", REGISTERS_CLOBBERED_BY_SYSCALL);			\
    (long int) resultvar;						\
})

/* Write NBYTES of BUF to FD.  Return the number written, or -1.  */
ssize_t
__libc_write (int fd, const void *buf, size_t nbytes)
{
    long int ret;
    if (__libc_single_threaded != 0)
    {
        long int sc_ret = internal_syscall3 (__NR_write, fd, buf, nbytes);
        if (__glibc_unlikely ((unsigned long int) (sc_ret) > -4096UL)) {
            __libc_errno = -sc_ret;
            ret = -1L;
        } else {
            ret = sc_ret;
        }
    }
    else
    {
        int sc_cancel_oldtype = __pthread_enable_asynccancel();
        long int sc_ret = internal_syscall3 (__NR_write, fd, buf, nbytes);
        if (__glibc_unlikely ((unsigned long int) (sc_ret) > -4096UL)) {
            __libc_errno = -sc_ret;
            ret = -1L;
        } else {
            ret = sc_ret;
        }
        __pthread_disable_asynccancel(sc_cancel_oldtype);
    }
    return ret;
}
libc_hidden_def (__libc_write)

// weak_alias (__libc_write, __write)
// libc_hidden_weak (__write)
// weak_alias (__libc_write, write)
// libc_hidden_weak (write)

int main(void) {
    write(1, "Hello, world!\n", 14);
    return 0;
}
```

The main part of `write` is in `__libc_write`, where we can see the `pthread` synchronization guard that we saw earlier in the GDB disassembly. The syscall number for `write` is defined in the macro `__NR_write`, which is `1`. The actual arguments are already passed outside of the `write`, so the internal syscall stub only cares about the number of arguments. Here, we have `internal_syscall3`, which use inline assembly to call the instruction `syscall`. However, if we look at the `internal_syscall4`, we will notice some differences:

```c
#define internal_syscall4(number, arg1, arg2, arg3, arg4)		\
({									\
    unsigned long int resultvar;					\
    TYPEFY (arg4, __arg4) = ARGIFY (arg4);			 	\
    TYPEFY (arg3, __arg3) = ARGIFY (arg3);			 	\
    TYPEFY (arg2, __arg2) = ARGIFY (arg2);			 	\
    TYPEFY (arg1, __arg1) = ARGIFY (arg1);			 	\
    register TYPEFY (arg4, _a4) asm ("r10") = __arg4;			\
    register TYPEFY (arg3, _a3) asm ("rdx") = __arg3;			\
    register TYPEFY (arg2, _a2) asm ("rsi") = __arg2;			\
    register TYPEFY (arg1, _a1) asm ("rdi") = __arg1;			\
    asm volatile (							\
    "syscall\n\t"							\
    : "=a" (resultvar)							\
    : "0" (number), "r" (_a1), "r" (_a2), "r" (_a3), "r" (_a4)		\
    : "memory", REGISTERS_CLOBBERED_BY_SYSCALL);			\
    (long int) resultvar;						\
})
```

As we mentioned, the fourth argument is assigned to register `r10` instead of `rcx`; besides that, nothing is different.

### Prepare for entering kernel space

From the userspace perspective, we only see an instruction being executed, and the job is done. But what happens behind the scenes? The [online x86 reference](https://www.felixcloutier.com/x86/) gives an detailed operation specification of the `syscall` instruction:

```plain
IF (CS.L ≠ 1 ) or (IA32_EFER.LMA ≠ 1) or (IA32_EFER.SCE ≠ 1)
(* Not in 64-Bit Mode or SYSCALL/SYSRET not enabled in IA32_EFER *)
    THEN #UD;
FI;
RCX := RIP; (* Will contain address of next instruction *)
RIP := IA32_LSTAR;
R11 := RFLAGS;
RFLAGS := RFLAGS AND NOT(IA32_FMASK);
CS.Selector := IA32_STAR[47:32] AND FFFCH (* Operating system provides CS; RPL forced to 0 *)
(* Set rest of CS to a fixed value *)
CS.Base := 0;
                (* Flat segment *)
CS.Limit := FFFFFH;
                (* With 4-KByte granularity, implies a 4-GByte limit *)
CS.Type := 11;
                (* Execute/read code, accessed *)
CS.S := 1;
CS.DPL := 0;
CS.P := 1;
CS.L := 1;
                (* Entry is to 64-bit mode *)
CS.D := 0;
                (* Required if CS.L = 1 *)
CS.G := 1;
                (* 4-KByte granularity *)
IF ShadowStackEnabled(CPL)
    THEN (* adjust so bits 63:N get the value of bit N–1, where N is the CPU’s maximum linear-address width *)
        IA32_PL3_SSP := LA_adjust(SSP);
            (* With shadow stacks enabled the system call is supported from Ring 3 to Ring 0 *)
            (* OS supporting Ring 0 to Ring 0 system calls or Ring 1/2 to ring 0 system call *)
            (* Must preserve the contents of IA32_PL3_SSP to avoid losing ring 3 state *)
FI;
CPL := 0;
IF ShadowStackEnabled(CPL)
    SSP := 0;
FI;
IF EndbranchEnabled(CPL)
    IA32_S_CET.TRACKER = WAIT_FOR_ENDBRANCH
    IA32_S_CET.SUPPRESS = 0
FI;
SS.Selector := IA32_STAR[47:32] + 8;
                (* SS just above CS *)
(* Set rest of SS to a fixed value *)
SS.Base := 0;
                (* Flat segment *)
SS.Limit := FFFFFH;
                (* With 4-KByte granularity, implies a 4-GByte limit *)
SS.Type := 3;
                (* Read/write data, accessed *)
SS.S := 1;
SS.DPL := 0;
SS.P := 1;
SS.B := 1;
                (* 32-bit stack segment *)
SS.G := 1;
                (* 4-KByte granularity *)
```

The pseudo code above contains many variable-like identifiers that are actually registers, including [General Purpose Registers](https://wiki.osdev.org/CPU_Registers_x86-64#General_Purpose_Registers) (`RCX`, `R11`), [Pointer Registers](https://wiki.osdev.org/CPU_Registers_x86-64#Pointer_Registers) (`RIP`), [Segment Registers](https://wiki.osdev.org/CPU_Registers_x86-64#Segment_Registers) (`CS`, `SS`), the [RFLAGS Register](https://wiki.osdev.org/CPU_Registers_x86-64#RFLAGS_Register) (`RFLAGS`), and [Model-Specific Registers (MSRs)](https://wiki.osdev.org/CPU_Registers_x86-64#MSRs) (`IA32_EFER`, `IA32_LSTAR`,  `IA32_FMASK`, `IA32_PL3_SSP`). The operator `.` accesses specific bit fields within these registers. Despite the numerous operations occurring, we only need to focus on a few:

```plain
RCX := RIP; (* Save address of next instruction(userspace) to RCX *)
RIP := IA32_LSTAR; (* Set address of next instruction(kernel) to IA32-LSTAR *)
R11 := RFLAGS; (* Save old RFLAGS to R11 *)
RFLAGS := RFLAGS AND NOT(IA32_FMASK); (* Clear some flags *)
CPL := 0; (* Set current privilege level to 0, also known as Protection Ring *)
```

Basically, the `syscall` instruction backs up some userspace context information (such as the return address), sets the next instruction pointer (`RIP`) to somewhere in kernel space (`IA32-LSTAR`), and switches the protection ring to `0`, which is kernel mode. For security reasons, only in this mode can the CPU execute kernel code.

It's important to note that all of this occurs within a single `syscall` instruction, so set `RIP` to point to kernel space does make sense. After executing this instruction, we are finally in kernel space.

## Prepare bootable kernel

To examine what happened in the kernel space, we will use QEMU[^6] and GDB to debugging a running kernel. But first, we need to create a bootable Linux kernel image, which means we need to compile the kernel.

### Compiling the Linux kernel

For a general C project, the basic build process typically follows three steps, and the Linux kernel is no exception:

#### Get the source

You can obtain the source code for every released Linux kernel version from the official [kernel.org](https://kernel.org) website. In this post, I will use version [6.6.6](https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.xz), but you can use any version you prefer. Additionally, make sure to download the [GPG signature file for the kernel version](https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.10.2.tar.sign) you choose.

```shell
# Download source
curl -OL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.xz
# Download the corresponding signature
curl -OL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.sign
# Uncompressing source
unxz linux-6.6.6.tar.xz
# Import keys belonging to Linus Torvalds and Greg Kroah-Hartman
gpg2 --locate-keys torvalds@kernel.org gregkh@kernel.org
# Verify the .tar archive with the signature
gpg2 --verify linux-6.6.6.tar.sign
```

If everything is set up correctly, you should see the following output after verifying the GPG signature(make sure you see `gpg: Good signature` in the output):

```plain
gpg: assuming signed data in 'linux-6.6.6.tar'
gpg: Signature made Mon 11 Dec 2023 05:40:57 PM CST
gpg:                using RSA key 647F28654894E3BD457199BE38DBBDC86092693E
gpg: Good signature from "Greg Kroah-Hartman <gregkh@kernel.org>" [unknown]
gpg: WARNING: This key is not certified with a trusted signature!
gpg:          There is no indication that the signature belongs to the owner.
Primary key fingerprint: 647F 2865 4894 E3BD 4571  99BE 38DB BDC8 6092 693E
```

After verifying the signature, extract the `.tar` file to get the kernel source tree `linux-6.6.6/`.

#### Configuration

Since our focus is on examining the system call implementation, we can use the default kernel configuration.

```shell
cd linux-6.6.6/
make defconfig
```

you can also use the kernel configuration that your Linux distribution employs if you like[^7], as many distributions save the configuration under `/boot/config-$(uname -r)`. If you are using Arch Linux like me, you will find it at `/proc/config.gz`.

If you decide to use a custom kernel configuration, you will need to rename the configuration file to `.config` (and potentially uncompress it first) and place it in the root of the kernel source tree (`linux-6.6.6/` in our case). Then, you need to run `make olddefconfig` to apply the custom configuration.

There are also some useful `make` targets for managing the kernel configuration:

```shell
# ncurse based TUI
make nconfig

# X based GUI
make menuconfig

# Print help
make help
```

{{< admonition warning "Kernel Debug Info" >}}

It's important to enable the kernel debug information. To do this, you should delete or comment out the `CONFIG_DEBUG_INFO_NONE` option in the kernel configuration, and set the option `CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT` to `y`. Then, run `make olddefconfig` to make the change effective.

For kernel versions prior to `5.19.8`, there is an alternative configuration option called `CONFIG_DEBUG_INFO=y` that you can use to enable the debug information.

{{< /admonition >}}


We will also add a custom build tag to the kernel configuration, but this step is optional, feel free to skip it.

```shell
# (optional)Add a build tag syscall_irl
./scripts/config --file .config --set-str LOCALVERSION "syscall_irl"
```

#### Compiling

Now that everything is ready, there is just one big thing left. Be careful your CPU might catch fire!

```shell
# Compile the kernel with all available cores, you can change the -j flag to the number of cores you want to use
make -j$(nproc) 2>&1 | tee build.log
```

It takes about 64 seconds to compile the Linux kernel on my `i7-13700K` platform when using all available CPU cores. As long as no errors are encountered during the build process, you should see the following output at the end:

```plain
...
	LD      arch/x86/boot/compressed/vmlinux
	ZOFFSET arch/x86/boot/zoffset.h
	OBJCOPY arch/x86/boot/vmlinux.bin
	AS      arch/x86/boot/header.o
	LD      arch/x86/boot/setup.elf
	OBJCOPY arch/x86/boot/setup.bin
	BUILD   arch/x86/boot/bzImage
Kernel: arch/x86/boot/bzImage is ready  (#1)
```

The final steps in the compilation process build the uncompressed Linux kernel `vmlinux`, and then convert it into a bootable compressed kernel image `bzImage`. You can find the resulting `bzImage` file at `arch/x86/boot/bzImage`, as indicated in the output.

### Make a root filesystem

Now you can actually boot the kernel in QEMU.

```shell
qemu-system-x86_64 -kernel arch/x86/boot/bzImage
```

But you will find that the kernel panics immediately. This is because we have only provided the kernel image itself, but a significant part is still missing: the root filesystem that makes the system functional. We need to attach an `initramfs`[^8] that contains a basic root filesystem to provide a working environment.

#### Filesystem structure

Since we are using the `initramfs` solely to run the kernel, and not for switching to a real disk-based root filesystem, we only need to create three directories in this root filesystem: `sys/` for mounting `sysfs`, `proc/` for mounting `procfs`, and `bin/` for all necessary binaries.

```shell
# Make a directory that contains the whole content of the initramfs
mkdir -p initramfs/{bin,proc,sys}
```

#### Copy necessary binaries

There are quite a few binaries we need, instead of manually including all these small components, we will use `busybox`, which staticly compiled and included many utils into one single file. You can download the `busybox` binary [here](https://www.busybox.net/downloads/binaries/), or compile from [source](https://www.busybox.net/downloads/) if you like.[^9]

```shell
# Download busybox-1.35.0 static binary
cd initramfs/bin/
curl -OL https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x busybox
```

The `busybox` binary is a special executable that takes its first argument into account, including the filename. So, if you rename it or create a symbolic link to it using a Unix utility name, such as `ls`, it will behave exactly like that utility. Running `busybox --list` will print all the binary functions it supports.

With `busybox`, we can simply place it in the `initramfs/bin/` directory and create symbolic links to it with different utility names.

```shell
for cmd in $(./busybox --list); do ln -s busybox $cmd; done
```

#### Create init script

`busybox` provides all the necessary binaries, but we still need to mount the `sysfs` and `procfs`, and most importantly, specify the first userspace program to execute. To handle these tasks, we will create an init script.

```bash
cat <<EOF > initramfs/init
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
exec /bin/sh
EOF
```

The Linux kernel will run `/init` in the `initramfs` automatically after booting. So we need to make sure the script is executable.

```shell
chmod +x initramfs/init
```

#### Make initramfs image

We will use `cpio` to create the image file `initramfs.cpio.gz`.

```shell
cd initramfs
find . | cpio -H newc -o | gzip > ../initramfs.cpio.gz
cd ..
```

#### Run kernel in QEMU

This time, let's try to boot the kernel with the `initramfs`.

```shell
qemu-system-x86_64 -kernel arch/x86/boot/bzImage -initrd initramfs.cpio.gz
```

If everything works as expected, you should see the boot sequence in a new window, and eventually a `sh` prompt. There may be some additional kernel messages that appear after the `sh` prompt is presented, so you can hit `Enter` a few times to ensure the `sh` shell is running properly.

![qemu](./qemu.png)

As you can see, the `uname` output shows the custom build tag `syscall_irl` that we added during the configuration step. This confirms that we have successfully booted the kernel we compiled and have a functional environment to explore. It's time to dive in and start doing something interesting!

## Debug running kernel in QEMU

### Attach GDB to QEMU

QEMU provides the capability to attach a GDB debugger to the program running within the QEMU environment. This allows us to use GDB to debug the Linux kernel and examine everything at runtime.

```shell
# Boot kernel with supporting gdb remote attach
qemu-system-x86_64 -kernel arch/x86/boot/bzImage -initrd initramfs.cpio.gz -append "nokaslr" -s -S
```

Explaination of the newly added flags:

- `-append "nokaslr"`: add kernel commandline parameter `nokaslr` to disable KASLR (Kernel Address Space Layout Randomization), otherwise the GDB breakpoint may not work as expected.
- `-s`: a shorthand for `-gdb tcp::1234`, which listen on tcp port 1234 that GDB can attach remotely.
- `-S`: freeze the CPU at startup, so we can control the execution from GDB at the very beginning.

You will see the QEMU window prompt a message about "display not initialized". This is because the execution is currently paused. Now, open a new terminal and attach GDB to the running QEMU instance.

```gdb
$ gdb -q vmlinux
Reading symbols from vmlinux...
(gdb) target remote :1234  # Attach to QEMU gdbserver at port 1234
0x000000000000fff0 in exception_stacks ()
(gdb)
```

The execution has stopped at the address `0x000000000000fff0`, which is the first instruction the CPU will execute.

### The syscall entry

In the previous chapter, we learned that the CPU jumps to the address stored in the `IA32_LSTAR` register after the syscall instruction is executed. In Linux, this register is addressed as `MSR_LSTAR`, and the definition is located in the `arch/x86/asm/msr-index.h` header file.

```c
// arch/x86/asm/msr-index.h
/* CPU model specific register (MSR) numbers. */

/* x86-64 specific MSRs */
#define MSR_EFER 0xc0000080 /* extended feature register */
#define MSR_STAR 0xc0000081 /* legacy mode SYSCALL target */
#define MSR_LSTAR 0xc0000082 /* long mode SYSCALL target */
#define MSR_CSTAR 0xc0000083 /* compat mode SYSCALL target */
#define MSR_SYSCALL_MASK 0xc0000084 /* EFLAGS mask for syscall */
#define MSR_FS_BASE 0xc0000100 /* 64bit FS base */
#define MSR_GS_BASE 0xc0000101 /* 64bit GS base */
#define MSR_KERNEL_GS_BASE 0xc0000102 /* SwapGS GS shadow */
#define MSR_TSC_AUX 0xc0000103 /* Auxiliary TSC */
```

From the comment, we can see that the `LSTAR` name stands for "**L**ong mode **S**yscall **Tar**get". There is also a `STAR` register used for legacy systems.

After a simple search through the kernel source, we can find that the `MSR_LSTAR` register is initialized in the `syscall_init()` function during the boot sequence.

```c
void syscall_init(void)
{
	wrmsr(MSR_STAR, 0, (__USER32_CS << 16) | __KERNEL_CS);
	wrmsrl(MSR_LSTAR, (unsigned long)entry_SYSCALL_64); // The MSR_LSTAR was set to entry_SYSCALL_64

#ifdef CONFIG_IA32_EMULATION
	wrmsrl_cstar((unsigned long)entry_SYSCALL_compat);
	/*
	 * This only works on Intel CPUs.
	 * On AMD CPUs these MSRs are 32-bit, CPU truncates MSR_IA32_SYSENTER_EIP.
	 * This does not cause SYSENTER to jump to the wrong location, because
	 * AMD doesn't allow SYSENTER in long mode (either 32- or 64-bit).
	 */
	wrmsrl_safe(MSR_IA32_SYSENTER_CS, (u64)__KERNEL_CS);
	wrmsrl_safe(MSR_IA32_SYSENTER_ESP,
		    (unsigned long)(cpu_entry_stack(smp_processor_id()) + 1));
	wrmsrl_safe(MSR_IA32_SYSENTER_EIP, (u64)entry_SYSENTER_compat);
#else
	wrmsrl_cstar((unsigned long)ignore_sysret);
	wrmsrl_safe(MSR_IA32_SYSENTER_CS, (u64)GDT_ENTRY_INVALID_SEG);
	wrmsrl_safe(MSR_IA32_SYSENTER_ESP, 0ULL);
	wrmsrl_safe(MSR_IA32_SYSENTER_EIP, 0ULL);
#endif

	/*
	 * Flags to clear on syscall; clear as much as possible
	 * to minimize user space-kernel interference.
	 */
	wrmsrl(MSR_SYSCALL_MASK,
	       X86_EFLAGS_CF|X86_EFLAGS_PF|X86_EFLAGS_AF|
	       X86_EFLAGS_ZF|X86_EFLAGS_SF|X86_EFLAGS_TF|
	       X86_EFLAGS_IF|X86_EFLAGS_DF|X86_EFLAGS_OF|
	       X86_EFLAGS_IOPL|X86_EFLAGS_NT|X86_EFLAGS_RF|
	       X86_EFLAGS_AC|X86_EFLAGS_ID);
}
```

At line 4, the `MSR_LSTAR` register is set to the symbol `entry_SYSCALL_64`. Now, let's set a breakpoint in GDB at the `syscall_init()` and continue the boot sequence to see what this `entry_SYSCALL_64` symbol represents.

```gdb
(gdb) b syscall_init
Breakpoint 1 at 0xffffffff81047020: file arch/x86/kernel/cpu/common.c, line 2073.
(gdb) c
Continuing.

Breakpoint 1, syscall_init () at arch/x86/kernel/cpu/common.c:2073
2073    {
(gdb) n
2074            wrmsr(MSR_STAR, 0, (__USER32_CS << 16) | __KERNEL_CS);
(gdb) n
2075            wrmsrl(MSR_LSTAR, (unsigned long)entry_SYSCALL_64);
(gdb) info symbol entry_SYSCALL_64
entry_SYSCALL_64 in section .text
```

From the symbol information, we can see that `entry_SYSCALL_64` is a symbol located in the `.text` section, which means it is the entry point for the 64-bit system call at the address `0xffffffff82000040`. We can use GDB to find the corresponding source code line information for this symbol.

```gbd
(gdb) info line entry_SYSCALL_64
Line 89 of "arch/x86/entry/entry_64.S" starts at address 0xffffffff82000040 <entry_SYSCALL_64>
and ends at 0xffffffff82000044 <entry_SYSCALL_64+4>.
```

So GDB has informed us that the `entry_SYSCALL_64` symbol is defined at line 89 of the file [`arch/x86/entry/entry_64.S`](https://elixir.bootlin.com/linux/v6.6.6/source/arch/x86/entry/entry_64.S), which contains some assembly code. Let's walk through it line by line, but to keep the content focused, I will skip over some unrelated parts.

```asm
SYM_CODE_START(entry_SYSCALL_64)
	UNWIND_HINT_ENTRY
	ENDBR
```

The `SYM_CODE_START` is a assembler annotation for interrupt handlers and similar where the calling convention is not the C one[^10]. It defines `entry_SYSCALL_64` as a function-like symbol(i.e. the address of a procedure) that the CPU can jump to. In our case, this is the first code executed in kernel space when a system call occurs. The following lines are some compiler related details, which we will not discuss here.

```asm
	swapgs
```

The `gs` register is a limited form of segmentation register, where only the base address(GSBase) is needed to calculate the effective address[^11], similar to a pointer to an array. So, when reading from `gs[:0x10]`, the actual address is `GSBase + 0x10`. In the `arch/x86/asm/msr-index.h` file we saw earlier, there are two GSBase registers: `MSR_GS_BASE` and `MSR_KERNEL_GS_BASE`. The `gs` register uses the value in `MSR_GS_BASE` as the GSBase, and the `swapgs` instruction swaps the values in `MSR_GS_BASE` and `MSR_KERNEL_GS_BASE`, effectively changing the GSBase value. The `MSR_KERNEL_GS_BASE` stores the address of the kernel's per-CPU structure, so after the `swapgs` instruction, we can suddenly access some kernel data structures using the `gs` register.

```asm
	/* tss.sp2 is scratch space. */
	movq	%rsp, PER_CPU_VAR(cpu_tss_rw + TSS_sp2)
```

Save the value in the `rsp` register to a per-CPU scratch space `tss.sp2`[^12], so that we can use the `rsp` register for other purposes.

```asm
	SWITCH_TO_KERNEL_CR3 scratch_reg=%rsp
```

This is another crucial part of the system call entry process: switching the pagetable from the userspace pagetable to the kernel's pagetable. `CR3`[^13] is a control register that holds the physical address of the top-level pagetable (PML4 in x86_64). The `SWITCH_TO_KERNEL_CR3` macro will clear the `PTI_USER_PCID_BIT` and `PTI_USER_PGTABLE_BIT` to switch the `CR3` register to the kernel's pagetables.

You may wonder how could this code even be executed before switching the address space, won't the address of these instructions be somewhere in user address space? Well, this behavior is exactly by design in how the kernel and userspace interaction is managed. In x86_64 Linux, the virtual address space is typically split between userspace and kernel space[^14]. The upper half (usually from `0xffff800000000000` and above) is always reserved for the kernel and mapped to a portion of the kernel area. This means some kernel code, including the syscall entry, is located in the user address space and can be executed before and after switching to the kernel pagetable, as they have the same virtual address in both user and kernel pagetable.

```asm
	movq	PER_CPU_VAR(pcpu_hot + X86_top_of_stack), %rsp
```

The `PER_CPU_VAR(pcpu_hot + X86_top_of_stack)` expression gives the address of the per-CPU kernel stack. By setting the stack pointer register `rsp` to this address, we can now use stack-related instructions like `push`, `pop`, and `call` within the kernel space.

```asm
	/* Construct struct pt_regs on stack */
	pushq	$__USER_DS				/* pt_regs->ss */
	pushq	PER_CPU_VAR(cpu_tss_rw + TSS_sp2)	/* pt_regs->sp */
	pushq	%r11					/* pt_regs->flags */
	pushq	$__USER_CS				/* pt_regs->cs */
	pushq	%rcx					/* pt_regs->ip */
SYM_INNER_LABEL(entry_SYSCALL_64_after_hwframe, SYM_L_GLOBAL)
	pushq	%rax					/* pt_regs->orig_ax */

	PUSH_AND_CLEAR_REGS rax=$-ENOSYS
```

This is what a "context switch" literaly means: saving the current register state onto the stack. The order in which the registers are pushed onto the stack is crucial, as it will construct a `struct pt_regs` on the stack, as the comment indicates.

```c
struct pt_regs {
/*
 * C ABI says these regs are callee-preserved. They aren't saved on kernel entry
 * unless syscall needs a complete, fully filled "struct pt_regs".
 */
	unsigned long r15;
	unsigned long r14;
	unsigned long r13;
	unsigned long r12;
	unsigned long bp;
	unsigned long bx;
/* These regs are callee-clobbered. Always saved on kernel entry. */
	unsigned long r11;
	unsigned long r10;
	unsigned long r9;
	unsigned long r8;
	unsigned long ax;
	unsigned long cx;
	unsigned long dx;
	unsigned long si;
	unsigned long di;
/*
 * On syscall entry, this is syscall#. On CPU exception, this is error code.
 * On hw interrupt, it's IRQ number:
 */
	unsigned long orig_ax;
/* Return frame for iretq */
	unsigned long ip;
	unsigned long cs;
	unsigned long flags;
	unsigned long sp;
	unsigned long ss;
/* top of stack page */
};
```

Since the stack grows from higher to lower addresses, we need to push the registers onto the stack in the reverse order of the fields defined in `struct pt_regs`. The `PUSH_AND_CLEAR_REGS` macro will push the registers from `di` to `r15` onto the stack and then clear them. It also sets the `rax` register (used for the return value) to `-ENOSYS` as a default return value.

```asm
	/* IRQs are off. */
	movq	%rsp, %rdi
	/* Sign extend the lower 32bit as syscall numbers are treated as int */
	movslq	%eax, %rsi

	/* clobbers %rax, make sure it is after saving the syscall nr */
	IBRS_ENTER
	UNTRAIN_RET

	call	do_syscall_64		/* returns with IRQs disabled */
```

### Syscall handler

Now, a complete `struct pt_regs` has been constructed on the stack, which means the `rsp` register is now a pointer to the saved registers `struct pt_regs*`. Then, following the C calling convention, the first two function arguments `rdi` and `rsi` are set to `rsp` and `eax`, respectively, which are the `struct pt_regs*` and the system call number. The `do_syscall_64` function is the system call handler, and we can use GDB to find the source code line information for this function.

```gdb
(gdb) info line do_syscall_64
Line 74 of "arch/x86/entry/common.c" starts at address 0xffffffff81ec2550 <do_syscall_64>
and ends at 0xffffffff81ec2554 <do_syscall_64+4>.
(gdb)
```

The defination of `do_syscall_64` is below:

```c
__visible noinstr void do_syscall_64(struct pt_regs *regs, int nr)
{
	add_random_kstack_offset();
	nr = syscall_enter_from_user_mode(regs, nr);

	instrumentation_begin();

	if (!do_syscall_x64(regs, nr) && !do_syscall_x32(regs, nr) && nr != -1) {
		/* Invalid system call, but still a system call. */
		regs->ax = __x64_sys_ni_syscall(regs);
	}

	instrumentation_end();
	syscall_exit_to_user_mode(regs);
}
```

The parameter list of `do_syscall_64` is exactly what we see in the assembly code. Skipping the trace points, the syscall handler logic is actually defined in `do_syscall_x64`:

```c
static __always_inline bool do_syscall_x64(struct pt_regs *regs, int nr)
{
	/*
	 * Convert negative numbers to very high and thus out of range
	 * numbers for comparisons.
	 */
	unsigned int unr = nr;

	if (likely(unr < NR_syscalls)) {
		unr = array_index_nospec(unr, NR_syscalls);
		regs->ax = sys_call_table[unr](regs);
		return true;
	}
	return false;
}
```

This handler uses the unsigned system call number to index into an array called `sys_call_table`, which contains the actual system call functions. The `sys_call_table` is defined as follows:

```c
// arch/x86/entry/syscall_64.c
#define __SYSCALL(nr, sym) extern long __x64_##sym(const struct pt_regs *);
#include <asm/syscalls_64.h>
#undef __SYSCALL

#define __SYSCALL(nr, sym) __x64_##sym,

asmlinkage const sys_call_ptr_t sys_call_table[] = {
#include <asm/syscalls_64.h>
};
```

The `sys_call_table` lists all the syscalls and construct an array for indexing them. The full list is defined in the file `arch/x86/include/generated/asm/syscalls_64.h`, but it's a compile-time generated header file, so we need to compile the kernel first to see its content, which we have done previously. In my kernel build, there are 454 syscalls in this header file. The first four syscalls are listed below:

```c
__SYSCALL(0, sys_read)
__SYSCALL(1, sys_write)
__SYSCALL(2, sys_open)
__SYSCALL(3, sys_close)
```

We can find the actual symbol for the `write` system call by expanding the `__SYSCALL` macro, which reveals that the symbol is `__x64_sys_write`. We can then use GDB to find the source code line information for this function.

```gdb
(gdb) info line __x64_sys_write
Line 646 of "fs/read_write.c" starts at address 0xffffffff8128b0d0 <__x64_sys_write> and ends at 0xffffffff8128b0d4 <__x64_sys_write+4>.
(gdb)
```

And the code in `fs/read_write.c`:

```c
SYSCALL_DEFINE3(write, unsigned int, fd, const char __user *, buf,
		size_t, count)
{
	return ksys_write(fd, buf, count);
}
```

The `SYSCALL_DEFINE3` macro reads the system call arguments from the registers, following the C calling convention, and then calls the `ksys_write` function, which is the final system call handler.

```c
// fs/read_write.c
ssize_t ksys_write(unsigned int fd, const char __user *buf, size_t count)
{
	struct fd f = fdget_pos(fd);
	ssize_t ret = -EBADF;

	if (f.file) {
		loff_t pos, *ppos = file_ppos(f.file);
		if (ppos) {
			pos = *ppos;
			ppos = &pos;
		}
		ret = vfs_write(f.file, buf, count, ppos);
		if (ret >= 0 && ppos)
			f.file->f_pos = pos;
		fdput_pos(f);
	}

	return ret;
}
```

Now we have reached the actual logic of the `write` system call. We can set a breakpoint on the `ksys_write` function to see when it is called and what arguments are passed.

### Breakpoint on `ksys_write()`

Since the `write` system call is used for almost all output to the screen, setting a breakpoint on it will likely result in many noise hits from various processes. To get a clearer understanding, we can continue execution until the sh shell is running, then set the breakpoint on `ksys_write` and run the `echo syscall_irl` command to observe what happens.

```gdb
(gdb) c
Continuing.  // Wait sh to be executed
^C           // Press Ctrl+C to interrupt the program and set the breakpoint at ksys_write
Program received signal SIGINT, Interrupt.
default_idle () at arch/x86/kernel/process.c:743
743             raw_local_irq_disable();
1: $rip = (void (*)()) 0xffffffff81ec790f <default_idle+15>
(gdb) b ksys_write
Breakpoint 2 at 0xffffffff8128afd0: file fs/read_write.c, line 627.
(gdb) c
Continuing.  // Run command echo syscall_irl

Breakpoint 2, ksys_write (fd=3, buf=0x7f9abf5b8040 "echo syscall_irl\n", count=17) at fs/read_write.c:627
627     {
1: $rip = (void (*)()) 0xffffffff8128afd0 <ksys_write>
(gdb) c
Continuing.

Breakpoint 2, ksys_write (fd=1, buf=0x7f9abf5b9950 "syscall_irl\n", count=12) at fs/read_write.c:627
627     {
1: $rip = (void (*)()) 0xffffffff8128afd0 <ksys_write>
```

The breakpoint was hit as expected! However, there seems to be something unusual: two `write` system calls were made. In the first one, the `fd` argument is `3`, and the `buf` argument is "echo syscall_irl\n". This is weird, because the typical file descriptors for printing are `stdin(0)` or `stderr(2)`. The second `write` call appears to be the one we expected. So `3` must be a file opened by `sh` itself, we can use the `strace` utility to trace the system calls made by the `sh` shell and find out what the file descriptor `3` is.

```shell
strace busybox sh
# Some verbose output...
$ echo syscall_irl
open("$HISTFILE", O_WRONLY|O_CREAT|O_APPEND, 0600) = 3 # I replace the actually path with $HISTFILE
lseek(3, 0, SEEK_END)                   = 9
write(3, "echo syscall_irl\n", 17)      = 17
close(3)                                = 0
```

So the first `write` call with file descriptor `3` is related to the command history feature of the `sh` shell. We can ignore this by adding a condition to the breakpoint in GDB:

```gdb
(gdb) del 2 // Delete the #2 breakpoint for ksys_write we set previously

(gdb) b ksys_write if fd == 1 // Break only when fd is 1(stdout)

Breakpoint 3 at 0xffffffff8128afd0: file fs/read_write.c, line 627.
(gdb) c

Continuing. // Run command echo syscall_irl again

Breakpoint 3, ksys_write (fd=1, buf=0x7f82e39b7970 "syscall_irl\n", count=12) at fs/read_write.c:627
627     {
1: $rip = (void (*)()) 0xffffffff8128afd0 <ksys_write>
(gdb) c

Continuing. // "syscall_irl" is printed.
```

Now the GDB breakpoint will only trigger when the `fd` argument of `ksys_write` is `1`. If we continue the execution, we should see the `syscall_irl` is printed to the console.

> You may wondering why the prompt of `sh` does not hit the breakpoint, but if you look at the previous output of `strace` carefully, you will notice that the prompt is actually printed through the syscall `writev`, not `write`, that's why it won't hit.

## Return to userspace

It should be clear now how system call is implemented from user to kernel space, to return from kernel to userspace process, just reverse what we have done when entering the kernel.

```c
	call	do_syscall_64		/* returns with IRQs disabled */

	// Skip some checks here

	/*
	 * We win! This label is here just for ease of understanding
	 * perf profiles. Nothing jumps here.
	 */
syscall_return_via_sysret:
	IBRS_EXIT
	POP_REGS pop_rdi=0 // restore from r15 to rsi

	/*
	 * Now all regs are restored except RSP and RDI.
	 * Save old stack pointer and switch to trampoline stack.
	 */
	movq	%rsp, %rdi
	movq	PER_CPU_VAR(cpu_tss_rw + TSS_sp0), %rsp
	UNWIND_HINT_END_OF_STACK

	pushq	RSP-RDI(%rdi)	/* RSP */
	pushq	(%rdi)		/* RDI */

	/*
	 * We are on the trampoline stack.  All regs except RDI are live.
	 * We can do future final exit work right here.
	 */
	STACKLEAK_ERASE_NOCLOBBER

	SWITCH_TO_USER_CR3_STACK scratch_reg=%rdi // Switch back to user pagetable

	popq	%rdi // restore rdi
	popq	%rsp // restore rsp
SYM_INNER_LABEL(entry_SYSRETQ_unsafe_stack, SYM_L_GLOBAL)
	ANNOTATE_NOENDBR
	swapgs // swap to user GSBase
	sysretq // return from kernel
```

After the `do_syscall_64` function returns, the context switch happens again to restore the userspace context. Then, the pagetable is switched back to the user pagetable, and the GSBase is also swapped to the user base address. Finally, the `sysretq` instruction is executed, which performs the reverse operations of the `syscall` instruction.

The full operations of `sysret` can be found at [here](https://www.felixcloutier.com/x86/sysret#operation), and there are only few matter:

```plain
IF (operand size is 64-bit)
    THEN (* Return to 64-Bit Mode *)
        IF (RCX is not canonical) THEN #GP(0);
        RIP := RCX; (* Restore the next instruction address in the userspace *)
    ELSE (* Return to Compatibility Mode *)
        RIP := ECX; (* Same but in 32-bit *)
FI;
RFLAGS := (R11 & 3C7FD7H) | 2; (* Clear RF, VM, reserved bits; set bit 1 *)
CPL := 3; (* Set current protect ring to 3, the userspace *)
```

After the `sysretq` instruction, the CPU will continue executing the instruction that comes after the original `syscall` instruction in userspace. This marks the end of our journey through the system call process.

## Summary

In this blog post, we first introduced some background knowledge about the Application Binary Interface(ABI) and the C Calling Convention. Then, we wrote a simple program that calls the `write` system call and used GDB to walk through the assembly code before jumping into the kernel space.

Next, we built a bootable kernel image from source and created an `initramfs` for it. Finally, we used QEMU and GDB to investigate what happens in the kernel space and how the execution returns from the kernel to user space.

Throughout this journey, we uncovered the whole picture of the system call mechanism and the interaction between userspace and kernel.

[^1]: https://github.com/golang/sys/blob/master/unix/README.md
[^2]: https://en.wikipedia.org/wiki/Sentinel_species#Toxic_gases
[^3]: We use `-O1` flag here to make the code less verbose but still verbose enough to express the idea.
[^4]: The `__GI___libc_write` is just an alias to `write`.
[^5]: Actually, there is another instruction `sysenter`, what it does is same to `syscall`, the only difference is that `sysenter` is an Intel instruction, and `syscall` is an AMD instruction. See [this page](https://wiki.osdev.org/SYSENTER) for more information.
[^6]: QEMU is a hardware emulator, you can get it via your distribution's package manager, or download from https://www.qemu.org/download/ manually.
[^7]: That will cause a relatively longer compiling time, so for the purpose of this blog, I would not recommand using the configuration provided by the distribution.
[^8]: You can also use a pesudo block device or even physical device if you like, but I won't cover this because it's not related to the topic.
[^9]: The compiling steps is similar to Linux kernel, I will not cover it here.
[^10]: https://docs.kernel.org/core-api/asm-annotations.html
[^11]: https://wiki.osdev.org/SWAPGS
[^12]: https://wiki.osdev.org/Task_State_Segment
[^13]: https://wiki.osdev.org/CPU_Registers_x86-64#CR3
[^14]: https://www.kernel.org/doc/html/latest/arch/x86/x86_64/mm.html
