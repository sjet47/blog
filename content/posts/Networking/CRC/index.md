---
title: "CRC算法的原理、实现、以及常用模式"
subtitle: ""
date: 2021-10-26T12:43:33+08:00
lastmod: 2021-10-27T17:20:19+08:00
draft: false
description: "CRC算法的原理、实现、以及常用模式"
tags:
  - Networking
  - Encoding
categories:
  - Algorithm
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
<!-- Main Content -->

## CRC简介

[CRC(Cyclic Redundancy Check, 循环冗余校验)](https://wikipedia.org/wiki/Cyclic_redundancy_check)
是在数字通信和数据存储领域常用的一种错误检测算法, 由于该算法硬件实现简单,
且容易进行数学分析, 尤其善于检测信道干扰所导致的误码, 因此得到了广泛应用。
CRC算法由[W. Wesley Perterson](https://wikipedia.org/wiki/W._Wesley_Peterson)于1961年发表。

<!--more-->

## 原理

CRC算法采用基于模2运算法则(modulo 2)的二进制除法, 即没有进位和借位, 使用XOR来代替加减法。因此通常在计算时使用二进制数的多项式形式(Polynomial)来表示。即设二进制数第$n$位上的数字为$a_n$, 其对应的多项式为$P = \sum a_n x^n$

设长度为$l$的原始二进制数据为$D$, 给定一个长度为$n$的二进制模式串(pattern)$P$, 将$D$逻辑左移$n-1$位并除以$P$得
$$
  \frac{2^{n-1}D}{P} = Q + \frac{R}{P}
$$
即
$$
  2^{n-1}D = QP + R
$$
其中$R$为除法计算的余数。由模2运算法则可知, 相同的两个数相加结果为0, 则将上式加上$R$可得
$$
  2^{n-1}D+R = QP + R + R = QP
$$
此时等式左边能够被$P$整除, 即余数$R=0$。通过观察可得, 余数$R$的位数至少比$P$的位数少1, 令
$$
  F = 2^{n-1}D + R
$$
则$F$即为CRC编码的结果(Codeword), 其中$F$的前$l$位是原始数据$D$, 后$n-1$位(即余数$R$)称为**CRC校验和(CRC Checksum)**, 在特定领域又称为**帧校验序列(Frame Checksum Sequence, FCS)**。计算$F$除以$P$得到的余数为0, 即说明传输无误码, 否则说明存在错误。

## 实现

基于Python的CRC算法实现(摘自wikipedia)

```python
def crc_remainder(input_bitstring, polynomial_bitstring, initial_filler):
    """Calculate the CRC remainder of a string of bits using a chosen polynomial.
    initial_filler should be '1' or '0'.
    """
    polynomial_bitstring = polynomial_bitstring.lstrip('0')
    len_input = len(input_bitstring)
    initial_padding = (len(polynomial_bitstring) - 1) * initial_filler
    input_padded_array = list(input_bitstring + initial_padding)
    while '1' in input_padded_array[:len_input]:
        cur_shift = input_padded_array.index('1')
        for i in range(len(polynomial_bitstring)):
            input_padded_array[cur_shift + i] \
            = str(int(polynomial_bitstring[i] != input_padded_array[cur_shift + i]))
    return ''.join(input_padded_array)[len_input:]

def crc_check(input_bitstring, polynomial_bitstring, check_value):
    """Calculate the CRC check of a string of bits using a chosen polynomial."""
    polynomial_bitstring = polynomial_bitstring.lstrip('0')
    len_input = len(input_bitstring)
    initial_padding = check_value
    input_padded_array = list(input_bitstring + initial_padding)
    while '1' in input_padded_array[:len_input]:
        cur_shift = input_padded_array.index('1')
        for i in range(len(polynomial_bitstring)):
            input_padded_array[cur_shift + i] \
            = str(int(polynomial_bitstring[i] != input_padded_array[cur_shift + i]))
    return ('1' not in ''.join(input_padded_array)[len_input:])
```

```shell
>>> crc_remainder('11010011101100', '1011', '0')
'100'
>>> crc_check('11010011101100', '1011', '100')
True
```

## 常用模式

通过对CRC算法中的细节进行微调, 可以得到多种CRC变体, 比如在做除法的时候从右往左生成逆向的数据位结果, 或者更改算术位移的填充规则, 亦或者将余数$R$在附加到$D$末尾之前进行字节取反, 此时正确的校验结果不再是0, 而是一个固定的核验多项式$C(X)$, 它的十六进制表示叫做**幻数**。

由CRC算法特性可知, CRC算法错误检测的效果与$P$有直接关系, 其中$P$又称为生成多项式(Generator ploynomial)$P(x)$, 不同的CRC算法之间的主要区别是具有不同的$P$。因此设计多项式$P(x)$是CRC算法实现中最重要的部分, 其直接影响CRC算法的错误检测能力和总体碰撞该率。

### 常用的多项式长度

- 9位(CRC-8)
- 17位(CRC-16)
- 33位(CRC-32)
- 65位(CRC-64)

生成多项式需满足多项式除了1与它自身之外不能被任何其他的多项式整除。

### 生成多项式的特性

- 如果CRC有多于一个的非零系数, 那么CRC能够检查出输入消息中的所有单数据位错误。
- CRC可以用于检测短于2k的输入消息中的所有双位错误, 其中k是多项式的最长的不可分解部分的长度。
- 如果多项式可以被x+1整除, 那么不存在可以被它整除的有奇数个非零系数的多项式。因此, 它可以用来检测输入消息中的奇数个错误, 就像奇偶校验函数那样。
