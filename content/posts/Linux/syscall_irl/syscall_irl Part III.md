OK, we have known what happened during a syscall in the user space, now it's time to dive into the kernel space!

## Prepare runnable kernel

To show exactly what happened, we will use QEMU[^6] and GDB to debugging a running kernel. But first, we need to prepare a runnable Linux kernel image, that means we need to compile the kernel.

### Compiling the Linux kernel

For a general C project, the basic building progress is in three steps, even the Linux kernel has no difference.

#### Get the source

You can get every released Linux kernel source from [kernel.org](https://kernel.org). I will use the version [6.6.6](https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.xz) for now, but you can use any version you like. Also don't forget download the [GPG signature of the version](https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.10.2.tar.sign).

```shell
# Download source tarball
curl -OL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.xz
# Download signature
curl -OL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.sign
# Uncompressing source
unxz linux-6.6.6.tar.xz
# Import keys belonging to Linus Torvalds and Greg Kroah-Hartman
gpg2 --locate-keys torvalds@kernel.org gregkh@kernel.org
# Verify the .tar archive with the signature
gpg2 --verify linux-6.6.6.tar.sign
```

If everything was right, you will see the following output(make sure you see `gpg: Good signature` in the output), that means the kernel source tree you got was not modified or tampered after releasd by the kernel developer.

```plain
gpg: assuming signed data in 'linux-6.6.6.tar'
gpg: Signature made Mon 11 Dec 2023 05:40:57 PM CST
gpg:                using RSA key 647F28654894E3BD457199BE38DBBDC86092693E
gpg: Good signature from "Greg Kroah-Hartman <gregkh@kernel.org>" [unknown]
gpg: WARNING: This key is not certified with a trusted signature!
gpg:          There is no indication that the signature belongs to the owner.
Primary key fingerprint: 647F 2865 4894 E3BD 4571  99BE 38DB BDC8 6092 693E
```

Then extract the `.tar` file, and we will get the kernel source tree `linux-6.6.6/`.
#### Configuration

Since we only want to debugging the progress of syscall, it's enough to just use the default configuration.

```shell
cd linux-6.6.6/
make defconfig
```

You can also use the configuration that your Linux distribution use if you like[^8] most distribution save configuration under `/boot/config-$(uname -r)`. If you are using Arch Linux like me, you can find the configuration at `/proc/config.gz`.

If you use a custom configuration, you need to rename it as `.config`(may need uncompress first) and put it under the root of kernel source tree. Then run `make olddefconfig` to use it. There are some useful `make` target for configuration:

```shell
# ncurse based TUI
make nconfig

# X based GUI
make menuconfig

# Print help
make help
```

> **NOTE** it's important to enable the kernel debug info, delete or comment out the `CONFIG_DEBUG_INFO_NONE` line[^7], and set the `CONFIG` to `y`. Then run `make olddefconfig` to make the change effective.

We will also add a custom building tag to this configuration, but it's not necessary, feel free to skip this step.

```shell
# Add building tag(optional)
./scripts/config --file .config --set-str LOCALVERSION "syscall_irl"
```

#### Compile

Now everything is ready, there is only one big thing left. Be careful your CPU may catch fire!

```shell
# Build with all available cores, you can change the -j flag to the number of cores you want to use
make -j$(nproc) 2>&1 | tee build.log
```

It takes about 64 seconds on my `i7-13700K` platform with all available cores. If no error was encountered, you should see the following output in the end.

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

The last serval steps build the uncompressed linux kernel `vmlinux`, and convert it into a bootable compressed kernel image `bzImage`. You can find it at `arch/x86/boot/bzImage` as the output said.

### Make a root filesystem

Now you can actually run the bootable kernel with `qemu`.

```shell
qemu-system-x86_64 -kernel arch/x86/boot/bzImage
```

But you will find the kernel panics immediately, that's because we provided the kernel itself, but there is still a signaficant part missing: the root filesystem that makes the system work. We need to attach an `initramfs`[^9] that contains a basic root filesystem to provide a functional environment.

#### Filesystem structure

Since we use `initramfs` to only run the kernel, not for switching to a real disk-based root filesystem, we only need to create three directories, `sys/` for mount `sysfs`, `proc/` for `procfs`, and `bin/` for all necessary binaries.

```shell
# Make a directory that contains the whole initramfs
mkdir -p initramfs/{bin,proc,sys}
```

#### Copy necessary binaries

There are quite a few binaries we need, instead of manually including these small components, we will use `busybox`, which staticly compiled and included many utils into one single file. You can download the `busybox` binary [here](https://www.busybox.net/downloads/binaries/), or compile from [source](https://www.busybox.net/downloads/) if you like.[^10]

```shell
# Download busybox-1.35.0 static binary
cd initramfs/bin/
curl -OL https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x busybox
```

The `busybox` binary is a special executable that will take it's first argument into account, which includes it's filename. So if you rename it or make a symbol link into some Unix utility name, like `ls`, it will behave exactly  like `ls`. `busybox --list` shows all binaries it supports.

With `busybox`, we can just put it under `initramfs/bin/`, and make symbol links to it with different utility names.

```shell
for cmd in $(./busybox --list); do ln -s busybox $cmd; done
```

#### Create init script

Now all necessary binaries are ready, but we still need to mount the `sysfs` and `procfs`, and the most important, specify the first userspace program. To do that, we will create an `init` script to handle these tasks.

```bash
cat <<EOF > initramfs/init
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys

echo "Boot took $(cut -d' ' -f1 /proc/uptime) seconds"

exec /bin/sh
EOF

chmod +x initramfs/init
```

#### Make initramfs image

We will use `cpio` to make the image file `initramfs.cpio.gz`.

```shell
cd initramfs
find . | cpio -H newc -o | gzip > ../initramfs.cpio.gz
cd ..
```

### Run kernel in QEMU

This time, let's try to boot the kernel with the `initramfs`.

```shell
qemu-system-x86_64 -kernel arch/x86/boot/bzImage -initrd initramfs.cpio.gz
```

If everything is fine, you should see the boot sequence in a new window, and the `sh` prompt. There may be some kernel messages after the `sh` got executed, you can hit enter for serval times to make sure the `sh` is running.

![img]

As you can see, the `uname` shows the build tag `syscall_irl` we added in the compiling step. That means we have successfully boot the kernel we compiled, and have a functional environment to explore. It's time to do some insteresting stuff!

## Dive into kernel

### Attach GDB to QEMU

QEMU provides the ability for attaching GDB to the program running on it, so we can use GDB to debug the kernel, and see everything at the runtime.

```shell
# Boot kernel with supporting gdb remote attach
qemu-system-x86_64 -kernel arch/x86/boot/bzImage -initrd initramfs.cpio.gz -append "nokaslr" -s -S
```

Let me explain the newly added flags

- `-append "nokaslr"`: add kernel commandline parameter `nokaslr` to disable KASLR (Kernel Address Space Layout Randomization), otherwise the GDB breakpoint may not work as expected.
- `-s`: a shorthand for `-gdb tcp::1234`, which listen on tcp port 1234 that GDB can attach remotely.
- `-S`: freeze the CPU at startup, so we can control the execution from GDB at the very beginning.

You can see the QEMU window will prompt a message about dislay not initialized, now start a new terminal and attach GDB to QEMU.

```gdb
# Although we have a remote port, gdb still need a program file to read symbols.
$ gdb -q vmlinux
Reading symbols from vmlinux...
(gdb) target remote :1234
0x000000000000fff0 in exception_stacks ()
(gdb)
```

The execution stopped at the address `0x000000000000fff0` for now. Which means it's the first instruction the CPU will execute.

### The syscall entry

In last blog, we know the CPU jumped to the address of register `IA32_LSTAR` after the `syscall` instruction is executed. In Linux, this register called `MSR_LSTAR`, where the defines located at `arch/x86/asm/msr-index.h`

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

From the comment, we can see the name `LSTAR` stands for **L**ong mode **S**yscall **TAR**get. There is also a `STAR` register for legacy system.

After simply search the kernel source, we can find the `MSR_LSTAR` was initialized in `syscall_init()` during the boot sequence.

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

At line 4, the `MSR_LSTAR` is set to a symbol `entry_SYSCALL_64`. Now let's set a breakpoint at `syscall_init()`, and continue the boot sequence to see what is `entry_SYSCALL_64`.

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

From the symbol info we can see the `entry_SYSCALL_64` is a symbol in `.text` section, which means it is the entry point of syscall at the address of `0xffffffff82000040`, we can use GDB to find out the line info.

```gbd
(gdb) info line entry_SYSCALL_64
Line 89 of "arch/x86/entry/entry_64.S" starts at address 0xffffffff82000040 <entry_SYSCALL_64>
and ends at 0xffffffff82000044 <entry_SYSCALL_64+4>.
```

So GDB tell us this symbol is defined at the line 89 of file [`arch/x86/entry/entry_64.S`](https://elixir.bootlin.com/linux/v6.6.6/source/arch/x86/entry/entry_64.S), this file contains some assembly code, So let's walk through it line by line. To keep the content more focus, I will skip some unrelated part.

```asm
SYM_CODE_START(entry_SYSCALL_64)
	UNWIND_HINT_ENTRY
	ENDBR
```

The `SYM_CODE_START` is a assembler annotation for interrupt handlers and similar where the calling convention is not the C one[^11], it defines `entry_SYSCALL_64` as a function-like symbol(address of some procedure) where CPU can jump to. In our case, it's the first code executed in the kernel space when syscall happens. The following is some compiler related stuff, which we will not discuss here.

```asm
	swapgs
```

The `GS` register is a limited form of segmentation register which only the base address(GSBase) is need to calculate the effective address[^12], just like a pointer to an array. So when read from `gs[:0x10]`, the actually address is `GSBase + 0x10`. In the file `arch/x86/asm/msr-index.h` we previously saw, there are two GSBase registers `MSR_GS_BASE` and `MSR_KERNEL_GS_BASE`. `GS` register use the value in `MSR_GS_BASE` as the GSBase, and `swapgs` will swap the value in `MSR_GS_BASE` and `MSR_KERNEL_GS_BASE`, which means change the value of GSBase. The `MSR_KERNEL_GS_BASE` stores the address of the kernel's per-CPU structure, so after `swapgs`, we can suddenly access some kernel data structure with `GS` register.

```asm
	/* tss.sp2 is scratch space. */
	movq	%rsp, PER_CPU_VAR(cpu_tss_rw + TSS_sp2)
```

Save the value in `rsp` register to a per CPU scratch space `tss.sp2`[^13], so we can use `rsp` for other purpose.

```asm
	SWITCH_TO_KERNEL_CR3 scratch_reg=%rsp
```

This is another crucial part of the system call entry process: to switches the page table from the user-space page table to the kernel's page table. `CR3`[^14] is a control register that holds the physical address of the top-level page table (PML4 in x86_64). The `SWITCH_TO_KERNEL_CR3` is a macro that will clear `PTI_USER_PCID_BIT` and `PTI_USER_PGTABLE_BIT` to switch CR3 to kernel pagetables.

You may wonder how could this code even be executed before switching address space, won't the address of the instruction be somewhere in the user space? Well, this behavior is exactly by design of how the kernel and user space interaction is managed. In x86_64 Linux, the virtual address space is typically split between user space and kernel space[^15]. The upper half (usually from 0xffff800000000000 and above) is always reserved for the kernel, and mapped to a portion of the kernel area. So some kernel code(including this syscall entry) do locate in the user address space and can be executed before and after switching to kernel pagetable, because they have the same virtual address in both user and kernel pagetable.

```asm
	movq	PER_CPU_VAR(pcpu_hot + X86_top_of_stack), %rsp
```

The `PER_CPU_VAR(pcpu_hot + X86_top_of_stack)` is where the per-CPU kernel stack located, by setting the stack pointer register `rsp` to it, we can use some stack related instructions like `push`, `pop` and `call` in the kernel space.

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

This is what "context switch" literaly mean, save current registers on the stack. The order of pushing registers on stack is crucial because it actually construct a `struct pt_regs` on the stack like the comment said.

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

Since the stack grows from higher address to lower, we need to push registers on stack in the reverse order of the fields defined in `struct pt_regs`. The `PUSH_AND_CLEAR_REGS` is a trivial macro that will push from `di` to `r15` on stack and then clear them. It also set the `rax`(the return value) to `-ENOSYS` as a default return value.

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

Now a complete `struct pt_regs` has been constructed on stack, which means the `rsp` is now a pointer `struct pt_regs*` to the saved registers. Then following the C calling convention, set the first two function arguments `rdi` and `rsi` to `rsp` and `eax`, which is `struct pt_regs*` and the syscall number respectively. So the `do_syscall_64` is the syscall handler, we can use GDB to find the line info.

```gdb
(gdb) info line do_syscall_64
Line 74 of "arch/x86/entry/common.c" starts at address 0xffffffff81ec2550 <do_syscall_64>
and ends at 0xffffffff81ec2554 <do_syscall_64+4>.
(gdb)
```

In the corresponding file, we can see the defination of `do_syscall_64`

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

The parameter list is exactly what we see in the assembly code. Skipping the trace points, the syscall handler logic is defined in `do_syscall_x64`:

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

This handler use unsigned syscall numer to index actually syscall function from an array `sys_call_table`, which is defined as below:

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

It list all syscalls and construct an array for indexing them. The full syscall list is defined in the file `arch/x86/include/generated/asm/syscalls_64.h`, but it's a compile-time generated header file, so we need to compile the kernel first to see its content, which we have done previously. In my kernel build, there are 454 syscalls in this header file, and the first four syscalls is in below.

```c
__SYSCALL(0, sys_read)
__SYSCALL(1, sys_write)
__SYSCALL(2, sys_open)
__SYSCALL(3, sys_close)
```

We can find the actually symbol for the `write` syscall by expanding the `__SYSCALL` macro, which is `__x64_sys_write`. So we can again use GDB to find the line info:

```gdb
(gdb) info line __x64_sys_write
Line 646 of "fs/read_write.c" starts at address 0xffffffff8128b0d0 <__x64_sys_write> and ends at 0xffffffff8128b0d4 <__x64_sys_write+4>.
(gdb)
```

And code in `fs/read_write.c` is below:

```c
SYSCALL_DEFINE3(write, unsigned int, fd, const char __user *, buf,
		size_t, count)
{
	return ksys_write(fd, buf, count);
}
```

The macro `SYSCALL_DEFINE3` read the arguments from registers by following the C calling convention, and then call `ksys_write`, the finally syscall handler.

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

Now we have reach the actually logic of the `write` syscall. We can set a breakpoint on `ksys_write` to see will it be called and what arguments are passed.

### Breakpoint on `ksys_write()`

Since everything we print to the screen is done by `write`, it's very easy to hit the breakpoint, which means there will be many noise. To give a clear idea, we can continue executing and wait the `sh` to be executed, then we set the breakpoint, and run `echo syscall_irl` to see what will happen

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

The breakpoint is hit! But there are something weird, there are two `write` was called, and in the first one's argument, `fd` is `3`, and `buf` is `echo syscall_irl\n`, then the second syscall is what we expect. Typically, there are only three file descriptor: `stdin(0)`, `stdout(1)` and `stderr(2)`, so `3` must be a file opened by `sh` itself. We can use `strace` to find out what it is.

```shell
strace busybox sh
# Some verbose output...
$ echo syscall_irl
open("$HISTFILE", O_WRONLY|O_CREAT|O_APPEND, 0600) = 3 # I replace the actually path with $HISTFILE
lseek(3, 0, SEEK_END)                   = 9
write(3, "echo syscall_irl\n", 17)      = 17
close(3)                                = 0
```

So it is a command history feature, we can ignore it by adding a condition to the breakpoint in GDB:

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

Now GDB only break when `fd` is `1`, and if we continue the execution, you should see `syscall_irl` is printed to console.

> You may wondering why only the prompt of `sh` does not hit the `write` breakpoint, but if you look at the previous output of `strace` carefully, you will notice the prompt is actually printed through the syscall `writev`, not `write`, so it won't hit.

## Return to user space

It should be clear how syscall is done from user to kernel space, but how does the execution returns from kernel to user space process? Just reverse what we have done before entering the kernel.

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

After the `do_syscall_64` returns in `entry_SYSCALL_64`, the context switch happens again to restore user space context, then the pagetable is switched back to the user one, and `GSBase` also swapped to user base address. Then the `sysretq` is executed, which also do the reverse job of `syscall` instruction.

The full operations of `sysret` can be found at [here](https://www.felixcloutier.com/x86/sysret#operation), and there are only few that matter

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

After this instruction, the CPU will continue execute the next instruction of `syscall` in userspace. Our journey of syscall finally ended.
## Summary

In this blog, we first introduced some background knowledge like ABI and C Calling Converntion, then we write a simple program that will call `write` syscall and use GDB to walk through the assembly code before jump into kernel space. Next, we build a bootable kernel image from source and make an `initramfs` for it. Finally, we use QEMU and GDB to find out the magic happened in the kernel space, and how the execution return from kernel to user space.

[^6]: You can get QEMU via your distribution's package manager, or download from https://www.qemu.org/download/ manually.
[^7]: For kernel before 5.19.8, there is another config called `CONFIG_DEBUG_INFO=y` to enable the debug info. You can search for more information.
[^8]: That will cause a relatively longer compiling time, so for the purpose of this blog, I would not recommand using the configuration provided by the distribution.
[^9]: You can also use a pesudo block device or even physical device if you like, but I won't cover this because it's not related to the topic.
[^10]: The compiling steps is similar to Linux kernel, I will not cover it here.
[^11]: https://docs.kernel.org/core-api/asm-annotations.html
[^12]: https://wiki.osdev.org/SWAPGS
[^13]: https://wiki.osdev.org/Task_State_Segment
[^14]: https://wiki.osdev.org/CPU_Registers_x86-64#CR3
[^15]: https://www.kernel.org/doc/html/latest/arch/x86/x86_64/mm.html
