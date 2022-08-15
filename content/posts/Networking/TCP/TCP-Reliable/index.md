---
title: "TCP可靠传输机制"
subtitle: ""
date: 2021-11-02T18:17:59+08:00
lastmod: 2022-08-15T19:43:11+08:00
draft: false
description: ""
tags:
  - Networking
categories:
  - Protocol
series:
  - TCP
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

TCP是一个有状态的，面向连接的协议，其在下层不可靠传输的基础上提供了一层抽象，
使连接双方可将TCP看作一个能够可靠传输数据的端到端通道，
保证接收方从TCP层收到的数据与发送方送往TCP层的数据的内容和顺序一致。

<!--more-->

<!-- Main Content -->

理论上讲，TCP/IP五层模型的任何一层都可以提供可靠的数据传输，但由于层间通信仍有可能会引入错误，
使得以提供可靠传输服务的下层为基础的传输协议仍有可能是非可靠的传输，
因此在紧邻应用层的传输层提供可靠传输服务将使得该服务的价值最大化。
另一方面，也可以基于UDP(不提供可靠传输服务)直接在应用层实现数据的可靠传输。

> *"functions placed at the lower levels may be redundant or of litle value when*
> *compared to the cost of providing them at the higher level."* [^1]

可靠传输服务主要包括以下三部分

- 乱序重组
- 错误检测
- 丢包处理

针对这三种需求，TCP分别使用对应的机制来实现。

## 乱序重组: 序号

TCP使用**序号**(Sequence Number)对发送的字节流进行编号，接收方可以根据序号对收到的数据重新排序。
接收方收到数据后会发送**确认包**(Acknowledgment Segment)，
其中包含声明自己已经无误接收到的数据流的**确认号**(Acknowledgment Number)。
通过使用序号和确认号可以确保发送方送入TCP层的数据与接收方从TCP层收到的数据顺序一致。

具体来说，发送方为每个数据包附上一个序号`SEG.SEQ`，其表示发送数据的开头在数据流中的字节位置；
接收方接收到该数据包后会将序号加上数据长度(Payload Length)作为确认号，
并回应一个含有确认号`SEG.ACK`的确认包。

考虑一个单向传输数据的TCP连接

