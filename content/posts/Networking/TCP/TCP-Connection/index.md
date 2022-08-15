---
title: "TCP连接"
subtitle: ""
date: 2021-11-02T19:29:02+08:00
lastmod: 2022-08-15T19:45:06+08:00
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

TCP是面向连接的协议，因此在数据传输之前需要先建立连接状态，传输完成后需要断开连接。

在建立连接、数据传输和断开连接时TCP会发生一系列同步过程，TCP连接的状态也随之发生变化，
因此可以将TCP连接看作一个状态机模型。
事实上，TCP标准为TCP连接规定了若干种状态，并且随着各个过程发生转换。

<!--more-->

<!-- Main Content -->

## 建立连接: 三步握手

在TCP连接中，连接双方符合C/S通信模型，即客户端主动发起建立连接的请求，
服务器则时刻监听其服务端口以便能够及时收到客户端的连接请求并完成建立连接的过程。
实际上TCP连接双方都有可能发起TCP连接，因此这里的C/S只是一个相对的概念，
即C端表示发起连接的一方，S端表示接收连接请求的一方。

要完成建立连接，需要通信双方(即C端和S端)互相进行共计3次通信，因此这三次通信过程也叫做三步握手
(Three-way handshake)。

### 监听端口

并不是所有主机之间都能够直接进行通信，而是需要S端首先对通信端口(Port)进行监听(Listen)，
然后才能收到来自发送端的消息。接收端监听的端口称为**开放服务端口**或**开放端口**，
大部分应用层开源协议都会与某个端口号相关联并规定在标准文件中，这些端口也称为对应协议的端口。
比如HTTP端口(80)、HTTPS端口(443)、SSH端口(22)等等。

端口协议列表详见[[IANA]Service Name and Transport Protocol Port Number Registry](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml)

由于不是所有应用层协议都以TCP为基础，比如有些应用层协议使用UDP或SCTP，
因此开放端口并不都提供TCP服务，有的端口只提供UDP服务，还有的端口能同时提供多种协议的服务。

当TCP的S端开始监听其服务端口后，其状态从`CLOSED`切换为`LISTEN`

### 发送连接请求C -> S

C端首先向S端发送一封`SYN`包，表示发起TCP连接请求。该`SYN`包具有以下属性

- 设置了`SYN`标志位
- 序号为`ISS`(Initial Send Sequence number)
- 不携带数据

状态切换：`CLOSED`->`SYN_SENT`

### 回应连接请求C <- S

S端在接收到来自C端的`SYN`包后，将判断该连接请求是否有效。

若请求无效(比如目标端口不提供TCP服务)，则回应设置了`RST`标志的`RST`包，表示拒绝(Reject)连接。

若请求有效，则回应`SYN-ACK`包，表示同意建立连接。`SYN-ACK`包具有以下属性

- 设置了`SYN`和`ACK`标志位
- 序号为`IRS`(Initial Receive Sequence number)
- 确认号为`SYN`包的`SEG.SEQ`+`1`
- 不携带数据

状态切换：`LISTEN`->`SYN_RCVD`

此时TCP连接处于**半连接**(Half-Open Connection)状态。

在收到合法的连接请求后，S端往往会为本次TCP连接分配各种资源，如缓冲区(buffer)和各种变量。
这种在连接建立之前就分配资源的行为会导致TCP的安全问题，比如**SYN洪水**(SYN flood)，
是**拒绝服务攻击**(Denial of Service, DoS)的一种形式。
因此目前的TCP的S端通常会使用叫做**SYN cookie**的技术来抵御SYN洪水。

{{< admonition type=info title="SYN cookie" open=false >}}

当S端收到合法连接请求后先对`SYN`包内的地址信息(双方IP地址、端口号)进行加盐散列运算，
将散列结果(即`cookie`)作为`SYN-ACK`包的序号直接发送，而不进行资源分配。
在随后收到`ACK`包后再使用同样的散列算法计算一次`cookie`，
若满足`SEG.ACK`=`cookie`+`1`则说明该请求是正常的连接请求，此时才为该连接分配资源，
并且使用`SEG.ACK`初始化`SND.NXT`

