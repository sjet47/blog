---
title: Data Lab
description: CS:APP DataLab Writeup
date: 2021-04-09
slug: datalab-writeup
license: CC BY-NC-ND
categories:
    - CS:APP-Lab
tags:
    - Writeup
---

## 前言

一开始看到这个lab的时候看到是对数据类型进行底层位操作，感觉还是挺简单的，毕竟规则都已经讲过了，但是实际做的时候发现还是有点难度的，最终花了两个晚上完成了这个lab，写一下总结

由于这个lab在[2019/12/16更新](http://csapp.cs.cmu.edu/3e/datalab-release.html)了，所以内容跟网上的一些以前的版本有些变化，感觉是变难了，但也变得更有意思

由于题目涉及到较多的构造，因此尽量将常数和表达式写成自解释名称的变量，便于阅读

##### 环境配置

OS: Ubuntu 20.10 x86_64

由于编译条件使用了`-m32`，因此需要32位运行时系统，安装`gcc-multilib`包

## 题目

### 整数部分

#### 规则

第一部分是对整数进行操作，有一些规则限制，具体如下

##### 允许使用

- 范围在[0,255]的整数
- 传入的函数参数和定义的局部变量
- 单目操作符: `!`, `~`
- 位操作符: `&`, `^`, `|`, `+`, `<<`, `>>`

##### 禁止使用

- 任何结构语句，例如`if`, `do`, `while`, `for`, `switch`等
- 定义或使用宏
- 定义或调用函数
- 除允许使用之外的任何运算符，如`&&`, `||`, `-`, `?:`
- 类型转换(casting)
- 除`int`之外的任何数据类型或数据结构

##### 假设条件

- 有符号整数使用32位补码的方式储存
- 右移操作是算数移位(保留符号位)
- 当移位位数为负或大于31时具有不可预测的行为

#### 题目

##### bitXor(x, y)

> 要求: 只使用`~`和`&`操作符实现异或运算
>
> 可用操作符: `~`, `&`
>
> 数量限制: 14
>
> 难度等级: 1

思路

送分题，考察布尔代数基础知识

```c
int bitXor(int x, int y)
{
    return ~(~(~x & y) & ~(x & ~y));
}
```

使用操作符数量: 8

##### tmin()

> 要求: 构造出32位补码能表示的最小数
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 4
>
> 难度等级: 1

思路

根据Tmin的定义可知其二进制形式为`0x80000000`，使用左移运算即可

```c
int tmin(void)
{
    return 1 << 31;
}
```

使用操作符数量: 1

##### isTmax(x)

> 要求: 若x是32位补码能表示的最大值则返回1，否则返回0
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`
>
> 数量限制: 10
>
> 难度等级: 1

思路

由于这道题限制了不能使用移位操作符，因此无法直接构造出Tmax进行比较，只能通过检验性质来判断。

Tmax没有什么特殊的性质，但其与Tmin是互补的关系，所以可以利用Tmin的性质来判断

Tmin和0都具有一个独特的性质: **没有正负之分**，即Tmin = -Tmin, 0 = -0。因此想到可以通过加了负号前后是否相等来判断x是否是这两个数之一，然后再将这两个区分开即可

```c
int isTmax(int x)
{
    int nx = ~x;
    int neg = ~nx + 1;
    int tmin_or_zero = !(nx ^ neg);
    int is_tmin = !!(nx ^ 0);
    return tmin_or_zero & is_tmin;
}
```

使用操作符数量: 9

##### allOddBits(x)

> 要求: 若x的所有奇数位均为1则返回1，否则返回0
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 12
>
> 难度等级: 2

思路

构造出`0xAAAAAAAA`取出奇数位然后异或比较

```c
int allOddBits(int x)
{
    int oddbits = 0xAA;
    oddbits = (oddbits << 8) | 0xAA;
    oddbits = (oddbits << 16) | oddbits;
    return !((x & oddbits) ^ oddbits);
}
```

使用操作符数量: 7

##### negate(x)

> 要求: 返回-x
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 5
>
> 难度等级: 2

思路

送分题，由原书2.3.3中的*Web Aside DATA:TNEG*可知补码的负数即为取反后加1

```c
int negate(int x)
{
    return ~x + 1;
}
```

使用操作符数量: 2

##### isAsciiDigit(x)

> 要求: 判断x是否在[0x30,0x39]范围中(ASCII的'0'-'9')，若在则返回1，否则返回0
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 15
>
> 难度等级: 3

思路

观察`0x30`和`0x39`的二进制表示可知只有最低4位有区别，于是可以构造出边界值来判断

```c
int isAsciiDigit(int x)
{
    int in_range_flag = !(0x03 ^ (x >> 4));
    int low4 = x & 0x0F;
    int lt_8 = !(low4 >> 3);
    int le_9 = !((low4 >> 1) ^ 0x04);
    int isdigit = lt_8 | le_9;
    return in_range_flag & isdigit;
}
```

使用操作符数量: 11

##### conditional(x, y, z)

> 要求: 使用位操作模拟条件运算符?:
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 16
>
> 难度等级: 3

思路

将条件参数x构造成掩码，然后用掩码选择参数即可

```c
int conditional(int x, int y, int z)
{
    int true_flag = ~(((!x) << 31) >> 31); // 0xFFFFFFFF if x == 1 else 0
    return (y & true_flag) | (z & ~true_flag);
}
```

使用操作符数量: 8

##### isLessOrEqual(x, y)

> 如果x <= y则返回1，否则返回0
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 24
>
> 难度等级: 3

思路

当x和y的符号相同时，通过y-x与0的关系进行比较；当符号不同时，通过符号进行比较

```c
int isLessOrEqual(int x, int y)
{
    int tmin = 1 << 31;
    int x_is_pos = !(x & tmin);
    int y_is_pos = !(y & tmin);
    int sign_eq = !(x_is_pos ^ y_is_pos);
    int y_sub_x = y + ~x + 1;
    int y_ge_x = !(y_sub_x >> 31);
    return (sign_eq & y_ge_x) | (!x_is_pos & y_is_pos);
}
```

使用操作符数量: 16

##### logicalNeg(x)

> 要求: 使用位操作模拟!运算符
>
> 可用操作符: `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 12
>
> 难度等级: 4

思路

先找出0和非0数之间的区别，然后再将这两者区分开即可

观察二进制形式，可以发现当x非零时，`x | -x`的符号位始终为1；当x为0时始终为0；可以通过这一点来区分0和非0数

```c
int logicalNeg(int x)
{
    int neg_x = ~x + 1;
    return ((~(x | neg_x)) >> 31) & 1;
}
```

使用操作符数量: 6

##### howManyBits(x)

> 要求: 返回要表达补码形式的x所需要的最少二进制位数
>
> 可用操作符: `!`, `~`, `&`, `^`, `|`, `+`, `<<`, `>>`
>
> 数量限制: 90
>
> 难度等级: 4

思路

这道题还是挺有意思的，难点在于要考虑到符号位对位数的影响

观察正负数的二进制形式可知

- 当x>=0时，最小位数为从左往右第一个1的位置索引+1
- 当x<0时，最小位数为从左往右第一个0的位置索引+1

对于x<0的情况，可以用与`0xFFFFFFFF`异或转换成x>=0的计算方式

明确解决方案后就可以用二分法来优化搜索复杂度

```c
int howManyBits(int x)
{
    int neg_flag = x >> 31;	// 0xFFFFFFFF if x < 0 else 0
    int xp = x ^ neg_flag; 	// (x & ~neg_flag) | (~x & neg_flag)
    int i = 0;
    i = i + ((!!(xp >> (i + 16))) << 4);
    i = i + ((!!(xp >> (i + 8))) << 3);
    i = i + ((!!(xp >> (i + 4))) << 2);
    i = i + ((!!(xp >> (i + 2))) << 1);
    i = i + ((!!(xp >> (i + 1))) << 0);
    i = i + (xp >> i);
    return i + 1;
}
```

**注意**: 由于第10行的代码会忽略(xp >> i)的LSB，因此需要第11行的代码判断该位是否为1

使用操作符数量: 35

### 浮点数部分

#### 规则

浮点数部分相比整数解除了一些限制，说明如下

##### 允许使用

- 整数允许使用的规则
- 条件控制和循环
- 整数和无符号型整数
- 整数和无符号型整数常量
- 任何针对整数的算术运算符、逻辑运算符、比较运算符

##### 禁止使用

- 定义或使用任何宏
- 定义或调用任何函数
- 类型转换(casting)
- 除int和unsigned外的任何数据类型和数据结构
- 浮点类型的操作符和常量

#### 题目

##### floatScale2(uf)

> 要求: 返回在二进制层面上与2*uf相等的值
>
> 可用操作符: 任何整数的操作符、逻辑运算符、比较运算符、`if`和`while`
>
> 数量限制: 30
>
> 难度等级: 4

思路

构造浮点不同域对应的掩码提取出对应的域，对规格化(Normalized)数和非规格化数(Denormalized)分开处理

- 当uf是规格数时(指数域不等于0)，将其指数域+1(2^e * 2 = 2^(e+1))
- 当uf是非规格数时，将其浮点域左移1(等同于浮点域*2)

```c
unsigned floatScale2(unsigned uf)
{
    int exp_mask = 0x7F800000;
    int nexp_mask = 0x807FFFFF;
    int frac_mask = 0x7FFFFF;
    int nfrac_mask = 0xFF800000;
    int e = (uf & exp_mask) >> 23;
    int f = (uf & frac_mask);

    if (e == 0xFF) // if uf == NaN or Inf then return uf
        return uf;

    if (e != 0) // Normalized
        return (uf & nexp_mask) | ((e + 1) << 23);
    else 		// Denormalized
        return (uf & nfrac_mask) | (f << 1);
}
```

使用操作符数量: 12

##### floatFloat2Int(uf)

> 要求: 返回在二进制层面上与(int)uf相等的值，即uf的整数部分
>
> 可用操作符: 任何整数的操作符、逻辑运算符、比较运算符、`if`和`while`
>
> 数量限制: 30
>
> 难度等级: 4

思路

根据浮点类型的表达式f = 1.fff * 2^E 可知，其实际值即把小数点向右移|E|个位置(若e为负则向左)，因此可以通过对浮点域进行右移位操作来把(数学意义上的)小数部分舍弃掉

当浮点数为非常大的数时(E>23)，则需要把浮点域左移|E|-23个位置，这里的23是32位浮点数的浮点域长度

考虑到溢出时的情况，即当左移到`0x80000000`时，继续左移则为不可预测的行为，因此要添加溢出判断

此外还要保持和原浮点数的符号一致

```c
int floatFloat2Int(unsigned uf)
{
    int tmin = 0x80000000;
    int bias = 127;
    int exp_mask = 0x7F800000;
    int frac_mask = 0x7FFFFF;

    int sign = uf >> 31; // 0xFFFFFFFF if uf < 0 else 0
    int e = (uf & exp_mask) >> 23;
    int f = (uf & frac_mask);
    int minus_E = bias + ~e + 1;
    int shift = minus_E + 23;
    int f2i = 0x800000 | f;

    if (e == 0xFF) // if uf == NaN or Inf then return 0x80000000u
        return 0x80000000u;
    if ((uf & 0x7FFFFFFF) == 0) // if uf == +0 or -0 then return 0
        return 0;
    if (e < bias) // if uf < 1 then return 0
        return 0;

    if (shift > 0)
        f2i = f2i >> shift;
    else
        while ((f2i != tmin) && (shift < 0))
        {
            f2i = f2i << 1;
            ++shift;
        }

    if (sign)
        return ~f2i + 1;
    else
        return f2i;
}
```

使用操作符数量: 21

##### floatPower2(x)

> 要求: 返回在二进制层面上与2.0^x相等的值
>
> 可用操作符: 任何整数的操作符、逻辑运算符、比较运算符、`if`和`while`
>
> 数量限制: 30
>
> 难度等级: 4

思路

因为结果始终是2的整次幂，所以其浮点数的二进制形式有以下特点

- 当x是规格数时，浮点域全为0，乘2等于指数域+1，因此只需要将x加上偏置作为指数域即可
- 当x是非规格数时，指数域全为零，乘2等于浮点域左移1，因此只需要把1左移|x|加非规格化偏置个位置作为浮点域即可

```c
unsigned floatPower2(int x)
{
    int inf = 0x7F800000;
    int float_0 = 0x3F800000;
    int bias = 127;
    int denorm_bias = 0xFFFFFF82; // -126
    int minus_23 = 0xFFFFFFE9;
    int length_frac = 23;
    int minus_x = ~x + 1;

    if (x > bias) // too large to represent as a norm, return +INF
        return inf;
    if (x == 0)
        return float_0;

    if (x < (denorm_bias + minus_23)) // too small to represent as a denorm
        return 0;

    if (x >= denorm_bias) // normalized
        return (x + bias) << length_frac;
    else // denormalized
        return 1 << (denorm_bias + minus_x);
}
```

使用操作符数量: 11

## 总结

虽然读完第二章之后感觉已经明白了数据类型的底层原理，但是真正使用的时候还是会暴露一些漏洞，通过这个lab理解了很多特别是浮点数规格化和非规格化表示的一些细节。

此外，一步一步完成这个lab也提高了对一些底层位操作的熟练度，而且也用到了在数电里学到的内容，尤其是做完最后一题回头优化的时候就会发现前面写的很多表达式都是可以写成更加优雅的表达形式。