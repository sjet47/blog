
bigret:     file format elf64-x86-64


Disassembly of section .init:

0000000000001000 <_init>:
    1000:	endbr64
    1004:	sub    $0x8,%rsp
    1008:	mov    0x2fc1(%rip),%rax        # 3fd0 <__gmon_start__@Base>
    100f:	test   %rax,%rax
    1012:	je     1016 <_init+0x16>
    1014:	call   *%rax
    1016:	add    $0x8,%rsp
    101a:	ret

Disassembly of section .text:

0000000000001020 <_start>:
    1020:	endbr64
    1024:	xor    %ebp,%ebp
    1026:	mov    %rdx,%r9
    1029:	pop    %rsi
    102a:	mov    %rsp,%rdx
    102d:	and    $0xfffffffffffffff0,%rsp
    1031:	push   %rax
    1032:	push   %rsp
    1033:	xor    %r8d,%r8d
    1036:	xor    %ecx,%ecx
    1038:	lea    0xe9(%rip),%rdi        # 1128 <main>
    103f:	call   *0x2f7b(%rip)        # 3fc0 <__libc_start_main@GLIBC_2.34>
    1045:	hlt
    1046:	cs nopw 0x0(%rax,%rax,1)
    1050:	lea    0x2fb9(%rip),%rdi        # 4010 <__TMC_END__>
    1057:	lea    0x2fb2(%rip),%rax        # 4010 <__TMC_END__>
    105e:	cmp    %rdi,%rax
    1061:	je     1078 <_start+0x58>
    1063:	mov    0x2f5e(%rip),%rax        # 3fc8 <_ITM_deregisterTMCloneTable@Base>
    106a:	test   %rax,%rax
    106d:	je     1078 <_start+0x58>
    106f:	jmp    *%rax
    1071:	nopl   0x0(%rax)
    1078:	ret
    1079:	nopl   0x0(%rax)
    1080:	lea    0x2f89(%rip),%rdi        # 4010 <__TMC_END__>
    1087:	lea    0x2f82(%rip),%rsi        # 4010 <__TMC_END__>
    108e:	sub    %rdi,%rsi
    1091:	mov    %rsi,%rax
    1094:	shr    $0x3f,%rsi
    1098:	sar    $0x3,%rax
    109c:	add    %rax,%rsi
    109f:	sar    %rsi
    10a2:	je     10b8 <_start+0x98>
    10a4:	mov    0x2f2d(%rip),%rax        # 3fd8 <_ITM_registerTMCloneTable@Base>
    10ab:	test   %rax,%rax
    10ae:	je     10b8 <_start+0x98>
    10b0:	jmp    *%rax
    10b2:	nopw   0x0(%rax,%rax,1)
    10b8:	ret
    10b9:	nopl   0x0(%rax)
    10c0:	endbr64
    10c4:	cmpb   $0x0,0x2f45(%rip)        # 4010 <__TMC_END__>
    10cb:	jne    1100 <_start+0xe0>
    10cd:	push   %rbp
    10ce:	cmpq   $0x0,0x2f0a(%rip)        # 3fe0 <__cxa_finalize@GLIBC_2.2.5>
    10d6:	mov    %rsp,%rbp
    10d9:	je     10e8 <_start+0xc8>
    10db:	mov    0x2f26(%rip),%rdi        # 4008 <__dso_handle>
    10e2:	call   *0x2ef8(%rip)        # 3fe0 <__cxa_finalize@GLIBC_2.2.5>
    10e8:	call   1050 <_start+0x30>
    10ed:	movb   $0x1,0x2f1c(%rip)        # 4010 <__TMC_END__>
    10f4:	pop    %rbp
    10f5:	ret
    10f6:	cs nopw 0x0(%rax,%rax,1)
    1100:	ret
    1101:	data16 cs nopw 0x0(%rax,%rax,1)
    110c:	nopl   0x0(%rax)
    1110:	endbr64
    1114:	jmp    1080 <_start+0x60>

0000000000001119 <ret_big>:
    1119:	mov    %rdi,%rax
    111c:	mov    %rsi,(%rdi)
    111f:	mov    %rdx,0x8(%rdi)
    1123:	mov    %rcx,0x10(%rdi)
    1127:	ret

0000000000001128 <main>:
    1128:	mov    $0x0,%eax
    112d:	ret

Disassembly of section .fini:

0000000000001130 <_fini>:
    1130:	endbr64
    1134:	sub    $0x8,%rsp
    1138:	add    $0x8,%rsp
    113c:	ret
