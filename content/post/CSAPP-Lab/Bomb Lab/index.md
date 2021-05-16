---
title: Bomb Lab
description: CS:APP Bomb Lab Writeup
date: 2021-05-14
slug: bomblab-writeup
license: CC BY-NC-ND
categories:
    - CS:APP-Lab
tags:
    - Writeup

---

## 前言

读完CS: APP第三章后，终于来到了期待已久的Bomb Lab环节，可能由于我拿到的是B&O提供的[Self-Handout Version](http://csapp.cs.cmu.edu/3e/bomb.tar)，加上之前有一点Re经验，所以难度没有现象中那么大，花了半个晚上就做完了。但是第一遍做的时候并没有仔细的一点一点读汇编，基本上是看个大概然后依靠直觉就得到答案了，这里再重新认真做一遍做个记录

> $./bomb exp
>
> Welcome to my fiendish little bomb. You have 6 phases with
> 
> which to blow yourself up. Have a nice day!
> 
> Phase 1 defused. How about the next one?
> 
> That's number 2.  Keep going!
> 
> Halfway there!
> 
> So you got that one.  Try this one.
> 
> Good work!  On to the next...
> 
> Curses, you've found the secret phase!
> 
> But finding it and solving it are quite different...
> 
> Wow! You've defused the secret stage!
> 
> Congratulations! You've defused the bomb!

##### 环境

Ubuntu 20.04.2 LTS on Windows 10 x86_64(WSL1)

##### 分析工具

`GDB`, `objdump`

## 正文

Lab给出了一个二进制程序`bomb`和一个包含*main*函数的参考代码

这里放一段跟解题有关的部分

```c++
/* Do all sorts of secret stuff that makes the bomb harder to defuse. */
initialize_bomb();

printf("Welcome to my fiendish little bomb. You have 6 phases with\n");
printf("which to blow yourself up. Have a nice day!\n");

/* Hmm...  Six phases must be more secure than one phase! */
input = read_line();             /* Get input                   */
phase_1(input);                  /* Run the phase               */
phase_defused();                 /* Drat!  They figured it out!
                    * Let me know how they did it. */
printf("Phase 1 defused. How about the next one?\n");

/* The second phase is harder.  No one will ever figure out
    * how to defuse this... */
input = read_line();
phase_2(input);
phase_defused();
printf("That's number 2.  Keep going!\n");

/* I guess this is too easy so far.  Some more complex code will
    * confuse people. */
input = read_line();
phase_3(input);
phase_defused();
printf("Halfway there!\n");

/* Oh yeah?  Well, how good is your math?  Try on this saucy problem! */
input = read_line();
phase_4(input);
phase_defused();
printf("So you got that one.  Try this one.\n");

/* Round and 'round in memory we go, where we stop, the bomb blows! */
input = read_line();
phase_5(input);
phase_defused();
printf("Good work!  On to the next...\n");

/* This phase will never be used, since no one will get past the
    * earlier ones.  But just in case, make this one extra hard. */
input = read_line();
phase_6(input);
phase_defused();
```

可以看到每个***phase***都是先读入一行字符串，然后传入对应的函数，如果解密成功则返回，进入下一个***phase***

### Phase_1

在输入字符串之前，先看一下`phase_1`函数的汇编代码找找有没有格式要求，这里用了`objdump`静态反汇编生成代码

```assembly
0000000000400ee0 <phase_1>:
  400ee0:	48 83 ec 08          	sub    $0x8,%rsp
  400ee4:	be 00 24 40 00       	mov    $0x402400,%esi
  400ee9:	e8 4a 04 00 00       	callq  401338 <strings_not_equal>
  400eee:	85 c0                	test   %eax,%eax
  400ef0:	74 05                	je     400ef7 <phase_1+0x17>
  400ef2:	e8 43 05 00 00       	callq  40143a <explode_bomb>
  400ef7:	48 83 c4 08          	add    $0x8,%rsp
  400efb:	c3                   	retq
```

从汇编代码可以看出，`phase_1`主要是调用了`strings_not_equal`这个函数，然后判断返回值是否为0，若为0则跳转到`retq`，否则触发`explode_bomb`。这里第一次做的时候我没有深入研究，只是根据函数名来判断函数的功能，因为`%rdi`存的是输入字符串的指针，那么`%rsi`应该存的就是目标字符串，且其地址为`0x402400`，在反汇编文件中查找对应地址

```
402400 426f7264 65722072 656c6174 696f6e73  Border relations
402410 20776974 68204361 6e616461 20686176   with Canada hav
402420 65206e65 76657220 6265656e 20626574  e never been bet
402430 7465722e 00000000 576f7721 20596f75  ter.....Wow! You
```

可以看到`0x402400`对应的是字符串“Border relations with Canada have never been better.”，在`GDB`中也可以看到

>GDB>x/s 0x402400
>
>0x402400:       "Border relations with Canada have never been better."

当然不可能每次都能遇到加载了符号的汇编代码，所以还是要深入查看一下`strings_not_equal`这个函数

```assembly
0000000000401338 <strings_not_equal>:
  401338:	41 54                	push   %r12
  40133a:	55                   	push   %rbp
  40133b:	53                   	push   %rbx
  40133c:	48 89 fb             	mov    %rdi,%rbx
  40133f:	48 89 f5             	mov    %rsi,%rbp
  401342:	e8 d4 ff ff ff       	callq  40131b <string_length>
  401347:	41 89 c4             	mov    %eax,%r12d
  40134a:	48 89 ef             	mov    %rbp,%rdi
  40134d:	e8 c9 ff ff ff       	callq  40131b <string_length>
  401352:	ba 01 00 00 00       	mov    $0x1,%edx
  401357:	41 39 c4             	cmp    %eax,%r12d
  40135a:	75 3f                	jne    40139b <strings_not_equal+0x63>
  40135c:	0f b6 03             	movzbl (%rbx),%eax
  40135f:	84 c0                	test   %al,%al
  401361:	74 25                	je     401388 <strings_not_equal+0x50>
  401363:	3a 45 00             	cmp    0x0(%rbp),%al
  401366:	74 0a                	je     401372 <strings_not_equal+0x3a>
  401368:	eb 25                	jmp    40138f <strings_not_equal+0x57>
  40136a:	3a 45 00             	cmp    0x0(%rbp),%al
  40136d:	0f 1f 00             	nopl   (%rax)
  401370:	75 24                	jne    401396 <strings_not_equal+0x5e>
  401372:	48 83 c3 01          	add    $0x1,%rbx
  401376:	48 83 c5 01          	add    $0x1,%rbp
  40137a:	0f b6 03             	movzbl (%rbx),%eax
  40137d:	84 c0                	test   %al,%al
  40137f:	75 e9                	jne    40136a <strings_not_equal+0x32>
  401381:	ba 00 00 00 00       	mov    $0x0,%edx
  401386:	eb 13                	jmp    40139b <strings_not_equal+0x63>
  401388:	ba 00 00 00 00       	mov    $0x0,%edx
  40138d:	eb 0c                	jmp    40139b <strings_not_equal+0x63>
  40138f:	ba 01 00 00 00       	mov    $0x1,%edx
  401394:	eb 05                	jmp    40139b <strings_not_equal+0x63>
  401396:	ba 01 00 00 00       	mov    $0x1,%edx
  40139b:	89 d0                	mov    %edx,%eax
  40139d:	5b                   	pop    %rbx
  40139e:	5d                   	pop    %rbp
  40139f:	41 5c                	pop    %r12
  4013a1:	c3                   	retq
```

这段汇编还是很清晰的，可以看出，该函数先比较两个字符串的长度，若不相等则返回1，若相等则继续逐字符比较，均相等则返回0，否则返回1

所以***phase_1***就是`Border relations with Canada have never been better.`

第一个***phase***可以说是热身题，还是蛮简单的，重点就是不要陷入细节，要从宏观上把握程序逻辑

### Phase_2

同样，在输入字符串之前先看一下有没有格式要求，对`phase_2`反汇编得到如下代码

```assembly
0000000000400efc <phase_2>:
  400efc:	55                   	push   %rbp
  400efd:	53                   	push   %rbx
  400efe:	48 83 ec 28          	sub    $0x28,%rsp
  400f02:	48 89 e6             	mov    %rsp,%rsi
  400f05:	e8 52 05 00 00       	callq  40145c <read_six_numbers>
  400f0a:	83 3c 24 01          	cmpl   $0x1,(%rsp)
  400f0e:	74 20                	je     400f30 <phase_2+0x34>
  400f10:	e8 25 05 00 00       	callq  40143a <explode_bomb>
  400f15:	eb 19                	jmp    400f30 <phase_2+0x34>
  400f17:	8b 43 fc             	mov    -0x4(%rbx),%eax
  400f1a:	01 c0                	add    %eax,%eax
  400f1c:	39 03                	cmp    %eax,(%rbx)
  400f1e:	74 05                	je     400f25 <phase_2+0x29>
  400f20:	e8 15 05 00 00       	callq  40143a <explode_bomb>
  400f25:	48 83 c3 04          	add    $0x4,%rbx
  400f29:	48 39 eb             	cmp    %rbp,%rbx
  400f2c:	75 e9                	jne    400f17 <phase_2+0x1b>
  400f2e:	eb 0c                	jmp    400f3c <phase_2+0x40>
  400f30:	48 8d 5c 24 04       	lea    0x4(%rsp),%rbx
  400f35:	48 8d 6c 24 18       	lea    0x18(%rsp),%rbp
  400f3a:	eb db                	jmp    400f17 <phase_2+0x1b>
  400f3c:	48 83 c4 28          	add    $0x28,%rsp
  400f40:	5b                   	pop    %rbx
  400f41:	5d                   	pop    %rbp
  400f42:	c3                   	retq
```

可以看到该函数调用了`read_six_numbers`，且传入的两个参数分别为输入字符串和当前的栈顶指针，对`read_six_numbers`进行分析

```assembly
000000000040145c <read_six_numbers>:
  40145c:	48 83 ec 18          	sub    $0x18,%rsp
  401460:	48 89 f2             	mov    %rsi,%rdx
  401463:	48 8d 4e 04          	lea    0x4(%rsi),%rcx
  401467:	48 8d 46 14          	lea    0x14(%rsi),%rax
  40146b:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  401470:	48 8d 46 10          	lea    0x10(%rsi),%rax
  401474:	48 89 04 24          	mov    %rax,(%rsp)
  401478:	4c 8d 4e 0c          	lea    0xc(%rsi),%r9
  40147c:	4c 8d 46 08          	lea    0x8(%rsi),%r8
  401480:	be c3 25 40 00       	mov    $0x4025c3,%esi
  401485:	b8 00 00 00 00       	mov    $0x0,%eax
  40148a:	e8 61 f7 ff ff       	callq  400bf0 <__isoc99_sscanf@plt>
  40148f:	83 f8 05             	cmp    $0x5,%eax
  401492:	7f 05                	jg     401499 <read_six_numbers+0x3d>
  401494:	e8 a1 ff ff ff       	callq  40143a <explode_bomb>
  401499:	48 83 c4 18          	add    $0x18,%rsp
  40149d:	c3                   	retq
```

这里可以看到该函数调用了标准库函数`sscanf`，且格式化字符串保存在`0x4025c3`中，使用`GDB`查看

> GDB>x/s 0x4025c3
> 
> 0x4025c3:       "%d %d %d %d %d %d"

可以看到该函数很简单，就是简单的包装了一下`sscanf`函数，基本逻辑就是读入6个数字并依次保存在传入的栈指针指向的连续内存中，因为参数寄存器一共有6个，一共传入8个参数到`sscanf`中(前两个是输入字符串和格式字符串，剩余6个是指针)，前6个参数均保存在参数寄存器中，剩余两个参数则保存在栈上(`%rsp`和`0x8(%rsp)`)，是典型的调用栈帧

接下来的代码主要包括两部分，第一部分如下

```assembly
  400f0a:	83 3c 24 01          	cmpl   $0x1,(%rsp)
  400f0e:	74 20                	je     400f30 <phase_2+0x34>
  400f10:	e8 25 05 00 00       	callq  40143a <explode_bomb>
  ...
  400f30:	48 8d 5c 24 04       	lea    0x4(%rsp),%rbx
  400f35:	48 8d 6c 24 18       	lea    0x18(%rsp),%rbp
  400f3a:	eb db                	jmp    400f17 <phase_2+0x1b>
```

这里首先将1与输入的6个数字中的第一个比较，若相等则将第2个数字的地址保存在`%rbx`中，将第6个数字的地址保存在`%rbp`中，(**注意这里由于使用的是16进制，所以18(16)实际上是24(10)**，刚开始的时候我虽然看到了前导`0x`，但还是搞混了。)然后跳转到`0x400f17`处，即第二部分

```assembly
  400f17:	8b 43 fc             	mov    -0x4(%rbx),%eax
  400f1a:	01 c0                	add    %eax,%eax
  400f1c:	39 03                	cmp    %eax,(%rbx)
  400f1e:	74 05                	je     400f25 <phase_2+0x29>
  400f20:	e8 15 05 00 00       	callq  40143a <explode_bomb>
  400f25:	48 83 c3 04          	add    $0x4,%rbx
  400f29:	48 39 eb             	cmp    %rbp,%rbx
  400f2c:	75 e9                	jne    400f17 <phase_2+0x1b>
  400f2e:	eb 0c                	jmp    400f3c <phase_2+0x40> # 函数结尾
```

可以看出这是一个循环，首先将`%rbx`指向的前一个数\*2，然后与`%rbx`指向的数相比，若相等则将`%rbx`指向下一个数字；若`%rbx`与`%rbp`相等，即当`%rbx`指向第6个数字时跳转到函数结尾，否则继续下一轮循环，用C描述为

```c
do
{
    if(*(rbx-1)*2 == *rbx)
        ++rbx;
    else
        explode_bomb();
}while(rbx != rbp);
```

即从1开始，往后每个数都是前一个数的2倍，即$a_0=1,p=2,N=6$的等比数列{1, 2, 4, 8, 16, 32}

即***phase_2***即为`1 2 4 8 16 32`

### Phase_3

在未知格式要求的情况下先看一下`phase_3`的汇编代码

```assembly
0000000000400f43 <phase_3>:
  400f43:	48 83 ec 18          	sub    $0x18,%rsp
  400f47:	48 8d 4c 24 0c       	lea    0xc(%rsp),%rcx
  400f4c:	48 8d 54 24 08       	lea    0x8(%rsp),%rdx
  400f51:	be cf 25 40 00       	mov    $0x4025cf,%esi
  400f56:	b8 00 00 00 00       	mov    $0x0,%eax
  400f5b:	e8 90 fc ff ff       	callq  400bf0 <__isoc99_sscanf@plt>
  400f60:	83 f8 01             	cmp    $0x1,%eax
  400f63:	7f 05                	jg     400f6a <phase_3+0x27>
  400f65:	e8 d0 04 00 00       	callq  40143a <explode_bomb>
  400f6a:	83 7c 24 08 07       	cmpl   $0x7,0x8(%rsp)
  400f6f:	77 3c                	ja     400fad <phase_3+0x6a>
  400f71:	8b 44 24 08          	mov    0x8(%rsp),%eax
  400f75:	ff 24 c5 70 24 40 00 	jmpq   *0x402470(,%rax,8)
  400f7c:	b8 cf 00 00 00       	mov    $0xcf,%eax
  400f81:	eb 3b                	jmp    400fbe <phase_3+0x7b>
  400f83:	b8 c3 02 00 00       	mov    $0x2c3,%eax
  400f88:	eb 34                	jmp    400fbe <phase_3+0x7b>
  400f8a:	b8 00 01 00 00       	mov    $0x100,%eax
  400f8f:	eb 2d                	jmp    400fbe <phase_3+0x7b>
  400f91:	b8 85 01 00 00       	mov    $0x185,%eax
  400f96:	eb 26                	jmp    400fbe <phase_3+0x7b>
  400f98:	b8 ce 00 00 00       	mov    $0xce,%eax
  400f9d:	eb 1f                	jmp    400fbe <phase_3+0x7b>
  400f9f:	b8 aa 02 00 00       	mov    $0x2aa,%eax
  400fa4:	eb 18                	jmp    400fbe <phase_3+0x7b>
  400fa6:	b8 47 01 00 00       	mov    $0x147,%eax
  400fab:	eb 11                	jmp    400fbe <phase_3+0x7b>
  400fad:	e8 88 04 00 00       	callq  40143a <explode_bomb>
  400fb2:	b8 00 00 00 00       	mov    $0x0,%eax
  400fb7:	eb 05                	jmp    400fbe <phase_3+0x7b>
  400fb9:	b8 37 01 00 00       	mov    $0x137,%eax
  400fbe:	3b 44 24 0c          	cmp    0xc(%rsp),%eax
  400fc2:	74 05                	je     400fc9 <phase_3+0x86>
  400fc4:	e8 71 04 00 00       	callq  40143a <explode_bomb>
  400fc9:	48 83 c4 18          	add    $0x18,%rsp
  400fcd:	c3                   	retq
```

可以看到首先调用了`sscanf`函数且格式字符串在`0x4025cf`，用`GDB`看一下可以得到

> GDB>x/s 0x4025cf
> 
> 0x4025cf:       "%d %d"

即读入两个数字并分别储存在栈地址`0x8(%rsp)`和`0xc(%rsp)`中，随后对第一个数与7进行比较，若大于7则引爆

然后以第一个数为索引进行分支跳转，即switch(num1)，由于第一个数的范围是0-7，故一共有8条分支，查看位于`0x402470`的跳转表可得

> GDB>x/8xg 0x402470
> 
> 0x402470:       0x0000000000400f7c    0x0000000000400fb9
> 
> 0x402480:       0x0000000000400f83      0x0000000000400f8a
> 
> 0x402490:       0x0000000000400f91      0x0000000000400f98
> 
> 0x4024a0:       0x0000000000400f9f      0x0000000000400fa6

其中每条分支都是先给`%eax`一个数，然后将其与第二个数相比较，若相等则返回，因此可以得到8对数

(0, 207(0xcf))，(1, 311(0x137))，(2, 707(0x2c3))，(3, 256(0x100))

(4, 389(0x185))，(5, 206(0xce))，(6, 682(0x2aa))，(7, 327(0x147))

故***phase_3***共有8组解，即{`0 207`，`1 311`，`2 707`，`3 256`，`4 389`，`5 206`，`6 682`，`7 327`}

### Phase_4

先看下`phase_4`的汇编代码

```assembly
000000000040100c <phase_4>:
  40100c:	48 83 ec 18          	sub    $0x18,%rsp
  401010:	48 8d 4c 24 0c       	lea    0xc(%rsp),%rcx
  401015:	48 8d 54 24 08       	lea    0x8(%rsp),%rdx
  40101a:	be cf 25 40 00       	mov    $0x4025cf,%esi
  40101f:	b8 00 00 00 00       	mov    $0x0,%eax
  401024:	e8 c7 fb ff ff       	callq  400bf0 <__isoc99_sscanf@plt>
  401029:	83 f8 02             	cmp    $0x2,%eax
  40102c:	75 07                	jne    401035 <phase_4+0x29>
  40102e:	83 7c 24 08 0e       	cmpl   $0xe,0x8(%rsp)
  401033:	76 05                	jbe    40103a <phase_4+0x2e>
  401035:	e8 00 04 00 00       	callq  40143a <explode_bomb>
  40103a:	ba 0e 00 00 00       	mov    $0xe,%edx
  40103f:	be 00 00 00 00       	mov    $0x0,%esi
  401044:	8b 7c 24 08          	mov    0x8(%rsp),%edi
  401048:	e8 81 ff ff ff       	callq  400fce <func4>
  40104d:	85 c0                	test   %eax,%eax
  40104f:	75 07                	jne    401058 <phase_4+0x4c>
  401051:	83 7c 24 0c 00       	cmpl   $0x0,0xc(%rsp)
  401056:	74 05                	je     40105d <phase_4+0x51>
  401058:	e8 dd 03 00 00       	callq  40143a <explode_bomb>
  40105d:	48 83 c4 18          	add    $0x18,%rsp
  401061:	c3                   	retq
```

可以看到前6行与`phase_3`相同，都是读入2个数字，且第一个数字要小于等于14(0xe)，然后调用了函数`func4`，且参数列表为(num1, 0, 14)，若`func4`返回0则继续，然后当第二个数字等于0时函数返回。所以重点就在`func4`中，看一下汇编

```assembly
0000000000400fce <func4>:
  400fce:	48 83 ec 08          	sub    $0x8,%rsp
  400fd2:	89 d0                	mov    %edx,%eax
  400fd4:	29 f0                	sub    %esi,%eax
  400fd6:	89 c1                	mov    %eax,%ecx
  400fd8:	c1 e9 1f             	shr    $0x1f,%ecx
  400fdb:	01 c8                	add    %ecx,%eax
  400fdd:	d1 f8                	sar    %eax
  400fdf:	8d 0c 30             	lea    (%rax,%rsi,1),%ecx
  400fe2:	39 f9                	cmp    %edi,%ecx
  400fe4:	7e 0c                	jle    400ff2 <func4+0x24>
  400fe6:	8d 51 ff             	lea    -0x1(%rcx),%edx
  400fe9:	e8 e0 ff ff ff       	callq  400fce <func4>
  400fee:	01 c0                	add    %eax,%eax
  400ff0:	eb 15                	jmp    401007 <func4+0x39>
  400ff2:	b8 00 00 00 00       	mov    $0x0,%eax
  400ff7:	39 f9                	cmp    %edi,%ecx
  400ff9:	7d 0c                	jge    401007 <func4+0x39>
  400ffb:	8d 71 01             	lea    0x1(%rcx),%esi
  400ffe:	e8 cb ff ff ff       	callq  400fce <func4>
  401003:	8d 44 00 01          	lea    0x1(%rax,%rax,1),%eax
  401007:	48 83 c4 08          	add    $0x8,%rsp
  40100b:	c3                   	retq
```

该段代码有两个比较跳转指令，分别在`0x400fe2`和`0x400ff7`处，且`%ecx`在这两条指令处均为7，则不考虑其他情况，当$num1 \ge 7$和$num1 \le 7$均满足时，有一条通路可以返回0，故首先可以得到一个解(7, 0)，这也是我第一次做得到的答案。但是这段代码在不满足上述条件时会触发递归，所以还可能存在其他的解。因为递归代码往往体积小却逻辑复杂，所以这里先对汇编代码手工进行反编译，以便进一步的分析

```c
int func(int a, int b, int c)
{
    int var1 = (c - b)/2;
    int var2 = (c + b)/2;
    
    if(var2 <= a)
        var1 = 0;
    else
        return func(a, 0, var2-1)*2;

    if(var2 >= a)
        return var1;
    else
        return func(a, var2+1, c)*2 + 1;
}
```

只考虑第1条递归，可以得到当a={0, 1, 3, 7}时func返回0；考虑两个递归时无解

同样也可以用反编译代码写一段C程序得到答案

> func(0, 0, 14) = 0, 
> func(1, 0, 14) = 0, 
> func(2, 0, 14) = 4, 
> 
> func(3, 0, 14) = 0, 
> func(4, 0, 14) = 26, 
> func(5, 0, 14) = 2, 
> 
> func(6, 0, 14) = 6, 
> func(7, 0, 14) = 0, 
> func(8, 0, 14) = 5, 
> 
> func(9, 0, 14) = 13, 
> func(10, 0, 14) = 29, 
> func(11, 0, 14) = 1, 
> 
> func(12, 0, 14) = 59, 
> func(13, 0, 14) = 3, 
> func(14, 0, 14) = 7, 

故***phase_4***一共存在4组解{`0 0`，`1 0`，`3 0`，`7 0`}

### Phase_5

```assembly
0000000000401062 <phase_5>:
  401062:	53                   	push   %rbx
  401063:	48 83 ec 20          	sub    $0x20,%rsp
  401067:	48 89 fb             	mov    %rdi,%rbx
  40106a:	64 48 8b 04 25 28 00 	mov    %fs:0x28,%rax
  401071:	00 00
  401073:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
  401078:	31 c0                	xor    %eax,%eax
  40107a:	e8 9c 02 00 00       	callq  40131b <string_length>
  40107f:	83 f8 06             	cmp    $0x6,%eax
  401082:	74 4e                	je     4010d2 <phase_5+0x70>
  401084:	e8 b1 03 00 00       	callq  40143a <explode_bomb>
  401089:	eb 47                	jmp    4010d2 <phase_5+0x70>
  40108b:	0f b6 0c 03          	movzbl (%rbx,%rax,1),%ecx
  40108f:	88 0c 24             	mov    %cl,(%rsp)
  401092:	48 8b 14 24          	mov    (%rsp),%rdx
  401096:	83 e2 0f             	and    $0xf,%edx
  401099:	0f b6 92 b0 24 40 00 	movzbl 0x4024b0(%rdx),%edx
  4010a0:	88 54 04 10          	mov    %dl,0x10(%rsp,%rax,1)
  4010a4:	48 83 c0 01          	add    $0x1,%rax
  4010a8:	48 83 f8 06          	cmp    $0x6,%rax
  4010ac:	75 dd                	jne    40108b <phase_5+0x29>
  4010ae:	c6 44 24 16 00       	movb   $0x0,0x16(%rsp)
  4010b3:	be 5e 24 40 00       	mov    $0x40245e,%esi
  4010b8:	48 8d 7c 24 10       	lea    0x10(%rsp),%rdi
  4010bd:	e8 76 02 00 00       	callq  401338 <strings_not_equal>
  4010c2:	85 c0                	test   %eax,%eax
  4010c4:	74 13                	je     4010d9 <phase_5+0x77>
  4010c6:	e8 6f 03 00 00       	callq  40143a <explode_bomb>
  4010cb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
  4010d0:	eb 07                	jmp    4010d9 <phase_5+0x77>
  4010d2:	b8 00 00 00 00       	mov    $0x0,%eax
  4010d7:	eb b2                	jmp    40108b <phase_5+0x29>
  4010d9:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
  4010de:	64 48 33 04 25 28 00 	xor    %fs:0x28,%rax
  4010e5:	00 00
  4010e7:	74 05                	je     4010ee <phase_5+0x8c>
  4010e9:	e8 42 fa ff ff       	callq  400b30 <__stack_chk_fail@plt>
  4010ee:	48 83 c4 20          	add    $0x20,%rsp
  4010f2:	5b                   	pop    %rbx
  4010f3:	c3                   	retq
```

观察汇编可以看出，这段代码使用了金丝雀值确保返回值不会被覆盖，同时需满足输入字符串的长度为6

代码前半部分是如下所示的一个循环结构(对顺序做了一些调整方便分析)

```assembly
  4010d2:	b8 00 00 00 00       	mov    $0x0,%eax
  4010d7:	eb b2                	jmp    40108b <phase_5+0x29>
  ...
  40108b:	0f b6 0c 03          	movzbl (%rbx,%rax,1),%ecx
  40108f:	88 0c 24             	mov    %cl,(%rsp)
  401092:	48 8b 14 24          	mov    (%rsp),%rdx
  401096:	83 e2 0f             	and    $0xf,%edx
  401099:	0f b6 92 b0 24 40 00 	movzbl 0x4024b0(%rdx),%edx
  4010a0:	88 54 04 10          	mov    %dl,0x10(%rsp,%rax,1)
  4010a4:	48 83 c0 01          	add    $0x1,%rax
  4010a8:	48 83 f8 06          	cmp    $0x6,%rax
  4010ac:	75 dd                	jne    40108b <phase_5+0x29>
  4010ae:	c6 44 24 16 00       	movb   $0x0,0x16(%rsp)
```

以`0x4024b0`为基址，取输入字符串中的每个字符的低4位作为偏移量访问内存，并将访问结果序列保存在栈地址`0x10(%rsp) ` 中，作为一个新的字符串。用`GDB`可以看到该地址对应的内容为

> GDB>x/s 0x4024b0
> 
> 0x4024b0 <array.3449>:  "maduiersnfotvbylSo you think you can stop the bomb with ctrl-c, do you?"

由于使用4位二进制数作为偏移量，所以最多可以访问到该字符串的前16个字符，即"maduiersnfotvbyl"

```assembly
  4010b3:	be 5e 24 40 00       	mov    $0x40245e,%esi
  4010b8:	48 8d 7c 24 10       	lea    0x10(%rsp),%rdi
  4010bd:	e8 76 02 00 00       	callq  401338 <strings_not_equal>
  4010c2:	85 c0                	test   %eax,%eax
  4010c4:	74 13                	je     4010d9 <phase_5+0x77>
  4010c6:	e8 6f 03 00 00       	callq  40143a <explode_bomb>
  4010cb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
  4010d0:	eb 07                	jmp    4010d9 <phase_5+0x77
```

然后将新字符串与地址`0x40245e`处的字符串进行比较，若相等则返回

用`GDB`查看该处的字符串内容

> GDB>x/s 0x40245e
> 
> 0x40245e:       "flyers"

所以只需要在字符串`0x4024b0`中按顺序获取对应的字符即可。写行Python算一下偏移量

```python
print(["maduiersnfotvbyl".find(i) for i in "flyers"])
```

> [9, 15, 14, 5, 6, 7]

其中需保证输入字符的高4位在可打印字符的范围内，所以高4位可以取0x2到0x6，当不需要访问第16个字符时也可以取0x7，但由于偏移量包含15，所以0x7舍去，故一共有5组解，用如下Python代码可以得到

```python
print([''.join([chr(h+i) for i in [9,15,14,5,6,7]]) for h in [0x20,0x30,0x40,0x50,0x60]])
```

> [")/.%&'", '9?>567', 'IONEFG', 'Y_^UVW', 'ionefg']

所以***phase_5***的解为{`)/.%&'`，`9?>567`，`IONEFG`，`Y_^UVW`，`ionefg`}

### Phase_6

由于`phase_6`的汇编代码比较长，这里就不全部放出了，只分段进行分析，并且省略了无关的代码

开头和`phase_2`类似，读入6个数字并存在栈中，然后是一段循环

```assembly
  401114:	4c 89 ed             	mov    %r13,%rbp
  401117:	41 8b 45 00          	mov    0x0(%r13),%eax
  40111b:	83 e8 01             	sub    $0x1,%eax
  40111e:	83 f8 05             	cmp    $0x5,%eax
  401121:	76 05                	jbe    401128 <phase_6+0x34>
  401123:	e8 12 03 00 00       	callq  40143a <explode_bomb>
  401128:	41 83 c4 01          	add    $0x1,%r12d
  40112c:	41 83 fc 06          	cmp    $0x6,%r12d
  401130:	74 21                	je     401153 <phase_6+0x5f> #结束循环
  401132:	44 89 e3             	mov    %r12d,%ebx
  401135:	48 63 c3             	movslq %ebx,%rax
  401138:	8b 04 84             	mov    (%rsp,%rax,4),%eax
  40113b:	39 45 00             	cmp    %eax,0x0(%rbp)
  40113e:	75 05                	jne    401145 <phase_6+0x51>
  401140:	e8 f5 02 00 00       	callq  40143a <explode_bomb>
  401145:	83 c3 01             	add    $0x1,%ebx
  401148:	83 fb 05             	cmp    $0x5,%ebx
  40114b:	7e e8                	jle    401135 <phase_6+0x41>
  40114d:	49 83 c5 04          	add    $0x4,%r13
  401151:	eb c1                	jmp    401114 <phase_6+0x20>
```

其中`%r13`指向读入的6个数字的首地址。可以看到，这段代码对每个数字首先减1然后与5进行比较，当大于5时则引爆。然后从当前数字开始，逐个与后面的数字进行比较，若相等则引爆

所以可以得到两个条件

1. 输入的6个数字均需小于7
2. 输入的6个数字必须互不相同

接着又是一段循环

```assembly
  401153:	48 8d 74 24 18       	lea    0x18(%rsp),%rsi
  401158:	4c 89 f0             	mov    %r14,%rax
  40115b:	b9 07 00 00 00       	mov    $0x7,%ecx
  401160:	89 ca                	mov    %ecx,%edx
  401162:	2b 10                	sub    (%rax),%edx
  401164:	89 10                	mov    %edx,(%rax)
  401166:	48 83 c0 04          	add    $0x4,%rax
  40116a:	48 39 f0             	cmp    %rsi,%rax
  40116d:	75 f1                	jne    401160 <phase_6+0x6c>
```

其中`%r14`与`%rsp`相等，均指向读入的6个数字的首地址。这里对6个数字进行遍历，对每个数字都用7减去这个数并将结果原地更新，用Python表达为

```Python
for num in nums: num = 7 - num
```

接下来是`phase_6`中最复杂的一段代码，这里分成三部分，先看第一部分

```assembly
  40116f:	be 00 00 00 00       	mov    $0x0,%esi
  401174:	eb 21                	jmp    401197 <phase_6+0xa3>
  401176:	48 8b 52 08          	mov    0x8(%rdx),%rdx
  40117a:	83 c0 01             	add    $0x1,%eax
  40117d:	39 c8                	cmp    %ecx,%eax
  40117f:	75 f5                	jne    401176 <phase_6+0x82>
  401181:	eb 05                	jmp    401188 <phase_6+0x94>
  401183:	ba d0 32 60 00       	mov    $0x6032d0,%edx
  401188:	48 89 54 74 20       	mov    %rdx,0x20(%rsp,%rsi,2)
  40118d:	48 83 c6 04          	add    $0x4,%rsi
  401191:	48 83 fe 18          	cmp    $0x18,%rsi
  401195:	74 14                	je     4011ab <phase_6+0xb7> # 结束循环
  401197:	8b 0c 34             	mov    (%rsp,%rsi,1),%ecx
  40119a:	83 f9 01             	cmp    $0x1,%ecx
  40119d:	7e e4                	jle    401183 <phase_6+0x8f>
  40119f:	b8 01 00 00 00       	mov    $0x1,%eax
  4011a4:	ba d0 32 60 00       	mov    $0x6032d0,%edx
  4011a9:	eb cb                	jmp    401176 <phase_6+0x82>
```

这里依然是遍历输入的6个数，当遍历到小于等于1的数时，将`0x6032d0`保存在栈上`0x20(%rsp,%rsi,2)`处，然后`%rsi`增加4；当遍历到大于1的数时，可以看到`401176`处的代码多次将内存中的值作为地址进行访问，因此可以看出这里是访问一段链表，且访问到第num个节点，然后将该节点保存在栈上`0x20(%rsp,%rsi,2)`处，并将`%rsi`增加4。通过GDB访问地址`0x6032d0`也可以证明这是一个链表

> GDB>x/24dw 0x6032d0
> 
> 0x6032d0 \<node1\>:       332     1       6304480 0
> 
> 0x6032e0 \<node2\>:       168     2       6304496 0
> 
> 0x6032f0 \<node3\>:       924     3       6304512 0
> 
> 0x603300 \<node4\>:       691     4       6304528 0
> 
> 0x603310 \<node5\>:       477     5       6304544 0
> 
> 0x603320 \<node6\>:       443     6       0       0

总的来看，这段代码的作用就是遍历输入的6个数，对于每个数num，将`0x6032d0`处的链表的第num个节点的地址保存在以`0x20(%rsp)`为首的第num个位置中，即按照输入的数字的顺序重新排列。**注意，这里的输入数字是被7减去后的结果，因此并不等于实际输入的字符串中的6个数字**

然后是第二部分

```assembly
  4011ab:	48 8b 5c 24 20       	mov    0x20(%rsp),%rbx
  4011b0:	48 8d 44 24 28       	lea    0x28(%rsp),%rax
  4011b5:	48 8d 74 24 50       	lea    0x50(%rsp),%rsi
  4011ba:	48 89 d9             	mov    %rbx,%rcx
  4011bd:	48 8b 10             	mov    (%rax),%rdx
  4011c0:	48 89 51 08          	mov    %rdx,0x8(%rcx)
  4011c4:	48 83 c0 08          	add    $0x8,%rax
  4011c8:	48 39 f0             	cmp    %rsi,%rax
  4011cb:	74 05                	je     4011d2 <phase_6+0xde> # 结束循环
  4011cd:	48 89 d1             	mov    %rdx,%rcx
  4011d0:	eb eb                	jmp    4011bd <phase_6+0xc9>
  4011d2:	48 c7 42 08 00 00 00 	movq   $0x0,0x8(%rdx)
```

这段代码的指针引用关系有点绕，但由于比较短，还是很好分析的。首先要明确的是`%rbx`和`%rcx`是节点指针，而`%rax`和`%rdx`都是指向节点指针的指针，即栈指针的偏移。先从重新排列后的第一个节点指针开始获取两个在栈上连续的节点指针，然后将第一个节点指针+8后指向的地址的值(即节点的指针域)改成第二个指针的值，最后直到第二个指针指向栈末尾的非节点地址时，将第一个指针指向的节点的指针域指向0(`NULL`)

因此，这段代码的作用就是用排列后的节点顺序更新链表的连接顺序

最后来看第三部分

```assembly
  4011da:	bd 05 00 00 00       	mov    $0x5,%ebp
  4011df:	48 8b 43 08          	mov    0x8(%rbx),%rax
  4011e3:	8b 00                	mov    (%rax),%eax
  4011e5:	39 03                	cmp    %eax,(%rbx)
  4011e7:	7d 05                	jge    4011ee <phase_6+0xfa>
  4011e9:	e8 4c 02 00 00       	callq  40143a <explode_bomb>
  4011ee:	48 8b 5b 08          	mov    0x8(%rbx),%rbx
  4011f2:	83 ed 01             	sub    $0x1,%ebp
  4011f5:	75 e8                	jne    4011df <phase_6+0xeb>
```

最后一部分就比较简单了，由于`%rbx`是指向链表头节点的指针，所以这段循环的作用就是遍历链表并且当下一个链表的元素大于当前链表的元素时引爆炸弹。因此得到了第3个条件：**输入的6个数字需使链表重新排列为降序**

由链表的原始顺序可得

> GDB>x/24dw 0x6032d0
> 
> 0x6032d0 \<node1\>:       332     1       6304480 0
> 
> 0x6032e0 \<node2\>:       168     2       6304496 0
> 
> 0x6032f0 \<node3\>:       924     3       6304512 0
> 
> 0x603300 \<node4\>:       691     4       6304528 0
> 
> 0x603310 \<node5\>:       477     5       6304544 0
> 
> 0x603320 \<node6\>:       443     6       0       0

排列链表的6个数字应该是{3, 4, 5, 6, 1, 2}，但由于这是被7减去后的结果，所以要得到原始输入，应该再次用7减去这6个数字，即输入的6个数字为{4, 3, 2, 1, 6, 5}，同时这6个数字也满足条件1和条件2

所以***phase_6***即为`4 3 2 1 6 5`

### Secret_Phase

第一遍做的时候我是直接用GDB调试汇编得到的答案，因此并没有完整的查看程序的汇编代码，在写这篇文章的时候发现还有一个程序段叫`secret_phase`，但是在`main`函数里并没有找到入口，所以看了下其他的函数，发现其入口是在每次解开一个phase都要调用的一个叫`phase_defused`的函数中，所以又仔细研究了一下怎么才能触发这个调用。

首先看一下`phase-defused`的汇编，为节省空间这里省略了无关的部分

```assembly
00000000004015c4 <phase_defused>:
  4015d8:	83 3d 81 21 20 00 06 	cmpl   $0x6,0x202181(%rip)         # 603760 
  4015df:	75 5e                	jne    40163f <phase_defused+0x7b> # 函数返回
  4015e1:	4c 8d 44 24 10       	lea    0x10(%rsp),%r8
  4015e6:	48 8d 4c 24 0c       	lea    0xc(%rsp),%rcx
  4015eb:	48 8d 54 24 08       	lea    0x8(%rsp),%rdx
  4015f0:	be 19 26 40 00       	mov    $0x402619,%esi
  4015f5:	bf 70 38 60 00       	mov    $0x603870,%edi
  4015fa:	e8 f1 f5 ff ff       	callq  400bf0 <__isoc99_sscanf@plt>
  4015ff:	83 f8 03             	cmp    $0x3,%eax
  401602:	75 31                	jne    401635 <phase_defused+0x71>
  401604:	be 22 26 40 00       	mov    $0x402622,%esi
  401609:	48 8d 7c 24 10       	lea    0x10(%rsp),%rdi
  40160e:	e8 25 fd ff ff       	callq  401338 <strings_not_equal>
  401613:	85 c0                	test   %eax,%eax
  401615:	75 1e                	jne    401635 <phase_defused+0x71>
  401617:	bf f8 24 40 00       	mov    $0x4024f8,%edi
  40161c:	e8 ef f4 ff ff       	callq  400b10 <puts@plt>
  401621:	bf 20 25 40 00       	mov    $0x402520,%edi
  401626:	e8 e5 f4 ff ff       	callq  400b10 <puts@plt>
  40162b:	b8 00 00 00 00       	mov    $0x0,%eax
  401630:	e8 0d fc ff ff       	callq  401242 <secret_phase>
  401635:	bf 58 25 40 00       	mov    $0x402558,%edi
  40163a:	e8 d1 f4 ff ff       	callq  400b10 <puts@plt>
```

这段代码首先将位于地址`0x603760`的值与`0x6`进行比较，若不相同则返回。通过搜索`603760`相关代码，发现这个地址的值初始化为0，每次读入一个字符串后都会自增1，这个操作在`read_line`函数中进行。所以只有当读入6个字符串，即读入***phase_6***之后才会运行后面的内容。但由于没有给额外的输入机会，因此唯一的方法是在前面6个***phase***后附加一个字符串作为***secret_phase***。

在读完6个字符串后，用`GDB`查看位于`0x603870`的源字符串和位于`0x402619`的格式化字符串

> GDB>x/s 0x603870
> 
> 0x603870 <input_strings+240>:   "0 0"
> 
> GDB>x/s 0x402619
> 
> 0x402619:       "%d %d %s"

可以看到源字符串是前面读入的6个字符串中的第四个，即***phase_4***，格式化字符串为读入两个数和一个字符串。

因此只需要在***phase_4***后附加一个字符串即可触发`secret_phase`。可以看到后面调用了`strings_not_equal`，即之前分析的比较字符串的函数，并且传入的参数是附加字符串和位于`0x402622`的字符串，使用`GDB`查看

> GDB>x/s 0x402622
> 
> 0x402622:       "DrEvil"

因此，只需要在***phase_4***后附加一个字符串`DrEvil`即可触发`secret_phase`

> Halfway there!
> 
> 0 0 DrEvil
> 
> So you got that one.  Try this one.
> 
> 9?>567
> 
> Good work!  On to the next...
> 
> 4 3 2 1 6 5
> 
> Curses, you've found the secret phase!
> 
> But finding it and solving it are quite different...

可以看到成功触发，接下来继续对`secret_phase`进行分析。这里把代码分成两部分，先看第一部分

```assembly
0000000000401242 <secret_phase>:
  401242:	53                   	push   %rbx
  401243:	e8 56 02 00 00       	callq  40149e <read_line>
  401248:	ba 0a 00 00 00       	mov    $0xa,%edx
  40124d:	be 00 00 00 00       	mov    $0x0,%esi
  401252:	48 89 c7             	mov    %rax,%rdi
  401255:	e8 76 f9 ff ff       	callq  400bd0 <strtol@plt>
  40125a:	48 89 c3             	mov    %rax,%rbx
  40125d:	8d 40 ff             	lea    -0x1(%rax),%eax
  401260:	3d e8 03 00 00       	cmp    $0x3e8,%eax
  401265:	76 05                	jbe    40126c <secret_phase+0x2a>
  401267:	e8 ce 01 00 00       	callq  40143a <explode_bomb>
```

这段代码先读入一个字符串，然后调用了`strtol`函数，查阅文档可得该函数原型为

```c
long strtol( const char *restrict str, char **restrict str_end, int base );
```

因此根据传入的参数可知，该函数从输入字符串中读取一个`long`型10进制数，然后将其减1并与`0x3e8`(1000)进行比较，若大于则引爆炸弹

然后看第二部分

```assembly
  40126c:	89 de                	mov    %ebx,%esi
  40126e:	bf f0 30 60 00       	mov    $0x6030f0,%edi
  401273:	e8 8c ff ff ff       	callq  401204 <fun7>
  401278:	83 f8 02             	cmp    $0x2,%eax
  40127b:	74 05                	je     401282 <secret_phase+0x40>
  40127d:	e8 b8 01 00 00       	callq  40143a <explode_bomb>
  401282:	bf 38 24 40 00       	mov    $0x402438,%edi
  401287:	e8 84 f8 ff ff       	callq  400b10 <puts@plt>
  40128c:	e8 33 03 00 00       	callq  4015c4 <phase_defused>
  401291:	5b                   	pop    %rbx
  401292:	c3                   	retq
```

可以看到这段代码将`0x6030f0`和输入的数字作为参数传入`fun7`中，当返回值为2时函数结束，否则引爆炸弹，因此重点就在这个`fun7`中。

按照惯例先看一下`fun7`的汇编

```assembly
0000000000401204 <fun7>:
  401204:	48 83 ec 08          	sub    $0x8,%rsp
  401208:	48 85 ff             	test   %rdi,%rdi
  40120b:	74 2b                	je     401238 <fun7+0x34>
  40120d:	8b 17                	mov    (%rdi),%edx
  40120f:	39 f2                	cmp    %esi,%edx
  401211:	7e 0d                	jle    401220 <fun7+0x1c>
  401213:	48 8b 7f 08          	mov    0x8(%rdi),%rdi
  401217:	e8 e8 ff ff ff       	callq  401204 <fun7>
  40121c:	01 c0                	add    %eax,%eax
  40121e:	eb 1d                	jmp    40123d <fun7+0x39>
  401220:	b8 00 00 00 00       	mov    $0x0,%eax
  401225:	39 f2                	cmp    %esi,%edx
  401227:	74 14                	je     40123d <fun7+0x39>
  401229:	48 8b 7f 10          	mov    0x10(%rdi),%rdi
  40122d:	e8 d2 ff ff ff       	callq  401204 <fun7>
  401232:	8d 44 00 01          	lea    0x1(%rax,%rax,1),%eax
  401236:	eb 05                	jmp    40123d <fun7+0x39>
  401238:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
  40123d:	48 83 c4 08          	add    $0x8,%rsp
  401241:	c3                   	retq
```

简单分析一下代码和内存可以看出，这段代码主要是递归访问二叉树，因此为了分析具体逻辑对该段代码进行反编译

```c
int fun7(struct BinTree * root, int num, int ret)
{
    if(root = NULL)
        ret = 0xffffffff;
    else if(root->value > num)
        ret = 2*fun7(root->left, num, ret);
    else
    {
        ret = 0;
        if(root->value != num)
            ret = 2*fun7(root->right, num, ret) + 1;
    }
    return ret;
}
```

根据代码逻辑分析，为了能够最终返回2，应该在第6行处调用`fun7`且返回1；若要`fun7`返回1，则应该在第11行处调用`fun7`且返回0；若要`fun7`返回0，则应该使num等于root->value。

因此最终二叉树的遍历路径为先访问左分支，再访问右分支，然后使num与当前分支的数据域相等即可。

使用`GDB`查看对应的数值

> GDB>x/dw \*(0x10+\*(0x6030f0+0x8))
> 
> 0x603150 \<n32\>: 22

因此得到***secret_phase***为`22`

## 总结

做完这个Lab之后现在看汇编都如同看C代码了，而且在这些机器码中穿梭本身也是一种乐趣。加上`objdump`和`GDB`这些强大的工具，降低了许多调试的难度。在看多了汇编以后，愈发体验到高级语言的强大和简洁，不得不佩服搞出各种编译器的那帮人

