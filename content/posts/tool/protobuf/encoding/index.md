---
title: "Protocol Buffers系列：编码方式(二)"
subtitle: ""
date: 2023-01-05T20:34:16+08:00
lastmod: 2023-01-05T21:14:14+08:00
draft: false
description: ""
tags:

categories:

series:
  - protobuf

hiddenFromHomePage: false
hiddenFromSearch: false
featuredImage: "wire format.png"
featuredImagePreview: "wire format.png"
avatarURL : "favicon.svg"
toc:
  enable: true
math:
  enable: true
lightgallery: false
license: "CC BY-NC-ND"
---
<!-- Summary -->

**Protocol Buffers(protobuf)**有两种序列化编码方式：**二进制格式(wire format)** 和 **文本格式(text format)**

其中wire format是protobuf的默认编码格式，可以高效地通过网络传输；
text format是一种类似[JSON](https://www.json.org/json-en.html)的表示方式，可以方便地用于调试和手动编写/编辑消息。

这篇文章记录一下wire format的编码格式

<!--more-->

---

**这篇Blog是protobuf系列的第二篇，整个系列目录如下**

- [Protocol Buffers系列：格式介绍(一)]({{< ref "posts/tool/protobuf/format" >}})
- Protocol Buffers系列：编码方式(二)

---

<!-- Main Content -->

## Base128 Varints

**变长整数**`varint`允许在不同范围内的整数编码结果具有不同的字节长度，
且整数越小字节长度越短(仅对非负数而言)

在`varint`二进制表示中，每个字节都有一个*continuation bit*(**CB**)用于指示后续是否还有连续的字节，
以及一个7-bit的payload。由于7-bit能表示的范围是$[0,127]$，所以这种编码方式也叫做**Base128**编码

对于一个64位的整数，要完整表示其64个bit则最少需要10个这样的字节，
因此`varint`类型的整数最多需要10个字节来表示，但最少只需要1个字节就可以表示，
因此在编码范围不定的非负整数时`varint`类型具有非常高的空间效率。

把这些连续字节的所有payload按little-endian的顺序组合到一起得到的结果就是该整数的二进制表示

比如，整数`1`只需要1bit就能表示，因此只需要一个字节，且其`CB`为`0`

```plain
0 0000001
^ CB
```

`0000001`即为最后的结果`1`的二进制表示

整数`150`最少需要8个bit表示，由于一个字节的payload只有7个bit，
所以需要两个字节来表示，并且第一个字节的`CB`为`1`，第二个字节的`CB`为`0`

```plain
1 0010110  0 0000001
^ CB       ^ CB
```

将这两个字节的payload按照little-endian顺序组合到一起得到的`00000010010110`
就是最后的结果`150`的二进制表示，具体操作如下

```plain
10010110 00000001        // Original bits.
 0010110  0000001        // Drop continuation bits.
 0000001  0010110        // Put into little-endian order.
 10010110                // Concatenate.
 128 + 16 + 4 + 2 = 150  // Interpret as integer.
```

### 负数编码

`intN`类型使用补码的方式编码负数，因此任何负数都需要使用全部的10个字节来表示，空间效率很低

`sintN`类型使用`ZigZag`方式编码负数，把`LSB`作为*signed bit*，
即正数`n`编码为`2 * n`，负数`-n`编码为`2 * n + 1`，这样虽然正数需要额外的1bit来表示，
但是解码一个负数并不需要知道该类型所能表示的最大范围，
这样不是所有的负数都需要用到全部的10个字节，相比补码方式能节省更多的空间

### 其他数字类型

Field type为`bool`和`enum`的value都按照`int32`类型来编码，
并且`bool`类型的值总是`0`或`1`，其protoscope别名为`false`和`true`

## Protoscope

为了增加二进制编码的可读性，protobuf使用一种叫做**Protoscope**的描述语言来描述wire
format的二进制表示。其包括以下语法：

### Value

- `` `70726f746f6275660a` ``: 表示该十六进制字符串对应的字节序列
- `150`: 表示一个`varint`类型的数字`150`，其等效于该`varint`的底层二进制表示`` `9601` ``
- `"Hello, Protobuf!"`: 表示一个UTF-8字符串

### Field

Wire format编码的field使用[Type-Length-Value(TLV)](https://en.wikipedia.org/wiki/Type%E2%80%93length%E2%80%93value)结构，用protoscope表示就是

```protoscope
<field number>:<wire type> <value>
```

wire type用于指示value的长度，不同的field类型会使用不同的wire type，其共有六种：

- `[0]VARINT`: `int32`, `int64`, `uint32`, `uint64`, `sint32`, `sint64`, `bool`, `enum`
- `[1]I64`: `fixed64`, `sfixed64`, `double`
- `[2]LEN`: `string`, `bytes`, embedded messages, packed repeated fields
- `[3]SGROUP`: ~~group start~~(*deprecated*)
- `[4]EGROUP`: ~~group end~~(*deprecated*)
- `[5]I32`: `fixed32`, `sfixed32`, `float`

比如`1:VARINT 150`表示wire type为`VARINT`，field number为`1`的field，且其值为`150`

此外，当wire type为`LEN`时，后面还会跟一个`varint`用于表示value的长度

比如`2:LEN 16 {"Hello, Protobuf!"}`，其表示一个wire type为`LEN`，field number为`2`的field,
且其字节长度为16，值为`"Hello, Protobuf!"`

### 类型推断

使用protoscope表示的field不一定要表明wire type，可以通过value的形式隐含地指示wire type，比如

- 当value是一个`varint`类型的数字`123`时，其wire type为`VARINT`
- 当value的第一个字符为`{`时，其wire type为`LEN`
- 当value显式标注了类型后缀时，比如`5i32`的wire type为`I32`、`3.1415i64`的wire type为`I64`等等

## Message

Protobuf message中的每个field都可以看作是一个key-value pair，
其中key是该field的field number，value就是该field的值。
每个field的名称和类型只在解码的时候才会决定，wire format本身不包含名称和类型信息。

在编码消息时，这样的一个key-value pair称为一个`record`，其具体表现形式就是上面提到的TLV结构。
当使用`optional`修饰的field的值为默认值时，该field不会被序列化，即编码结果中不包含该field的`record`

在一个`record`中field number和wire type会编码在同一个`varint`中，
这个`varint`称为这个`record`的`tag`，并且该`varint`的lower 3-bit就是wire type，
其余的为field number

例如下面这个`record`

```protoscope
1:VARINT 150
```

表示其field number和wire type的`varint`是`` `08` ``，拆开来看就是

```plain
0    0001           000
^    ^^^^           ^^^
CB   field number   wire type([0]VARINT)
```

这个`record`加上value的完整表示如下

```plain
|   tag   |   | value: varint 150 |
0  0001 000   1 0010110   0 0000001
^  ^^^^ ^^^   ^           ^
CB FN   WT    CB          CB
```


### Length-Delimited Records

Wire type为`LEN`的field使用一个额外的`varint`来表示其value的字节长度，
因此这种表示方式叫做**Length-Delimited**

例如，对于下面这个`record`

```protoscope
2:LEN 5 {"hello"}
```

其二进制表示如下

```plain
|   tag   |  | Len 5 |  |    string "hello"    |
0  0010 010  0000 0101  0x68 0x65 0x6c 0x6c 0x6f
^  ^^^^ ^^^  ^
CB FN   WT   CB
```

对于其他wire type为`LEN`的类型也是一样的，其`value`就是该类型的二进制表示


### Record Order

Field number与该field对应的`record`在编码结果中的位置没有关系。
此外，序列化的格式也并不是固定的，protobuf只保证被编码的对象和解码出的对象对同一个`.proto`生成的代码具有相同的值，
因此不能对编码后的`wire format`内容做任何假设

### `repeated`

类型为`repeated`的field的每一个元素都会按照`singular`方式编码为一个`record`，
此时编码结果中有多个具有相同`key`的`record`

例如，对于以下field

```proto
repeated int32 arr = 3;
```

当`arr = [1,2,3]`时，会被编码为

```protoscope
3: 1
3: 2
3: 3
```

在编码`repeated`类型的时候不需要保证其所有元素的`record`都分布在一起，
其他field的`record`可以穿插在这些元素的`record`之间。
只有具有相同`key`的`record`之间的相对顺序会被作为该`repeated`类型field元素之间的顺序

### Packed Encoding

在`proto3`中，使用`VARINT`、`I32`或`I64`作为元素wire type的`repeated`类型默认会以"packed"的形式编码，
即用一个wire type为`LEN`的`record`代替多个wire type为`VARINT`、`I32`或`I64`的`record`

例如，上面的`arr`用"packed"的方式可以编码为如下形式

```protoscope
3: {1 2 3}
```

同样，以`packed`形式编码的`field`也可以有多个相同`key`的`record`，
这些`record`的值在解码的时候会被拼接在一起

## `map`

如果一个`map`类型的field的定义如下

```proto
map<string, int32> count = 4;
```

则其与以下定义的编码方式相同

```proto
message count_Entry {
    optional string key = 1;
    optional int32 value = 2;
}
repeated count_Entry count = 4;
```

## `oneof`

`oneof`类型的field编码方式与`message`相同，但一个`oneof`只能有一个field的`record`

## `repeated` to `singluar`

当反序列化的时候某个`singular`类型的field出现了多个`record`，
即该field表现出`repeated`的性质，则按照以下方式处理

1. `scalar`类型会取最后一个`record`的值作为该field的值
2. `embeded message`会合并，即递归按照以下方式处理该`embeded message`中的每个field
   - `singular scalar`按照(1)处理
   - `singular embedded message`按照(2)处理
   - `repeated`类型会把值拼接到一起

---

## Reference Card

以下是wire format的一个速查表

```plain
message    := (tag value)*

tag        := (field << 3) bit-or wire_type;
                encoded as varint
value      := varint      for wire_type == VARINT,
              i32         for wire_type == I32,
              i64         for wire_type == I64,
              len-prefix  for wire_type == LEN,
              <empty>     for wire_type == SGROUP or EGROUP

varint     := int32 | int64 | uint32 | uint64 | bool | enum | sint32 | sint64;
                encoded as varints (sintN are ZigZag-encoded first)
i32        := sfixed32 | fixed32 | float;
                encoded as 4-byte little-endian;
                memcpy of the equivalent C types (u?int32_t, float)
i64        := sfixed64 | fixed64 | double;
                encoded as 8-byte little-endian;
                memcpy of the equivalent C types (u?int32_t, float)

len-prefix := size (message | string | bytes | packed);
                size encoded as varint
string     := valid UTF-8 string (e.g. ASCII);
                max 2GB of bytes
bytes      := any sequence of 8-bit bytes;
                max 2GB of bytes
packed     := varint* | i32* | i64*,
                consecutive values of the type specified in `.proto`
```