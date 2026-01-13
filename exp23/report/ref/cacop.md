### 4.2.2.1 CACOP

**指令格式：**

```
cacop   code, rj, si12
```

CACOP 指令主要用于 Cache 的初始化以及 Cache 一致性维护。
通用寄存器 rj 的值加上符号扩展后的 12 位立即数 si12，将得到 CACOP 指令所用的虚拟地址 VA，其将用于指示被操作 Cache 行的位置。

CACOP 指令访问哪个 Cache 以及进行何种 Cache 操作由指令中 5 比特的 `code` 决定。
`code[2:0]` 指示操作的 Cache 对象，`code[4:3]` 指示操作类型。

* `code[2:0] = 0` 表示操作一级私有指令 Cache

* `code[2:0] = 1` 表示操作一级私有数据 Cache

* `code[2:0] = 2` 表示操作二级共享混合 Cache

* `code[4:3] = 0` 表示用于 Cache 初始化（Store Tag），将指定 Cache 行的 tag 置为全 0。
  假设访问的 Cache 有 `(1<<Way)` 路，每一路有 `(1<<Index)` 个 Cache 行，每个 Cache 行大小为 `(1<<Offset)` 个字节，那么采用地址直接索引方式意味着，操作该 Cache 的第 `VA[Way-1:0]` 路的第 `VA[Index+Offset-1:Offset]` 个 Cache 行。

* `code[4:3] = 1` 表示采用地址直接索引方式维护 Cache 一致性（Index Invalidate / Invalidate and Writeback）。
  地址直接索引方式的定义见上一段的描述。维护一致性的操作是对指定的 Cache 进行无效并写回的操作。
  如果被操作的是指令 Cache，那么仅需要进行无效操作，并不需要将 Cache 行中的数据写回。写回的数据进入到哪一级存储中由具体实现的 Cache 层次及各级间的包含或互斥关系决定。
  对于数据 Cache 或混合 Cache，由具体实现决定是否仅在 Cache 行数据为脏时才将其写回。

* `code[4:3] = 2` 表示采用查询索引方式维护 Cache 一致性（Hit Invalidate / Invalidate and Writeback）。
  这里维护 Cache 一致性的操作与上面一段所述一致。所谓查询索引方式，是将 CACOP 指令的 VA 视作一个普通 load 指令去访问待操作的 Cache，如果命中则对命中的 Cache 行进行操作，否则不做任何操作。
  由于这个查询过程可能涉及虚实地址转换，所以这种情况下 CACOP 指令可能触发 TLB 相关的例外。不过，由于 CACOP 指令操作的对象是 Cache 行，所以这种情况下并不需要考虑地址对齐与否。

* `code[4:3] = 3` 属于实现自定义的 Cache 操作，架构规范中不予明确的功能定义。
