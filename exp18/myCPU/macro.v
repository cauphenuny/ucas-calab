// CSR addresses
`define CSR_CRMD    14'h000
`define CSR_PRMD    14'h001
`define CSR_ESTAT   14'h005
`define CSR_ERA     14'h006
`define CSR_EENTRY  14'h00c
`define CSR_SAVE(n) (14'h030 + n)
`define CSR_ECFG    14'h004 // Exception Configuration
`define CSR_BADV    14'h007 // Bad Virtual Address
`define CSR_TID     14'h040 // Timer ID
`define CSR_TCFG    14'h041 // Timer Configuration
`define CSR_TVAL    14'h042 // Timer Value
`define CSR_TICLR   14'h044 // Timer Interrupt Clear

// CSR fields
`define CSR_CRMD_PLV    1:0
`define CSR_CRMD_IE     2
`define CSR_CRMD_DA     3
`define CSR_CRMD_PG     4
`define CSR_CRMD_DATF   6:5
`define CSR_CRMD_DATM   8:7
`define CSR_CRMD_WE     9
`define CSR_CRMD_ZERO   31:10

`define CSR_PRMD_PPLV   1:0
`define CSR_PRMD_PIE    2
`define CSR_PRMD_PWE    3
`define CSR_PRMD_ZERO   31:4

`define CSR_ESTAT_IS        12:0
`define CSR_ESTAT_IS_SWI    1:0
`define CSR_ESTAT_IS_HWI    9:2
`define CSR_ESTAT_IS_PMI    10
`define CSR_ESTAT_IS_TI     11
`define CSR_ESTAT_IS_IPI    12
`define CSR_ESTAT_ZERO1     15:13
`define CSR_ESTAT_ECODE     21:16
`define CSR_ESTAT_ESUBCODE  30:22
`define CSR_ESTAT_ZERO2     31

`define CSR_ERA_PC      31:0

`define CSR_EENTRY_ZERO 11:0
`define CSR_EENTRY_VA   31:12

`define CSR_SAVE_DATA   31:0

`define CSR_ECFG_LIE 12:0
`define CSR_ECFG_LIE_SWI 1:0
`define CSR_ECFG_LIE_HWI 9:2
`define CSR_ECFG_LIE_PMI 10
`define CSR_ECFG_LIE_TI 11
`define CSR_ECFG_LIE_IPI 12
`define CSR_ECFG_ZERO0 15:13
`define CSR_ECFG_VS 18:16
`define CSR_ECFG_ZERO1 31:19

`define CSR_TCFG_EN 0
`define CSR_TCFG_PERIOD 1
`define CSR_TCFG_INIT 31:2

`define CSR_TICLR_CLR 0
`define CSR_TICLR_ZERO 31:1

`define ECODE_SYS  6'hb
`define ECODE_BRK  6'hc
`define ECODE_ADEF 6'h8
`define ECODE_ALE  6'h9
`define ECODE_INE  6'hd
`define ECODE_INTR 6'h0

`define ESUBCODE_ADEF 9'h0



