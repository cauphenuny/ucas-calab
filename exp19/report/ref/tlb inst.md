# 龙芯架构32位精简版参考手册

## 4.2.3 TLB维护指令
### 4.2.3.1 TLBSRCH
指令格式:tlbsrch
使用CSR.ASID和CSR.TLBEHI的信息去查询TLB。如果有命中项，那么将命中项的索引值写入到CSR.TLBIDX的Index域，同时将CSR.TLBIDX的NE位置为0；如果没有命中项，那么将CSR.TLBIDX的NE位置为1。
TLB中各项的索引值计算规则是，从0开始依次递增编号，从第0行至最后一行。

### 4.2.3.2 TLBRD
指令格式:tlbrd
将CSR.TLBIDX的Index域的值作为索引值去读取TLB中的指定项。如果指定位置处是一个有效TLB项，那么将该TLB项的页表信息写入到CSR.TLBEHI、CSR.TLBELO0、CSR.TLBELO1和CSR.TLBIDX.PS中，且将CSR.TLBIDX的NE位置为0；如果指定位置处是一个无效TLB项，需将CSR.TLBIDX的NE位置为1，且将CSR.ASID.ASID、CSR.TLBEHI、CSR.TLBELO0、CSR.TLBELO1 和 CSR.TLBIDX.PS全置为0。
需要注意的是，有效/无效TLB项和TLB中的页表项有效/无效是两个概念。
如果访问所用的index值超过了TLB的范围，则处理器的行为不确定。

### 4.2.3.3 TLBWR
指令格式:tlbwr
TLBWR指令将TLB相关CSR中所存放的页表项信息写入到TLB的指定项。被填入的页表项信息来自于CSR.TLBEHI、CSR.TLBELO0、CSR.TLBELO1 和 CSR.TLBIDX.PS。若此时CSR.ESTAT.Ecode=0x3F，即处于TLB重填例外处理过程中，那么TLB中总是填入一个有效项(即TLB项的E位为1)。否则的话，就需要看CSR.TLBIDX.NE位的值。此时如果CSR.TLBIDX.NE=1，那么TLB中会被填入一个无效TLB项；仅当CSR.TLBIDX.NE=0时，TLB中才会被填入一个有效TLB项。
执行TLBWR时，页表项写入TLB的位置是由CSR.TLBIDX的Index域的值指定的。具体的对应规则请参看TLBSRCH指令中关于TLB中各项索引值的计算规则。

### 4.2.3.4 TLBFILL
指令格式:tlbfill
TLBFILL指令将TLB相关CSR中所存放的页表项信息填入到TLB中。被填入的页表项信息来自于CSR.TLBEHI、CSR.TLBELO0、CSR.TLBELO1和CSR.TLBIDX.PS。若此时CSR.ESTAT.Ecode=0x3F，即处于TLB重填例外处理过程中，那么TLB中总是填入一个有效项(即TLB项的E位为1)。否则的话，就需要看CSR.TLBIDX.NE位的值。此时如果CSR.TLBIDX.NE=1，那么TLB中会被填入一个无效TLB项；仅当CSR.TLBIDX.NE=0时，TLB中才会被填入一个有效TLB项。
执行TLBFILL时，页表项被填入到TLB的哪一项，是由硬件随机选择的。

### 4.2.3.5 INVTLB
指令格式:invtlb op, rj, rk
INVTLB指令用于无效TLB中的内容，以维持TLB与内存之间页表数据的一致性。
指令的三个源操作数中，op是5比特立即数，用于指示操作类型。
通用寄存器rj的[9:0]位存放无效操作需的ASID信息(称为"寄存器指定ASID")，其余比特必须填0。当op所指示的操作不需要ASID时，应将通用寄存器rj设置为r0。
通用寄存器rk中用于存放无效操作所需的虚拟地址信息(称为"寄存器指定VA")。当op所指示的操作不需要虚拟地址信息时，应将通用寄存器rk设置为r0。
各op对应的操作如下表所示，未在表中出现的op将触发保留指令例外。

|        | 操作描述                                                                 |
| ------ | ------------------------------------------------------------------------ |
|        | 清除所有页表项。此时操作效果与 op=0 完全一致。                           |
| 0x2    | 清除所有 G=1 的页表项。                                                 |
| 0x4    | 清除所有 G=0，且 ASID 等于寄存器指定 ASID 的页表项。                     |
| 0x5    | 清除 G=0，且 ASID 等于寄存器指定 ASID，且 VA 等于寄存器指定 VA的页表项。 |
| 0x6    | 清除所有 G=1 或 ASID 等于寄存器指定 ASID，且 VA 等于寄存器指定 VA的页表项。 |