[关于SYN cookie的详细内容](https://wikipedia.org/wiki/SYN_cookies)

{{< /admonition >}}

### 连接建立C -> S

若C端收到`RST`包，则中断(Abort)建立连接的过程，将状态重置为`CLOSED`。

若C端收到`SYN-ACK`包，则回应的`ACK`包，表示TCP连接建立完成。`ACK`包具有以下属性

- 设置了`ACK`标志位
- 并且设置确认号为`SYN-ACK`包的`SEG.SEQ`+`1`
- 可能携带数据

状态切换：`SYN_SENT`->`ESTABLISHED`

C端在建立连接后将为本次连接分配资源。

S端在收到该`ACK`包后进行状态切换：`SYN_RCVD`->`ESTABLISHED`

当双方均处于`ESTABLISHED`状态时，连接建立完成，可以开始数据传输。
此时`SND.NXT`为`ISS`+`1`，即第一个数据包的`SEG.SEQ`为`ISS`+`1`

注意，TCP数据传输可能发生在建立连接时期，但TCP层必须在连接建立完成后才能将数据上传给应用层，
在此之前需将数据缓存[^1]。

## 关闭连接

TCP连接的双方都有可能要求关闭连接，对任意一方来说其同步都是相同的，
这里考虑C端主动要求关闭连接的情况。

1. C端发送给S端一个设置了`FIN`标志位的`FIN`包表示关闭连接
    - 状态切换: `ESTABLISHED` -> `FIN_WAIT_1`
2. S端收到C端发来的`FIN`包后返回一个`ACK`包
    - 状态切换: `ESTABLISHED` -> `CLOSE_WAIT`
3. C端收到S端的`ACK`包
    - 状态切换: `FIN_WAIT_1` -> `FIN_WAIT_2`
4. S端再次发送一个`FIN`包给C端
    - 状态切换: `CLOSE_WAIT` -> `LAST_ACK`
5. C端收到S端发来的`FIN`包后返回一个`ACK`包
    - 状态切换: `FIN_WAIT_2` -> `TIME_WAIT` -等待一段时间后[^2]-> `CLOSED`
    - 状态切换为`CLOSED`后释放所有资源并解除端口占用
6. S端收到C端发来的`ACK`包后正式关闭连接
    - 状态切换: `LAST_ACK` -> `CLOSED`
    - 释放所有资源并解除端口占用


## 状态转换图

下面的状态转换图来自[RFC 793](https://www.rfc-editor.org/rfc/rfc793)

```State
                              +---------+ ---------\      active OPEN
                              |  CLOSED |            \    -----------
                              +---------+<---------\   \   create TCB
                                |     ^              \   \  snd SYN
                   passive OPEN |     |   CLOSE        \   \
                   ------------ |     | ----------       \   \
                    create TCB  |     | delete TCB         \   \
                                V     |                      \   \
                              +---------+            CLOSE    |    \
                              |  LISTEN |          ---------- |     |
                              +---------+          delete TCB |     |
                   rcv SYN      |     |     SEND              |     |
                  -----------   |     |    -------            |     V
 +---------+      snd SYN,ACK  /       \   snd SYN          +---------+
 |         |<-----------------           ------------------>|         |
 |   SYN   |                    rcv SYN                     |   SYN   |
 |   RCVD  |<-----------------------------------------------|   SENT  |
 |         |                    snd ACK                     |         |
 |         |------------------           -------------------|         |
 +---------+   rcv ACK of SYN  \       /  rcv SYN,ACK       +---------+
   |           --------------   |     |   -----------
   |                  x         |     |     snd ACK
   |                            V     V
   |  CLOSE                   +---------+
   | -------                  |  ESTAB  |
   | snd FIN                  +---------+
   |                   CLOSE    |     |    rcv FIN
   V                  -------   |     |    -------
 +---------+          snd FIN  /       \   snd ACK          +---------+
 |  FIN    |<-----------------           ------------------>|  CLOSE  |
 | WAIT-1  |------------------                              |   WAIT  |
 +---------+          rcv FIN  \                            +---------+
   | rcv ACK of FIN   -------   |                            CLOSE  |
   | --------------   snd ACK   |                           ------- |
   V        x                   V                           snd FIN V
 +---------+                  +---------+                   +---------+
 |FINWAIT-2|                  | CLOSING |                   | LAST-ACK|
 +---------+                  +---------+                   +---------+
   |                rcv ACK of FIN |                 rcv ACK of FIN |
   |  rcv FIN       -------------- |    Timeout=2MSL -------------- |
   |  -------              x       V    ------------        x       V
    \ snd ACK                 +---------+delete TCB         +---------+
     ------------------------>|TIME WAIT|------------------>| CLOSED  |
                              +---------+                   +---------+
```

[^1]:[RFC 793 - Section3.4](https://www.rfc-editor.org/rfc/rfc793#section-3.4)
[^2]: 为了防止最后一个`ACK`包丢失的情况通常会在发送后等待两倍的数据包生命周期，在此期间保持占用端口。可以通过设置端口复用来快速重启服务。具体内容查看[RFC 793 - Section3.5](https://www.rfc-editor.org/rfc/rfc793#section-3.5)
