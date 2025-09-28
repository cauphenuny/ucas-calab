`ifndef BUS_H
`define BUS_H

// `define DEF_RANGE(name, low, width) \
//     `define name`_WIDTH width \
//     `define name`_SUM (`name`_WIDTH + low) \
//     `define name (`name`_SUM-1):(`name`_SUM-`name`_WIDTH)
// 
// `DEF_RANGE(PC, 0, 32)
// `DEF_RANGE(ALU_SRC1, PC_SUM, 32)
// `DEF_RANGE(ALU_SRC2, ALU_SRC1_SUM, 32)

// `define CURRENT_OFFSET 0
// 
// `define DEF_RANGE_AUTO(name, width) \
//     `define name`_WIDTH width \
//     `define name`_START `CURRENT_OFFSET \
//     `define name`_END (`CURRENT_OFFSET + width - 1) \
//     `define name (`name`_END):(`name`_START) \
//     `undef CURRENT_OFFSET \
//     `define CURRENT_OFFSET (`CURRENT_OFFSET + width)
// 
// `DEF_RANGE_AUTO(CURRENT_PC, 32)
// `DEF_RANGE_AUTO(ALU_SRC1, 32)
// `DEF_RANGE_AUTO(ALU_SRC2, 32)

`define CURRENT_PC 31:0
`define IF_WIDTH 32 // pc[32]

`define INST 63:32
`define ID_WIDTH 64 // pc[32] inst[32]

`define RF_WADDR `ID_WIDTH+5-1:`ID_WIDTH
`define RF_WEN `ID_WIDTH+5
`define RF_SEL_ALU `ID_WIDTH+5+1
`define WB_WIDTH `ID_WIDTH+5+1+1 // pc[32] wdata[32] waddr[5] wen[1] sel_alu[1]

`define WB_FILEDS `WB_WIDTH-1:0 // fields that restored untill wb stage

`define MEM_ADDR `WB_WIDTH+32-1:`WB_WIDTH
`define MEM_LOAD `WB_WIDTH+32
`define MEM_STORE `WB_WIDTH+32+1
`define MEM_ATTR `WB_WIDTH+32+2+4:`WB_WIDTH+32+2 // 5 bits stored for memory inst attributes.
`define WRITE_DATA `WB_WIDTH+32+2+5+32-1:`WB_WIDTH+32+2+5 // store data for store inst


`endif
