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

// MMU related CSRs
`define CSR_TLBIDX      14'h010 // TLB Index
`define CSR_TLBEHI      14'h011 // TLB Entry High
`define CSR_TLBELO0     14'h012 // TLB Entry Low 0
`define CSR_TLBELO1     14'h013 // TLB Entry Low 1
`define CSR_ASID        14'h018 // Address Space ID
`define CSR_TLBRENTRY   14'h088 // TLB Refill Exception Entry
`define CSR_DMW0        14'h180 // Direct Mapping Window 0
`define CSR_DMW1        14'h181 // Direct Mapping Window 1
`define CSR_DMW2        14'h182 // Direct Mapping Window 2
`define CSR_DMW3        14'h183 // Direct Mapping Window 3

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

// TLBIDX fields
`define CSR_TLBIDX_INDEX    3:0   // assuming 16 TLB entries, so 4 bits
`define CSR_TLBIDX_ZERO1    15:4
`define CSR_TLBIDX_ZERO2    23:16
`define CSR_TLBIDX_PS       29:24
`define CSR_TLBIDX_ZERO3    30
`define CSR_TLBIDX_NE       31

// TLBEHI fields
`define CSR_TLBEHI_ZERO     12:0
`define CSR_TLBEHI_VPPN     31:13

// TLBELO0/1 fields
`define CSR_TLBELO_V        0
`define CSR_TLBELO_D        1
`define CSR_TLBELO_PLV      3:2
`define CSR_TLBELO_MAT      5:4
`define CSR_TLBELO_G        6
`define CSR_TLBELO_ZERO1    7
`define CSR_TLBELO_PPN      27:8   // PALEN=32, so PPN is [27:8]
`define CSR_TLBELO_ZERO2    31:28

// ASID fields
`define CSR_ASID_ASID       9:0
`define CSR_ASID_ZERO1      15:10
`define CSR_ASID_ASIDBITS   23:16
`define CSR_ASID_ZERO2      31:24

// TLBRENTRY fields
`define CSR_TLBRENTRY_ZERO  5:0
`define CSR_TLBRENTRY_PA    31:6

// DMW0/1 fields
`define CSR_DMW_PLV0        0
`define CSR_DMW_ZERO1       2:1
`define CSR_DMW_PLV3        3
`define CSR_DMW_MAT         5:4
`define CSR_DMW_ZERO2       24:6
`define CSR_DMW_PSEG        27:25
`define CSR_DMW_ZERO3       28
`define CSR_DMW_VSEG        31:29

`define ECODE_SYS  6'hb
`define ECODE_BRK  6'hc
`define ECODE_ADEF 6'h8
`define ECODE_ALE  6'h9
`define ECODE_INE  6'hd
`define ECODE_INTR 6'h0
`define ECODE_PIL  6'h1  // Page Invalid Exception (Load)
`define ECODE_PIS  6'h2  // Page Invalid Exception (Store)
`define ECODE_PIF  6'h3  // Page Invalid Exception (Fetch)
`define ECODE_PME  6'h4  // Page Modify Exception
`define ECODE_PPI  6'h7  // Page Privilege level Illegal
`define ECODE_TLBR 6'h3f // TLB Refill

`define ESUBCODE_ADEF 9'h0



