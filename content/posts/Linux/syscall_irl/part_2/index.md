---
title: "syscall_irl - Part II: Userspace Stub"
subtitle: "Deep dive into Linux system call, based on Linux-6.7 and glibc-2.38"
date: 2024-01-20T21:23:53+08:00
lastmod: 2024-06-22T18:23:06+08:00
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

<!--more-->

<!-- Main Content -->

## Userspace Code

So how does *syscall* happens, actually? If you look up the definition of the `write`, you will see the following function signature:

```c
/* Write N bytes of BUF to FD.  Return the number written, or -1.

   This function is a cancellation point and therefore not marked with
   __THROW.  */
extern ssize_t write (int __fd, const void *__buf, size_t __n) __wur
    __attr_access ((__read_only__, 2, 3));
```

But we still don't know exactly what happens when we call it. All we know is that it's like a normal C function: we call it, and everything gets done.

Since the source code of `libc` is open to everyone, we can look up how `write` is implemented. But before doing that, let's use `gdb` to find out what actually happens.

```c
// write.c
#include <unistd.h>
int main() {
    write(1, "Hello, World!\n", 14);
    return 0;
}
```

After compiling this simple code with `gcc -O1 -g -o write write.c`[^1], we get an executable named `write`. All it does is print the string "Hello, World!".

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

We can even see what is passed to which parameter thanks to the GDB debuginfod feature, but we already know that, so let's print out the assembly code of the `__GI___libc_write`[^2]:

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

Well, it's quite noisy, but we only need to focus on two lines:

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
3. Execute the `syscall` instruction[^3].

This is surprisingly simple, we can just set an extra register `rax` to the required syscall number, replace the `call` instruction with `syscall`, and an normal C function call becomes a syscall. We can even create our own `write` function with just the two lines of assembly code above.

However, there is actually another small difference in the calling convention: for syscalls, the fourth argument is passed via register `r10` instead of `rcx`. This is because `syscall` need to store the address of the next userspace instruction in register `rcx`, so after returning from kernel, execution can continue at that saved address.

### The Glibc Syscall Stub

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

## Context Switch

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

TODO: [syscall_irl - Part III: Dive into the kernel]()

[^1]: We use `-O1` flag here to make the code less verbose but still verbose enough to express the idea.

[^2]: The `__GI___libc_write` is just an alias to `write`.
[^3]: Actually, there is another instruction `sysenter`, what it does is same to `syscall`, the only difference is that `sysenter` is an Intel instruction, and `syscall` is an AMD instruction. See [this page](https://wiki.osdev.org/SYSENTER) for more information.
