---
title: "Book & Log"
subtitle: ""
date: 2022-08-17T15:51:36+08:00
lastmod: 2022-08-17T15:51:36+08:00
draft: true
description: ""
tags:
  - Thoughts
categories:
  - Essay
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

<!--more-->

<!-- Main Content -->

昨天[@lidangzzz](https://twitter.com/lidangzzz)发了一条关于书的推文，内容如下

{{< tweet user="lidangzzz" id="1559563876903051266" >}}

当然这条推特引来了很多批评，我也不想再作任何评价，但是这忽然让我与最近正在学习的分布式系统的一些概念联想到了一起。

在分布式系统中，通过Primary/Backup机制实现Fault-Tolerance，其中Backup需要与Primary保持同步，
从而在Primary出现不可用的情况时能够及时接替。
要保持两个系统的状态同步，一个常规操作是记录Primary的所有操作到日志中，Backup通过replay日志进行状态同步。
由于系统中存在一些non-deterministic operation，因此日志中还需要记录额外的信息来保证Backup能在replay
后达到与Primary完全同步的状态。由于带宽和性能的限制，Backup通常难以做到实时同步，会落后Primary一段时间。

而书，不管是传统的纸质书，还是电子书，对我来说就像是日志一样。作为一个后来者，我就像是Backup，
难以跟上最前沿的研究进展，但所有的这些进展，在经过争议、达成共识后，沉淀到了一本本书上面，
从而让我这个Backup能够replay，更新自己的状态，并且或许在未来的某天，能够接替Primary。

也许书籍的时效性、互动性确实不如新的知识载体，但对于我这样一个非科研水平的学习者来说，
这些"时效性"的价值远远不如一本系统且深入的专业书籍所带给我的思考与感动。相比于迷失在各种时髦的名词当中，
我更愿意跟随前人的脚步，一步一步构建起我自己的知识系统。
