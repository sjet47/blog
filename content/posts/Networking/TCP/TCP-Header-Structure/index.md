---
title: "TCP首部字段详解"
subtitle: ""
date: 2021-10-31T14:51:41+08:00
lastmod: 2021-10-31T14:51:41+08:00
draft: false
description: "adwaeaw"
tags:
  - Networking
categories:
  - Protocol
series:
  - TCP
hiddenFromHomePage: false
hiddenFromSearch: false
avatarURL : "favicon.svg"
toc:
  enable: true
math:
  enable: true
lightgallery: false
license: "CC BY-NC-ND"
---
<!-- Main Content -->

## TCP 首部字段结构

```Code
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Source Port          |       Destination Port        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Sequence Number                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Acknowledgment Number                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       |     |  Control Bits   |                               |
|  Data | Rese|N|C|E|U|A|P|R|S|F|                               |
| Offset| rved|S|W|C|R|C|S|S|Y|I|            Window             |
|       |     | |R|E|G|K|H|T|N|N|                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Checksum            |         Urgent Pointer        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Options                    |    Padding    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                             data                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

<!--more-->

### Source Port(16 bits)

指示发送该TCP报文的主机端口，以网络字节序(大端)表示

用于多路复用和多路分解

### Destination Port(16 bits)

指示在目标主机上接收该TCP报文的的端口，以网络字节序(大端)表示

用于多路复用和多路分解

### Sequence Number(16 bits)

TCP报文的编号，用于标记TCP报文，详见
[TCP可靠传输机制]({{< ref "posts/Networking/TCP/TCP-Reliable" >}})

### Acknowledgment Number(32 bits)

TCP报文的确认号，用于确认指定TCP报文，详见
[TCP可靠传输机制]({{< ref "posts/Networking/TCP/TCP-Reliable" >}})

### Data Offset(4 bits)

数据相对于TCP报文开头的偏移量，以4字节为单位(32-bit words)。
最小为5(Options字段为空)，最大为15。也可看作首部字段的长度。

### Reserved(3 bits)

保留字段，供未来和非标准用途

### Control Bits(12 bits)

**NS**(Nonces): 实验性特性，用于隐蔽保护，
详见[RFC 3540](https://datatracker.ietf.org/doc/html/rfc3540)

**CWR**(Congestion Window Reduced): 用于响应`ECE`标志位，
详见[RFC 3168](https://datatracker.ietf.org/doc/html/rfc3168)

**ECE**(ECN-Echo): ECE标志位根据SYN位不同有两种用途

- SYN(1): 表示连接方支持`ECN`
- SYN(0): 在正常传输期间接收到IP报文首部字段中含有`ECN=11`字段，表示发送方发生或即将发生网络拥塞

**URG**(Urgent): 指示存在紧急数据，使用`Urgent Pointer`字段指示紧急数据的位置

**ACK**(Acknowledgment): 指示报文为确认报文

**PSH**(Push): 要求推送(push)缓冲区数据给上层应用

**RST**(Reset): 重置连接状态为`CLOSED`

**SYN**(Synchronize): 同步`Sequence Numbers`，只在建立TCP连接时使用

**FIN**(Final): 指示断开TCP连接，在TCP连接断开时使用

### Window size(16 bits)

表示发送该TCP报文一方的接收窗口大小，用于流量控制的滑动窗口协议，
接收该报文的一方在下一次向对方发送数据时数据长度(不包含首部字段)不应超过接收窗口。详见
[TCP流量控制]

### Checksum(16 bits)

储存TCP报文的校验和，用于TCP的错误检测。详见
[TCP可靠传输机制]({{< ref "posts/Networking/TCP/TCP-Reliable" >}})

### Urgent Pointer(16 bits)

当`URG`标志位置1时，表示紧急数据的最后一个字节相对`SEG.SEQ`的偏移量，可以跨多个TCP报文

### Options(0-320 bits)

其他可选项，每个选项长度均为32bits，最多含有10个选项

> 所有TCP实现均应能处理全部的选项

### Date(0-MSS bits)

TCP所携带的数据，长度不超过MSS(Max Segment Size)。通常MSS的默认值为536，
在创建TCP连接时双方会通过`SYN`报文中的`MSS`选项进行**MSS协商**来确定本次连接的MSS值。

---

## 参考文献

[[RFC 793]](https://www.rfc-editor.org/rfc/rfc793#section-3.1)

[[RFC 3168]](https://datatracker.ietf.org/doc/html/rfc3168#section-6.1)

[[RFC 3540]](https://datatracker.ietf.org/doc/html/rfc3540#section-5)

[[Wikipedia]Transmission Control Protocol](https://en.wikipedia.org/wiki/Transmission_Control_Protocol)