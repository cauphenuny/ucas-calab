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


module csr(
    input  wire clk,
    input  wire rst,

    // software (instruction) interface
    input  wire [13:0]  csr_rnum,
    input  wire [13:0]  csr_wnum,
    output wire [31:0]  csr_rvalue,

    input  wire         csr_we,
    input  wire [31:0]  csr_wmask,
    input  wire [31:0]  csr_wvalue,

    // hardware interface
    input  wire         wb_ex,
    input  wire [31:0]  wb_pc,
    input  wire [ 5:0]  wb_ecode,
    input  wire [ 8:0]  wb_esubcode,
    input  wire         ertn_flush,
    output wire [12:0]  intr_stat,
    output wire [31:0]  ex_entry,
    output wire [31:0]  ex_ra
);

    reg [31:0]  csr_crmd;
    reg [31:0]  csr_prmd;
    reg [31:0]  csr_estat;
    reg [31:0]  csr_era;
    reg [31:0]  csr_eentry;
    reg [31:0]  csr_save_i [0:3];
    reg [31:0]  csr_ecfg;
    reg [31:0]  csr_badv;
    reg [31:0]  csr_tid;
    reg [31:0]  csr_tcfg;
    wire [31:0] csr_tval;
    wire [31:0] csr_ticlr;

    // In principle, these signal should from externel inputs, while in lab,
    // we simulate it by setting fixed value.
    wire [ 7:0] externel_hw_int  = 8'b0;
    wire        externel_ipi_int = 1'b0;
    wire [31:0] externel_coreid = 32'h0;

    // CRMD fields
    wire        crmd_rsel   = csr_rnum == `CSR_CRMD;
    wire        crmd_wsel   = csr_wnum == `CSR_CRMD;
    wire [31:0] crmd_wmask  = crmd_wsel ? csr_wmask : 32'b0;
    wire [31:0] crmd_wdata  = crmd_wmask & csr_wvalue | ~crmd_wmask & csr_crmd;

    always @(posedge clk) begin
        // unused fields
        csr_crmd[`CSR_CRMD_DA]   <= 1'b1;
        csr_crmd[`CSR_CRMD_PG]   <= 1'b0;
        csr_crmd[`CSR_CRMD_DATF] <= 2'b0;
        csr_crmd[`CSR_CRMD_DATM] <= 2'b0;
        csr_crmd[`CSR_CRMD_WE]   <= 1'b0;
        csr_crmd[`CSR_CRMD_ZERO] <= 22'b0;

        // CRMD.PLV, CRMD.IE
        if (rst) begin
            csr_crmd[`CSR_CRMD_PLV] <= 2'b0;
            csr_crmd[`CSR_CRMD_IE]  <= 1'b0;
        end
        else if (wb_ex) begin
            csr_crmd[`CSR_CRMD_PLV] <= 2'b0;
            csr_crmd[`CSR_CRMD_IE]  <= 1'b0;
        end
        else if (ertn_flush) begin
            csr_crmd[`CSR_CRMD_PLV] <= csr_prmd[`CSR_PRMD_PPLV];
            csr_crmd[`CSR_CRMD_IE]  <= csr_prmd[`CSR_PRMD_PIE];
        end
        else if (csr_we && crmd_wsel) begin
            csr_crmd[`CSR_CRMD_PLV] <= crmd_wdata[`CSR_CRMD_PLV];
            csr_crmd[`CSR_CRMD_IE]  <= crmd_wdata[`CSR_CRMD_IE];
        end
    end

    // PRMD fields
    wire        prmd_rsel   = csr_rnum == `CSR_PRMD;
    wire        prmd_wsel   = csr_wnum == `CSR_PRMD;
    wire [31:0] prmd_wmask  = prmd_wsel ? csr_wmask : 32'b0;
    wire [31:0] prmd_wdata  = prmd_wmask & csr_wvalue | ~prmd_wmask & csr_prmd;

    always @(posedge clk) begin
        // unused fields
        csr_prmd[`CSR_PRMD_PWE]  <= 1'b0;
        csr_prmd[`CSR_PRMD_ZERO] <= 28'b0;

        // PRMD.PPLV, PRMD.PIE
        if (wb_ex) begin
            csr_prmd[`CSR_PRMD_PPLV] <= csr_crmd[`CSR_CRMD_PLV];
            csr_prmd[`CSR_PRMD_PIE]  <= csr_crmd[`CSR_CRMD_IE];
        end
        else if (csr_we && prmd_wsel) begin
            csr_prmd[`CSR_PRMD_PPLV] <= prmd_wdata[`CSR_PRMD_PPLV];
            csr_prmd[`CSR_PRMD_PIE]  <= prmd_wdata[`CSR_PRMD_PIE];
        end
    end

    // ERA fields
    wire        era_rsel  = csr_rnum == `CSR_ERA;
    wire        era_wsel  = csr_wnum == `CSR_ERA;
    wire [31:0] era_wmask = era_wsel ? csr_wmask : 32'b0;
    wire [31:0] era_wdata = era_wmask & csr_wvalue | ~era_wmask & csr_era;

    always @(posedge clk) begin
        // ERA.PC
        if (wb_ex)
            csr_era[`CSR_ERA_PC] <= wb_pc;
        else if (csr_we && era_wsel)
            csr_era[`CSR_ERA_PC] <= era_wdata[`CSR_ERA_PC];
    end

    assign ex_ra = csr_era;

    // EENTRY fields
    wire        eentry_rsel  = csr_rnum == `CSR_EENTRY;
    wire        eentry_wsel  = csr_wnum == `CSR_EENTRY;
    wire [31:0] eentry_wmask = eentry_wsel ? csr_wmask : 32'b0;
    wire [31:0] eentry_wdata = eentry_wmask & csr_wvalue | ~eentry_wmask & csr_eentry;

    always @(posedge clk) begin
        // unused fields
        csr_eentry[`CSR_EENTRY_ZERO] <= 12'b0;

        // EENTRY.VA
        if (csr_we && eentry_wsel)
            csr_eentry[`CSR_EENTRY_VA] <= eentry_wdata[`CSR_EENTRY_VA];
    end

    assign ex_entry = csr_eentry;

    // SAVE fields
    wire        save_rsel_i   [0:3];
    wire        save_wsel_i   [0:3];
    wire [31:0] save_wmask_i  [0:3];
    wire [31:0] save_wdata_i  [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_save_sel
            assign save_rsel_i[i]   = csr_rnum == `CSR_SAVE(i);
            assign save_wsel_i[i]   = csr_wnum == `CSR_SAVE(i);
            assign save_wmask_i[i]  = save_wsel_i[i] ? csr_wmask : 32'b0;
            assign save_wdata_i[i]  = save_wmask_i[i] & csr_wvalue | ~save_wmask_i[i] & csr_save_i[i];

            always @(posedge clk) begin
                if (csr_we && save_wsel_i[i])
                    csr_save_i[i][`CSR_SAVE_DATA] <= save_wdata_i[i][`CSR_SAVE_DATA];
            end
        end
    endgenerate

    wire        save_rsel = save_rsel_i[0] | save_rsel_i[1] | save_rsel_i[2] | save_rsel_i[3];
    wire [31:0] csr_save = {32{save_rsel_i[0]}} & csr_save_i[0]
                         | {32{save_rsel_i[1]}} & csr_save_i[1]
                         | {32{save_rsel_i[2]}} & csr_save_i[2]
                         | {32{save_rsel_i[3]}} & csr_save_i[3];

    // ECFG fields

    wire       ecfg_rsel  = csr_rnum == `CSR_ECFG;
    wire       ecfg_wsel  = csr_wnum == `CSR_ECFG;
    wire [31:0] ecfg_wmask = ecfg_wsel ? csr_wmask : 32'b0;
    wire [31:0] ecfg_wdata = ecfg_wmask & csr_wvalue | ~ecfg_wmask & csr_ecfg;

    always @(posedge clk) begin
        // unused fields
        csr_ecfg[`CSR_ECFG_ZERO0] <= 3'b0;
        csr_ecfg[`CSR_ECFG_ZERO1] <= 13'b0;

        // according to loongarch docs, ECFG.LIE and ECFG.VS should be reset to 0
        if (rst) begin
            csr_ecfg[`CSR_ECFG_LIE] <= 13'b0;
            csr_ecfg[`CSR_ECFG_VS] <= 3'b0;
        end else if (csr_we && ecfg_wsel) begin
            csr_ecfg[`CSR_ECFG_LIE] <= ecfg_wdata[`CSR_ECFG_LIE];
            csr_ecfg[`CSR_ECFG_VS] <= ecfg_wdata[`CSR_ECFG_VS];
        end
    end

    // BADV fields

    wire       badv_rsel  = csr_rnum == `CSR_BADV;
    wire       badv_wsel  = csr_wnum == `CSR_BADV;
    wire [31:0] badv_wmask = badv_wsel ? csr_wmask : 32'b0;
    wire [31:0] badv_wdata = badv_wmask & csr_wvalue | ~badv_wmask & csr_badv;

    always @(posedge clk) begin
        if (csr_we && badv_wsel)
            csr_badv <= badv_wdata;
    end

    // TID fields
    wire       tid_rsel  = csr_rnum == `CSR_TID;
    wire       tid_wsel  = csr_wnum == `CSR_TID;
    wire [31:0] tid_wmask = tid_wsel ? csr_wmask : 32'b0;
    wire [31:0] tid_wdata = tid_wmask & csr_wvalue | ~tid_wmask & csr_tid;
    always @(posedge clk) begin
        if (rst)
            csr_tid <= externel_coreid;
        else if (csr_we && tid_wsel)
            csr_tid <= tid_wdata;
    end

    // TCFG fields
    wire       tcfg_rsel  = csr_rnum == `CSR_TCFG;
    wire       tcfg_wsel  = csr_wnum == `CSR_TCFG;
    wire [31:0] tcfg_wmask = tcfg_wsel ? csr_wmask : 32'b0;
    wire [31:0] tcfg_wdata = tcfg_wmask & csr_wvalue | ~tcfg_wmask & csr_tcfg;
    always @(posedge clk) begin
        if (rst)
            csr_tcfg[`CSR_TCFG_EN] <= 1'b0;
        else if (csr_we && tcfg_wsel)
            csr_tcfg[`CSR_TCFG_EN] <= tcfg_wdata[`CSR_TCFG_EN];

        if (csr_we && tcfg_wsel) begin
            csr_tcfg[`CSR_TCFG_PERIOD] <= tcfg_wdata[`CSR_TCFG_PERIOD];
            csr_tcfg[`CSR_TCFG_INIT] <= tcfg_wdata[`CSR_TCFG_INIT];
        end
    end

    // TVAL fields
    wire       tval_rsel  = csr_rnum == `CSR_TVAL;
    reg [31:0] timer_cnt;

    always @(posedge clk) begin
        if (rst)
            timer_cnt <= 32'hffffffff;
        else if (csr_we && tcfg_wsel && tcfg_wdata[`CSR_TCFG_EN]) // reset cnt when enabling timer
            timer_cnt <= {tcfg_wdata[`CSR_TCFG_INIT], 2'b0};
        else if (csr_tcfg[`CSR_TCFG_EN] && timer_cnt != 32'hffffffff) begin
            if (timer_cnt == 32'h0 && csr_tcfg[`CSR_TCFG_PERIOD])
                timer_cnt <= {csr_tcfg[`CSR_TCFG_INIT], 2'b0};
            else
                timer_cnt <= timer_cnt - 1'b1;
        end
        // NOTE: when not periodic, stall at 32'hffffffff, only equals to 32'h0
        // at a specific cycle, thus producing a sparkel signal, would not interfere with ticlr inst.
        // (check the priority of ESTAT.TI, if cnt is zero, the TI would never
        // be cleared)
    end

    assign csr_tval = timer_cnt;

    // TICLR fields
    wire       ticlr_rsel  = csr_rnum == `CSR_TICLR;
    wire       ticlr_wsel  = csr_wnum == `CSR_TICLR;
    wire [31:0] ticlr_wmask = ticlr_wsel ? csr_wmask : 32'b0;
    wire [31:0] ticlr_wdata = ticlr_wmask & csr_wvalue | ~ticlr_wmask & csr_ticlr;

    assign csr_ticlr = 32'h0; // NOTE: csr.ticlr is not readable

    // ESTAT fields
    wire        estat_rsel  = csr_rnum == `CSR_ESTAT;
    wire        estat_wsel  = csr_wnum == `CSR_ESTAT;
    wire [31:0] estat_wmask = estat_wsel ? csr_wmask : 32'b0;
    wire [31:0] estat_wdata = estat_wmask & csr_wvalue | ~estat_wmask & csr_estat;

    always @(posedge clk) begin
        // unused fields
        csr_estat[`CSR_ESTAT_ZERO1] <= 3'b0;
        csr_estat[`CSR_ESTAT_ZERO2] <= 1'b0;

        // ESTAT.IS
        if (rst)
            csr_estat[`CSR_ESTAT_IS_SWI] <= 2'b0;
        else if (csr_we && estat_wsel)
            csr_estat[`CSR_ESTAT_IS_SWI] <= estat_wdata[`CSR_ESTAT_IS_SWI];

        csr_estat[`CSR_ESTAT_IS_HWI] <= externel_hw_int;
        csr_estat[`CSR_ESTAT_IS_PMI] <= 1'b0;

        if (rst)
            csr_estat[`CSR_ESTAT_IS_TI] <= 1'b0;
        else if (csr_tcfg[`CSR_TCFG_EN] && timer_cnt == 32'h0)
            csr_estat[`CSR_ESTAT_IS_TI] <= 1'b1;
        else if (csr_we && ticlr_wsel && ticlr_wdata[`CSR_TICLR_CLR])
            csr_estat[`CSR_ESTAT_IS_TI] <= 1'b0;

        csr_estat[`CSR_ESTAT_IS_IPI] <= externel_ipi_int;

        // ESTAT.Ecode
        if (wb_ex) begin
            csr_estat[`CSR_ESTAT_ECODE]     <= wb_ecode;
            csr_estat[`CSR_ESTAT_ESUBCODE]  <= wb_esubcode;
        end
    end

    // CSR read
    assign csr_rvalue = {32{crmd_rsel}}   & csr_crmd
                      | {32{prmd_rsel}}   & csr_prmd
                      | {32{estat_rsel}}  & csr_estat
                      | {32{era_rsel}}    & csr_era
                      | {32{eentry_rsel}} & csr_eentry
                      | {32{save_rsel}}   & csr_save
                      | {32{ecfg_rsel}}   & csr_ecfg
                      | {32{badv_rsel}}   & csr_badv
                      | {32{tid_rsel}}    & csr_tid
                      | {32{tcfg_rsel}}   & csr_tcfg
                      | {32{tval_rsel}}   & csr_tval
                      | {32{ticlr_rsel}}  & csr_ticlr
                      ;

    assign intr_stat = {13{csr_crmd[`CSR_CRMD_IE]}}
                     & csr_ecfg[`CSR_ECFG_LIE] & csr_estat[`CSR_ESTAT_IS];

endmodule
