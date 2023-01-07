---
title: "Protocol Buffers系列：格式介绍(一)"
subtitle: ""
date: 2023-01-02T14:08:12+08:00
lastmod: 2023-01-05T21:14:14+08:00
draft: false
description: ""
tags:

categories:

series:
  - protobuf

hiddenFromHomePage: false
hiddenFromSearch: false
featuredImage: "protobuf.png"
featuredImagePreview: "protobuf.png"
avatarURL : "favicon.svg"
toc:
  enable: true
math:
  enable: true
lightgallery: false
license: "CC BY-NC-ND"
---
<!-- Summary -->

最近组里的项目需要自己写一套消息序列化协议来代替`protobuf`，
所以顺便研究了一下`protobuf`的原理，以便在造轮子的时候借鉴一下其设计上的优雅之处。

首先介绍一下[Protocol Buffers](https://developers.google.com/protocol-buffers)，
这是由Google开发的一种无关语言、无关平台、高可扩展性、轻量级的结构化数据序列化格式。
它使用一种模式定义语言来描述数据结构，可以通过`protoc`编译器将其编译成对应语言的代码。

Protocol Buffers数据格式在不同语言和平台间具有高度一致性，
生成的代码也具有相似的功能，因此其通常作为分布式组件和微服务之间数据通信的序列化协议。

<!--more-->

---

**这篇Blog是protobuf系列的第一篇，整个系列目录如下**

- Protocol Buffers系列：格式介绍(一)
- [Protocol Buffers系列：编码方式(二)]({{< ref "posts/tool/protobuf/encoding" >}})

--

<!-- Main Content -->

## 代码生成

Protocol Buffers的工作流程如下所示

`file.proto` => `protoc` => `language-specified code`

其中`protoc`是用来将`.proto`文件编译成对应语言平台代码的编译器。在编译时需要安装对应语言的编译器后端

以[Go](https://go.dev)为例

```shell
# 安装用于生成Go代码的编译器后端protoc-gen-go
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
# 在DST_DIR目录中生成对应的Go代码
protoc --proto-path=<IMPORT_PATH> --go_out=<DST_DIR> path/to/file.proto
```

其他语言可以用以下参数来生成对应的代码

- `--cpp_out=<DST_DIR>` generates C++ code in DST_DIR.
- `--java_out=<DST_DIR>` generates Java code in DST_DIR.
- `--kotlin_out=<DST_DIR>` generates additional Kotlin code in DST_DIR.
- `--python_out=<DST_DIR>` generates Python code in DST_DIR.
- `--ruby_out=<DST_DIR>` generates Ruby code in DST_DIR.
- `--objc_out=<DST_DIR>` generates Objective-C code in DST_DIR.
- `--csharp_out=<DST_DIR>` generates C# code in DST_DIR.
- `--php_out=<DST_DIR>` generates PHP code in DST_DIR.

## `.proto` 文件格式

```proto
syntax = <proto.version>;

import *public "other_proto_file_path"; // 可以导入其他.proto文件来使用其中的定义

package PackageName; // 定义该.proto文件的命名空间

[file option];

message MessageName {
  // 将某个FieldName或FieldNumber设为保留值，这两种保留值需写在不同的reserved语句中，可省略
  reserved ...;

  // scalar类型，默认为singular
  [optional] singular|repeated FieldType FieldName = FieldNumber;

  // map类型
  [optional] <KeyType, ValueType> FieldName = FieldNumber;
}

enum EnumName {
  option allow_alias = true|false; // 允许不同的case具有相同的enum number
  CaseName = EnumNumber;
}

oneof OneofName {
  // 不能出现repeated和map类型的field
  FieldType FieldName = FieldNumber;
}
```

- 在一个结构内部可以嵌套定义其他的结构，而且嵌套层数可以无限深，并且可以从外部通过`__Parent__.__Type__`访问
- `map`类型实际上是一个别名，以下两种定义是一样的

```proto
// Define 1
message MapFieldEntry {
  optional key_type key = 1;
  optional value_type value = 2;
}
repeated MapFieldEntry map_field = N;

// Define 2
map<key_type, value_type> map_field = N;
```

## 标量类型

### Numeric

| type     | .proto type 32bit | .proto type 64bit | note                                                                       |
| -------- | ----------------- | ----------------- | -------------------------------------------------------------------------- |
| 有符号数 | int32             | int64             | 使用变长编码格式                                                           |
| 有符号数 | sint32            | sint64            | 使用变长编码格式，当编码负数时比对应的`int`类型更有效率                    |
| 有符号数 | sfixed32          | sfixed64          | 固定字节长度                                                               |
| 无符号数 | uint32            | uint64            | 使用变长编码格式                                                           |
| 无符号数 | fixed32           | fixed64           | 固定字节长度，当值较大时比对应的`uint`类型更有效率(32bit 2^28, 64bit 2^56) |
| 浮点数   | float             | double            | IEEE 754标准浮点数                                                         |

### Others

| .proto type | note                                                                              |
| ----------- | --------------------------------------------------------------------------------- |
| bool        |                                                                                   |
| string      | 长度小于2^32的合法UTF-8字符串(7-bit ASCII和其对应的UTF-8编码相同，所以也是合法的) |
| bytes       | 长度小于2^32的字节序列                                                            |


### 默认值

在反序列化过程中，缺失的field会被设置为默认值，同样，消息对象中具有默认值的field不会被序列化。
对于不同的field类型，其默认值定义如下

- `string`: 空字符串
- `bytes`: 空字节序列
- `bool`: False
- `numeric`: 0/0.0
- `enum`: 第一个enum case
- `composite`: language-dependent

> 注意：protobuf在反序列化时无法区分一个field的值被显式设置为了默认值还是没有设置，
> 所以不要把这个默认值作为重要的判断条件

## 复合类型

### `message`类型

Example

```proto
message Person {
  string name = 1;
  int32 id = 2;
  repeat string email = 3;
  optional string addr = 4;
}
```

#### Field Number

Field number用于在反序列化时识别不同的field，为了保证兼容性，
在更新`.proto`文件时不要修改已有field的field number，
而是以增量更新的方式为新创建或更新的field分配一个新的field number。

当需要删除某个field时，需要将其对应的field number或field name声明在`reserved`语句中，
以避免未来的更新可能会重复使用这一field number或field name
(如果不需要考虑兼容性可以不使用`reserved`声明)

> 注意：field number和field名必须声明在不同的`reserved`语句中

其中field number的范围为`[1,2^29-1]`，此外`[19000,19999]`是protobuf保留范围，不能使用。
可以通过`FieldDescriptor::kFirstReservedNumber`和`FieldDescriptor::kLastReservedNumber`
获取这两个上下限。声明为`reserved`的field number也不能使用

不同范围的field number会被编码成不同长度的字节串，具体如下

| range   | byte size |
| ------- | --------- |
| 1-15    | 1         |
| 16-2047 | 2         |

因此应该将1-15保留给`required`以及会频繁出现的`optional`field
(还要考虑到将来可能出现的符合这种条件的field)，
16-2047保留给不经常出现的`optional`field

#### Field Type

`message`支持以下field类型

- `singular` 非数组类型，该类型为默认类型，无需显式声明
- `repeated` 有序数组类型，长度可以为0
- `optional` 只有该field被设置时(非默认值)才会被序列化
- `map`

### `enum`类型

- `enum`的`EnumNumber`从`0`开始，并且`0`对应的case为默认值
- 当设置`option allow_alias = true;`时，多个case可以有同一个`EnumNumber`
- `enum`使用`int32`编码，因此一个`enum`结构中case的数量不能超过`int32`所能表示的范围，
  此外有些语言也限制了一个`enum`结构所能包含的case数量

在反序列化过程中，未定义的case在不同的语言会有不同的表示
- open enum type语言(如C++, Go)中会被直接储存为以该值为底层表示的`enum`对象，
- closed enum type语言(如Java)中会有一个特殊的`unrecognized` case来表示未定义的值

`enum`类型的`reserved`语法为

```proto
reserved EnumNumber, RangeBegin to RangeEnd, RangeBegin to max;
reserved CaseName;
```


### `oneof`类型

- 如果重复设置某个`oneof`类型的值，只会保留最后一次设置的值
- 反序列化时如果某个`oneof`有多个类型的值，则只取最后一个
- `oneof`本身不能是`repeated`
- 即使一个`oneof`的值是默认值，其也会被序列化
- 更新一个`oneof`结构时会遇到很多兼容性的问题，如果一定要更新确保仔细阅读文档避免出现问题

### `map`类型

- `key_type`只能是整数类型(不包括`enum`和`bool`类型, 即使他们是兼容的)或者`string`类型
- `value_type`不能是`map`类型
- `map`类型的field不能是`repeated`类型
- `map`类型在序列化到wire format时其键值对的顺序取决于具体语言的实现；序列化到text format时会按照`key`进行排序
- 从wire format反序列化时重复出现的键值对只会保留最后一个，从text format反序列化时重复的key会报错

## 更新定义

- 不要修改已有field的field number
- 删除某个field时需确保field number不会被复用，可以通过`reserved`语句或者添加`OBSOLETE_`前缀来实现
- 未知的field会被跳过或储存在名为`unknown`的field中

## 类型兼容性

类型之间兼容意味着可以把某个field的类型从一个类型更改为另一个类型而不破坏代码

- 这些集合内部是相互兼容的:
  - `varint = {int32, uint32, int64, uint64}`
  - `{varint, bool}` `{varint, enum}`
  - `{sint32, sint64}` `{fixed32, sfixed32}` `{fixed64, sfixed64}`
- 只要`string`和`bytes`都是合法的UTF-8字符串，那么他们也是兼容的
- 如果一个`bytes`是某个`message`的序列化表示，那么其与这个`message`也是兼容的
- `string`、`bytes`和`message`的`singular`类型与其对应的`repeated`类型是兼容的
  - primitive类型会取该`repeated`中的最后一个元素
  - `message`类型会将所有元素合并
- 由于`repeated`标量数字类型使用[packed]({{< ref "posts/tool/protobuf/encoding#packed-encoding" >}})序列化格式，无法从`repeated`类型中解析出正确的`singular`值
- `optional`和`oneof`是二进制兼容的，但是在语言层面可能不兼容

## Service Type

`service`类型用于定义RPC接口，

```proto
service <ServiceName> {
  rpc <RPCName>(<parameter type>) returns (<return type>);
}
```

`service`类型定义了一个RPC服务和其支持的RPC接口，需要对应的编译器来生成对应的RPC代码，参考[gRPC](https://grpc.io/docs/)