1. 发送方维护两个变量`SND.NXT`和`SND.UNA`并初始化为相同的**序号初始值**(Initial Send Sequence number, ISS)。
  `ISS`通常会随机选取[^2]以防御[TCP序号预测攻击](https://wikipedia.org/wiki/TCP_sequence_prediction_attack)。
  把这两个变量的值减去`ISS`的结果作为相对值，从而能够将`ISS`当作相对`0`来考虑，
  相对值只与发送的字节数有关而与`ISS`的取值无关。其中
    - `SND.NXT`表示发送方下个数据包的序号，其相对值表示尚未发送的数据在数据流中的字节位置
    - `SND.UNA`表示尚未被确认的最小序号，其相对值表示尚未被确认的数据在数据流中的字节位置
2. 接收方维护一个变量`RCV.NXT`并使用收到的第一个数据包的`SEG.SEQ`作为初始值(即`ISS`)
3. TCP连接建立完成后数据流的第一个字节的序号为`ISS`+`1`，详见[TCP连接]({{< ref "posts/Networking/TCP/TCP-Connection" >}})
4. 发送方发送序号为`SND.NXT`，包含数据长度为`n`的报文，并将`SND.NXT`更新为`SND.NXT`+`n`
5. 接受方收到序号为`RCV.NXT`的数据包并确认无误后将`RCV.NXT`更新为`RCV.NXT`+`n`
   并延时等待最多`500ms`[^3] (若已处于等待状态则结束等待并立即发送所有等待中的确认包)，
   然后发送确认号为`RCV.NXT`的确认包，表示下个数据包的期望序号为`RCV.NXT`
6. 当发送方收到的确认包满足`SEG.ACK`>`SND.UNA`时将`SND.UNA`更新为`SEG.ACK`

当接收方接收到`SEG.SEQ`与`RCV.NXT`不一致的数据包时(out-of-order segment)[^4]

- 若`SEG.SEQ`<`RCV.NXT`，则重新发送确认号为`RCV.NXT`的确认包并丢掉接受到的内容
- 若`SEG.SEQ`>`RCV.NXT`，TCP标准没有规定暂存还是丢掉该数据包，
  但通常情况会暂存该数据包并记录`SEG.SEQ`与`RCV.NXT`的间隔(Gap)。
  若后续数据包完全或部分填补间隔(Gap)，
  则立即发送确认号为间隔最左端(lower end of the gap)的确认包

实际上，TCP通信双方都会各自维护发送方和接收方两套变量，
因此在TCP数据传输中会有两个序号和两个响应号。

## 错误检测: 校验和

为了确保通信双方发送和接受到的内容一致，TCP使用**校验和**(Checksum)机制来对TCP数据包进行校验。

### 计算校验和

发送方首先对以下三部分进行求和(以16 bits为单位，不足16 bits的右端补`0`)

- IP伪首部
- TCP的首部字段(`Checksum`字段初始为`0x0000`)
- TCP的数据内容(`Data Payload`)

再对求和结果求其反码，就得到了校验和，并将其填入数据包的`Checksum`字段中。
接收者在收到数据包后连同`Checksum`字段按相同的算法再计算一次校验和。
如果计算结果为`0xFFFF`，那么就表明数据包没有检测出错误和完整性缺失。

### 错误处理

当检测出错误时:

- 发送方重新发送序号为`SND.UNA`的数据包
- 接收方重新发送确认号为`RCV.NXT`的确认包

### IP伪首部

IPv4的**IP伪首部**(96 bits)包括

- Source Address: 发送方的IPv4地址(32 bits)
- Destination Address: 接收方的IPv4地址(32 bits)
- Zeros: 固定填充位`0x00`(8 bits)
- Protocol: 上层协议编号(8 bits)
- Upper-Layer Packet Length: 上层协议报文字节长度，此处为TCP报文长度(16 bits)

IPv4的校验和具体计算方式定义在
[RFC 793 - Section 3.1](https://datatracker.ietf.org/doc/html/rfc793#page-16)

IPv6的**IP伪首部**(320 bits)包括

- Source Address: 发送方的IPv6地址(128 bits)
- Destination Address: 接收方的IPv6地址(128 bits)
- Upper-Layer Packet Length: 上层协议报文字节长度，此处为TCP报文长度(32 bits)
- Zeros: 固定填充位`0x000000`(24 bits)
- Next Header: 上层协议编号(8 bits)

IPv6的校验和具体计算方式定义在
[RFC 2460 - Section 8.1](https://datatracker.ietf.org/doc/html/rfc2460#section-8.1)

> IP伪首部不是真正的IP首部，而只是IP首部的一部分字段，因此叫做"伪"首部(IP Pseudo-header)

协议编号详见[[IANA]Assigned Internet Protocol Numbers](https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml)

{{< admonition type=info title="关于TCP校验和的校验强度" open=false >}}

由于`Checksum`字段仅使用了简单的求和方式，校验和发生碰撞的概率较大，
因此现代TCP通信通常会在数据链路层额外使用`CRC`来增强校验能力。关于CRC算法详见
[CRC算法的原理、实现、以及常用模式]({{< ref "posts/Networking/CRC" >}})

观察表明，即使在受到CRC校验保护的转发和层间跳转过程中软件和硬件仍会引入错误，
因此TCP的校验和作为端到端检验仍有其存在价值

{{< /admonition >}}

## 丢包处理: 重传

### 超时

TCP使用**超时**(Timeout)机制检测丢包，当发送一个数据包后在**重传时长**(Retransmission TimeOut, RTO)内没有收到对应的确认包，
便视为该数据包或确认包丢失，此时会重新发送一次该数据包。

当`RTO`过小时会导致由于网络拥塞或路由等延迟因素没有及时收到的报文被当作丢失处理，
从而增加重传的数据量，增大网络负载，可能会导致延迟更加严重，也会导致发送方带宽利用率降低；
过大时会使等待确认的时间过长从而降低带宽利用率。 由于网络因素时刻在发生变化，
因此`RTO`不适合使用静态值，而应根据网络状况动态计算出最适合的取值。

### 计算重传时长[^5]

发送方维护两个变量`SRTT`(Smoothed Round-Trip Time)和`RTTVAR`(Round-Trip Time Variation)，
并且选择`G`作为时钟粒度(Clock Granularity)，则有

{{< math >}}
$$
  \mathrm{RTO} = \mathit{max}\{\mathrm{SRTT} + \mathit{max} \{\mathrm{G}, \mathrm{K}\cdot \mathrm{RTTVAR}\},\;1\}
$$
{{< /math >}}

其中$\mathrm{K}=4$

当第一次测出`RTT`后，将`SRTT`的初始化为`RTT`，`RTTVAR`的初始化为`RTT/2`；
由于首次通信发生之前无法测出`RTT`的值，因此通常选择`1s`[^6]作为`RTO`的初始值。

在后续通信过程中，每次测量出新`RTT`后按以下顺序更新`SRTT`和`RTTVAR`，最后再更新`RTO`

{{< math >}}
$$
\begin{matrix}
\mathrm{RTTVAR}&=&(1-\boldsymbol\beta)\cdot \mathrm{RTTVAR}+\boldsymbol\beta \cdot |\mathrm{SRTT}-\mathrm{RTT}|\\
\mathrm{SRTT}&=&(1-\boldsymbol\alpha)\cdot \mathrm{SRTT}+\boldsymbol\alpha \cdot \mathrm{RTT}
\end{matrix}
$$
{{< /math >}}

其中$\boldsymbol{\alpha}=0.125, \\;\boldsymbol{\beta}=0.25$[^7]

### 超时重传机制[^8]

- 在发送方发送一个数据包后(包括重传)，若定时器尚未运行，则启动定时器
- 当收到预期的确认包(即`SEG.ACK`>`SND.UNA`)后重置定时器
- 当`SND.UNA`==`SND.NXT`时，关闭定时器
- 当定时器超时后，重新发送序号为`SND.UNA`的数据包，将`RTO`设置为原来的2倍(back off the timer)
  但不能超过上限(上限最小为`60s`)，然后重启定时器。若超时发生在连接建立时期，即(SYN-ACK)超时，
  且该TCP实现的`RTO`初始值小于`3s`，则在连接建立后需将`RTO`重新初始化为`3s`
- 若发生重传后收到了其他数据包的确认，则按照公式重新计算`RTO`。
  由于发生超时可能意味着网络状况发生变化，因此TCP实现可能会在超时后重新初始化`SRTT`和`RTTVAR`

注意，由于确认包表示位于`SEG.ACK`及之前的数据均已被无误接收，
因此即使传输过程中一部分确认包发生丢失， 只要发送方仍能收到后续的确认包，
即可认为丢失确认包的数据包没有丢失，无需重传

### 快速重传机制[^9]

由于TCP使用流水线(Pipeline)的方式发送数据包，当定时器超时后通常已经发送了许多数据包，
因此使用超时机制并不能及时的检测到丢包。针对这种情况，
TCP使用一种**快速重传**(Fast Retransmit and Recovery, FRR)机制，
即当发送方连续收到三个重复的确认包(不包括原始确认包)且`SEG.ACK`<`SND.UNA`时视为发生了丢包，
随即重传序号为`SND.UNA`的数据包而无需等到定时器超时。此时需按照超时重传机制重置定时器。

当发生单独的数据包丢失时，快速重传机制效率最高；
当多个数据包在短时间内丢失时快速重传则无法很有效的工作。

## 其他问题

TCP数据包的用于储存`SEG.SEQ`的空间长度只有32 bits，因此当发送的数据量足够大时(大于4GB)，
网络中可能同时存在两个`SEG.SEQ`相同但携带不同数据的合法数据包，
这种情况称为**序号混迭**(Sequence number warp-around)

为了解决这个问题，需要根据TCP的传输速率规定TCP数据包的**最大存活周期**(Maximum Segment Lifetime, MSL),
也可以对储存序号的空间进行扩容(涉及到更改TCP首部字段, 实施困难)或使用`Option`字段扩大`SEG.SEQ`的数值空间

[RFC 7323](https://datatracker.ietf.org/doc/html/rfc7323)
讨论了TCP高速传输数据时可能出现的问题以及对应的解决方案。

[^1]: J. Saltzer, D. Reed, D. Clark, “End-to-End Arguments in System Design, ” ACM Transactions on Computer Systems (TOCS), Vol. 2, No. 4 (Nov. 1984).
[^2]: [RFC 793 - Section 3.3 Initial Sequence Number Selection](https://datatracker.ietf.org/doc/html/rfc793#section-3.3)
[^3]: [RFC 1122 - Section 4.2.3.2 When to Send an ACK Segment](https://datatracker.ietf.org/doc/html/rfc1122#page-96)
[^4]: [RFC 5681 - Section 4.2 Generating Acknowledgments](https://datatracker.ietf.org/doc/html/rfc5681#section-4.2)
[^5]: [RFC 6298 - Computing TCP's Retransmission Timer](https://datatracker.ietf.org/doc/html/rfc6298)
[^6]: [RFC 6298 - Section 2.1](https://datatracker.ietf.org/doc/html/rfc6298#section-2)
[^7]: [Jacobson, V. and M. Karels, "Congestion Avoidance and Control"](ftp://ftp.ee.lbl.gov/papers/congavoid.ps.Z.)
[^8]: [RFC 6298 - Section 5](https://datatracker.ietf.org/doc/html/rfc6298#section-5)
[^9]: [RFC 5681 - Section 3.2 Fast Retransmit/Fast Recovery](https://datatracker.ietf.org/doc/html/rfc5681#section-3.2)
