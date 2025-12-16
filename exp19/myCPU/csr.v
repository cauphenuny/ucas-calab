`timescale 10ns / 1ps

`include "macro.v"

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
    output wire [31:0]  ex_ra,

    // TLB interface
    input  wire         tlbrd_en,      // TLBRD instruction
    input  wire         tlbwr_en,      // TLBWR instruction
    input  wire         tlbfill_en,    // TLBFILL instruction
    input  wire [ 3:0]  tlbfill_rand_index, // Random index for TLBFILL
    input  wire         tlbsrch_en,    // TLBSRCH instruction
    input  wire         tlbsrch_found, // TLBSRCH result: found
    input  wire [ 3:0]  tlbsrch_index, // TLBSRCH result: index

    // TLB read port (TLBRD)
    input  wire         r_e,
    input  wire [18:0]  r_vppn,
    input  wire [ 5:0]  r_ps,
    input  wire [ 9:0]  r_asid,
    input  wire         r_g,
    input  wire [19:0]  r_ppn0,
    input  wire [ 1:0]  r_plv0,
    input  wire [ 1:0]  r_mat0,
    input  wire         r_d0,
    input  wire         r_v0,
    input  wire [19:0]  r_ppn1,
    input  wire [ 1:0]  r_plv1,
    input  wire [ 1:0]  r_mat1,
    input  wire         r_d1,
    input  wire         r_v1,

    // TLB write port outputs (for TLBWR/TLBFILL)
    output wire [ 3:0]  w_index,
    output wire         w_e,
    output wire [18:0]  w_vppn,
    output wire [ 5:0]  w_ps,
    output wire [ 9:0]  w_asid,
    output wire         w_g,
    output wire [19:0]  w_ppn0,
    output wire [ 1:0]  w_plv0,
    output wire [ 1:0]  w_mat0,
    output wire         w_d0,
    output wire         w_v0,
    output wire [19:0]  w_ppn1,
    output wire [ 1:0]  w_plv1,
    output wire [ 1:0]  w_mat1,
    output wire         w_d1,
    output wire         w_v1,

    // Exposed CSR state for MMU usage
    output wire [31:0]  crmd_value,
    output wire [31:0]  asid_value,
    output wire [31:0]  tlbehi_value,
    output wire [31:0]  tlbidx_value,
    output wire [31:0]  tlbrentry_value,
    output wire [31:0]  dmw0_value,
    output wire [31:0]  dmw1_value,
    output wire [31:0]  dmw2_value,
    output wire [31:0]  dmw3_value,

    // Exception feedback for automatic CSR updates
    input  wire         wb_mmu_ex,
    input  wire         wb_tlb_found,
    input  wire [ 3:0]  wb_tlb_index,
    input  wire [ 5:0]  wb_tlb_ps,

    // TLB read index (for TLBRD)
    output wire [ 3:0]  r_index
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

    // MMU related CSRs
    reg [31:0]  csr_tlbidx;
    reg [31:0]  csr_tlbehi;
    reg [31:0]  csr_tlbelo0;
    reg [31:0]  csr_tlbelo1;
    reg [31:0]  csr_asid;
    reg [31:0]  csr_tlbrentry;
    reg [31:0]  csr_dmw0;
    reg [31:0]  csr_dmw1;
    reg [31:0]  csr_dmw2;
    reg [31:0]  csr_dmw3;

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
        csr_crmd[`CSR_CRMD_WE]   <= 1'b0;
        csr_crmd[`CSR_CRMD_ZERO] <= 22'b0;

        // CRMD.PLV, CRMD.IE
        if (rst) begin
            csr_crmd[`CSR_CRMD_PLV] <= 2'b0;
            csr_crmd[`CSR_CRMD_IE]  <= 1'b0;
            csr_crmd[`CSR_CRMD_DA]  <= 1'b1;  // Direct translation mode on reset
            csr_crmd[`CSR_CRMD_PG]  <= 1'b0;  // Mapped mode disabled on reset
            csr_crmd[`CSR_CRMD_DATF] <= 2'b0;
            csr_crmd[`CSR_CRMD_DATM] <= 2'b0;
        end
        else if (wb_ex) begin
            csr_crmd[`CSR_CRMD_PLV] <= 2'b0;
            csr_crmd[`CSR_CRMD_IE]  <= 1'b0;
            // Handle TLB refill exception
            if (wb_ecode == `ECODE_TLBR) begin
                csr_crmd[`CSR_CRMD_DA] <= 1'b1;
                csr_crmd[`CSR_CRMD_PG] <= 1'b0;
            end
        end
        else if (ertn_flush) begin
            csr_crmd[`CSR_CRMD_PLV] <= csr_prmd[`CSR_PRMD_PPLV];
            csr_crmd[`CSR_CRMD_IE]  <= csr_prmd[`CSR_PRMD_PIE];
            // Return from TLB refill exception
            if (csr_estat[`CSR_ESTAT_ECODE] == `ECODE_TLBR) begin
                csr_crmd[`CSR_CRMD_DA] <= 1'b0;
                csr_crmd[`CSR_CRMD_PG] <= 1'b1;
            end
        end
        else if (csr_we && crmd_wsel) begin
            csr_crmd[`CSR_CRMD_PLV] <= crmd_wdata[`CSR_CRMD_PLV];
            csr_crmd[`CSR_CRMD_IE]  <= crmd_wdata[`CSR_CRMD_IE];
            csr_crmd[`CSR_CRMD_DA]  <= crmd_wdata[`CSR_CRMD_DA];
            csr_crmd[`CSR_CRMD_PG]  <= crmd_wdata[`CSR_CRMD_PG];
            csr_crmd[`CSR_CRMD_DATF] <= crmd_wdata[`CSR_CRMD_DATF];
            csr_crmd[`CSR_CRMD_DATM] <= crmd_wdata[`CSR_CRMD_DATM];
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

    wire is_tlbr_exception = wb_ex && (wb_ecode == `ECODE_TLBR);

    assign ex_entry = is_tlbr_exception ? csr_tlbrentry : csr_eentry;

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
            csr_ecfg[`CSR_ECFG_LIE_SWI] <= ecfg_wdata[`CSR_ECFG_LIE_SWI];
            csr_ecfg[`CSR_ECFG_LIE_HWI] <= ecfg_wdata[`CSR_ECFG_LIE_HWI];
            // NOTE: PMI disabled
            // csr_ecfg[`CSR_ECFG_LIE_PMI] <= ecfg_wdata[`CSR_ECFG_LIE_PMI];
            csr_ecfg[`CSR_ECFG_LIE_TI] <= ecfg_wdata[`CSR_ECFG_LIE_TI];
            csr_ecfg[`CSR_ECFG_LIE_IPI] <= ecfg_wdata[`CSR_ECFG_LIE_IPI];
            csr_ecfg[`CSR_ECFG_VS] <= ecfg_wdata[`CSR_ECFG_VS];
        end
    end

    // BADV fields

    wire       badv_rsel  = csr_rnum == `CSR_BADV;
    wire       badv_wsel  = csr_wnum == `CSR_BADV;
    wire [31:0] badv_wmask = badv_wsel ? csr_wmask : 32'b0;
    wire [31:0] badv_wdata = badv_wmask & csr_wvalue | ~badv_wmask & csr_badv;

    // BADV should be updated on address-related exceptions
    wire badv_ex = wb_ex && (
        wb_ecode == `ECODE_ADEF || wb_ecode == `ECODE_ALE ||
        wb_ecode == `ECODE_PIL  || wb_ecode == `ECODE_PIS ||
        wb_ecode == `ECODE_PIF  || wb_ecode == `ECODE_PME ||
        wb_ecode == `ECODE_PPI  || wb_ecode == `ECODE_TLBR
    );

    always @(posedge clk) begin
        if (badv_ex)
            csr_badv <= badv_wdata;  // use captured bad virtual address
        else if (csr_we && badv_wsel)
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

    // TLBIDX fields
    wire       tlbidx_rsel  = csr_rnum == `CSR_TLBIDX;
    wire       tlbidx_wsel  = csr_wnum == `CSR_TLBIDX;
    wire [31:0] tlbidx_wmask = tlbidx_wsel ? csr_wmask : 32'b0;
    wire [31:0] tlbidx_wdata = tlbidx_wmask & csr_wvalue | ~tlbidx_wmask & csr_tlbidx;

    always @(posedge clk) begin
        // Fixed fields
        csr_tlbidx[`CSR_TLBIDX_ZERO1] <= 12'b0;
        csr_tlbidx[`CSR_TLBIDX_ZERO2] <= 8'b0;
        csr_tlbidx[`CSR_TLBIDX_ZERO3] <= 1'b0;

        if (rst) begin
            csr_tlbidx[`CSR_TLBIDX_INDEX] <= 4'b0;
            csr_tlbidx[`CSR_TLBIDX_PS] <= 6'b0;
            csr_tlbidx[`CSR_TLBIDX_NE] <= 1'b1;
        end
        else if (tlbsrch_en) begin
            // TLBSRCH: update Index and NE based on search result
            csr_tlbidx[`CSR_TLBIDX_INDEX] <= tlbsrch_index;
            csr_tlbidx[`CSR_TLBIDX_NE] <= ~tlbsrch_found;
        end
        else if (tlbrd_en) begin
            // TLBRD: update PS and NE based on read result
            // If TLB entry is invalid (r_e=0), PS should be cleared to 0
            csr_tlbidx[`CSR_TLBIDX_PS] <= r_e ? r_ps : 6'b0;
            csr_tlbidx[`CSR_TLBIDX_NE] <= ~r_e;
        end
        else if (csr_we && tlbidx_wsel) begin
            csr_tlbidx[`CSR_TLBIDX_INDEX] <= tlbidx_wdata[`CSR_TLBIDX_INDEX];
            csr_tlbidx[`CSR_TLBIDX_PS] <= tlbidx_wdata[`CSR_TLBIDX_PS];
            csr_tlbidx[`CSR_TLBIDX_NE] <= tlbidx_wdata[`CSR_TLBIDX_NE];
        end
    end

    // TLBEHI fields
    wire       tlbehi_rsel  = csr_rnum == `CSR_TLBEHI;
    wire       tlbehi_wsel  = csr_wnum == `CSR_TLBEHI;
    wire [31:0] tlbehi_wmask = tlbehi_wsel ? csr_wmask : 32'b0;
    wire [31:0] tlbehi_wdata = tlbehi_wmask & csr_wvalue | ~tlbehi_wmask & csr_tlbehi;

    always @(posedge clk) begin
        csr_tlbehi[`CSR_TLBEHI_ZERO] <= 13'b0;

        if (rst) begin
            csr_tlbehi[`CSR_TLBEHI_VPPN] <= 19'b0;
        end
        else if (badv_ex) begin
            // Update VPPN on TLB/page exceptions using bad virtual address
            csr_tlbehi[`CSR_TLBEHI_VPPN] <= badv_wdata[31:13];
        end
        else if (tlbrd_en) begin
            // TLBRD: update VPPN from TLB
            csr_tlbehi[`CSR_TLBEHI_VPPN] <= r_e ? r_vppn : 19'b0;
        end
        else if (csr_we && tlbehi_wsel) begin
            csr_tlbehi[`CSR_TLBEHI_VPPN] <= tlbehi_wdata[`CSR_TLBEHI_VPPN];
        end
    end

    // TLBELO0 fields
    wire       tlbelo0_rsel  = csr_rnum == `CSR_TLBELO0;
    wire       tlbelo0_wsel  = csr_wnum == `CSR_TLBELO0;
    wire [31:0] tlbelo0_wmask = tlbelo0_wsel ? csr_wmask : 32'b0;
    wire [31:0] tlbelo0_wdata = tlbelo0_wmask & csr_wvalue | ~tlbelo0_wmask & csr_tlbelo0;

    always @(posedge clk) begin
        csr_tlbelo0[`CSR_TLBELO_ZERO1] <= 1'b0;
        csr_tlbelo0[`CSR_TLBELO_ZERO2] <= 4'b0;

        if (rst) begin
            csr_tlbelo0[`CSR_TLBELO_V] <= 1'b0;
            csr_tlbelo0[`CSR_TLBELO_D] <= 1'b0;
            csr_tlbelo0[`CSR_TLBELO_PLV] <= 2'b0;
            csr_tlbelo0[`CSR_TLBELO_MAT] <= 2'b0;
            csr_tlbelo0[`CSR_TLBELO_G] <= 1'b0;
            csr_tlbelo0[`CSR_TLBELO_PPN] <= 20'b0;
        end
        else if (tlbrd_en) begin
            // TLBRD: update from TLB
            if (r_e) begin
                csr_tlbelo0[`CSR_TLBELO_V] <= r_v0;
                csr_tlbelo0[`CSR_TLBELO_D] <= r_d0;
                csr_tlbelo0[`CSR_TLBELO_PLV] <= r_plv0;
                csr_tlbelo0[`CSR_TLBELO_MAT] <= r_mat0;
                csr_tlbelo0[`CSR_TLBELO_G] <= r_g;
                csr_tlbelo0[`CSR_TLBELO_PPN] <= r_ppn0;
            end else begin
                csr_tlbelo0[`CSR_TLBELO_V] <= 1'b0;
                csr_tlbelo0[`CSR_TLBELO_D] <= 1'b0;
                csr_tlbelo0[`CSR_TLBELO_PLV] <= 2'b0;
                csr_tlbelo0[`CSR_TLBELO_MAT] <= 2'b0;
                csr_tlbelo0[`CSR_TLBELO_G] <= 1'b0;
                csr_tlbelo0[`CSR_TLBELO_PPN] <= 20'b0;
            end
        end
        else if (csr_we && tlbelo0_wsel) begin
            csr_tlbelo0[`CSR_TLBELO_V] <= tlbelo0_wdata[`CSR_TLBELO_V];
            csr_tlbelo0[`CSR_TLBELO_D] <= tlbelo0_wdata[`CSR_TLBELO_D];
            csr_tlbelo0[`CSR_TLBELO_PLV] <= tlbelo0_wdata[`CSR_TLBELO_PLV];
            csr_tlbelo0[`CSR_TLBELO_MAT] <= tlbelo0_wdata[`CSR_TLBELO_MAT];
            csr_tlbelo0[`CSR_TLBELO_G] <= tlbelo0_wdata[`CSR_TLBELO_G];
            csr_tlbelo0[`CSR_TLBELO_PPN] <= tlbelo0_wdata[`CSR_TLBELO_PPN];
        end
    end

    // TLBELO1 fields
    wire       tlbelo1_rsel  = csr_rnum == `CSR_TLBELO1;
    wire       tlbelo1_wsel  = csr_wnum == `CSR_TLBELO1;
    wire [31:0] tlbelo1_wmask = tlbelo1_wsel ? csr_wmask : 32'b0;
    wire [31:0] tlbelo1_wdata = tlbelo1_wmask & csr_wvalue | ~tlbelo1_wmask & csr_tlbelo1;

    always @(posedge clk) begin
        csr_tlbelo1[`CSR_TLBELO_ZERO1] <= 1'b0;
        csr_tlbelo1[`CSR_TLBELO_ZERO2] <= 4'b0;

        if (rst) begin
            csr_tlbelo1[`CSR_TLBELO_V] <= 1'b0;
            csr_tlbelo1[`CSR_TLBELO_D] <= 1'b0;
            csr_tlbelo1[`CSR_TLBELO_PLV] <= 2'b0;
            csr_tlbelo1[`CSR_TLBELO_MAT] <= 2'b0;
            csr_tlbelo1[`CSR_TLBELO_G] <= 1'b0;
            csr_tlbelo1[`CSR_TLBELO_PPN] <= 20'b0;
        end
        else if (tlbrd_en) begin
            // TLBRD: update from TLB
            if (r_e) begin
                csr_tlbelo1[`CSR_TLBELO_V] <= r_v1;
                csr_tlbelo1[`CSR_TLBELO_D] <= r_d1;
                csr_tlbelo1[`CSR_TLBELO_PLV] <= r_plv1;
                csr_tlbelo1[`CSR_TLBELO_MAT] <= r_mat1;
                csr_tlbelo1[`CSR_TLBELO_G] <= r_g;
                csr_tlbelo1[`CSR_TLBELO_PPN] <= r_ppn1;
            end else begin
                csr_tlbelo1[`CSR_TLBELO_V] <= 1'b0;
                csr_tlbelo1[`CSR_TLBELO_D] <= 1'b0;
                csr_tlbelo1[`CSR_TLBELO_PLV] <= 2'b0;
                csr_tlbelo1[`CSR_TLBELO_MAT] <= 2'b0;
                csr_tlbelo1[`CSR_TLBELO_G] <= 1'b0;
                csr_tlbelo1[`CSR_TLBELO_PPN] <= 20'b0;
            end
        end
        else if (csr_we && tlbelo1_wsel) begin
            csr_tlbelo1[`CSR_TLBELO_V] <= tlbelo1_wdata[`CSR_TLBELO_V];
            csr_tlbelo1[`CSR_TLBELO_D] <= tlbelo1_wdata[`CSR_TLBELO_D];
            csr_tlbelo1[`CSR_TLBELO_PLV] <= tlbelo1_wdata[`CSR_TLBELO_PLV];
            csr_tlbelo1[`CSR_TLBELO_MAT] <= tlbelo1_wdata[`CSR_TLBELO_MAT];
            csr_tlbelo1[`CSR_TLBELO_G] <= tlbelo1_wdata[`CSR_TLBELO_G];
            csr_tlbelo1[`CSR_TLBELO_PPN] <= tlbelo1_wdata[`CSR_TLBELO_PPN];
        end
    end

    // ASID fields
    wire       asid_rsel  = csr_rnum == `CSR_ASID;
    wire       asid_wsel  = csr_wnum == `CSR_ASID;
    wire [31:0] asid_wmask = asid_wsel ? csr_wmask : 32'b0;
    wire [31:0] asid_wdata = asid_wmask & csr_wvalue | ~asid_wmask & csr_asid;

    always @(posedge clk) begin
        csr_asid[`CSR_ASID_ZERO1] <= 6'b0;
        csr_asid[`CSR_ASID_ASIDBITS] <= 8'd10;  // ASID is 10 bits
        csr_asid[`CSR_ASID_ZERO2] <= 8'b0;

        if (rst) begin
            csr_asid[`CSR_ASID_ASID] <= 10'b0;
        end
        else if (tlbrd_en) begin
            // TLBRD: update ASID from TLB
            csr_asid[`CSR_ASID_ASID] <= r_e ? r_asid : 10'b0;
        end
        else if (csr_we && asid_wsel) begin
            csr_asid[`CSR_ASID_ASID] <= asid_wdata[`CSR_ASID_ASID];
        end
    end

    // TLBRENTRY fields
    wire       tlbrentry_rsel  = csr_rnum == `CSR_TLBRENTRY;
    wire       tlbrentry_wsel  = csr_wnum == `CSR_TLBRENTRY;
    wire [31:0] tlbrentry_wmask = tlbrentry_wsel ? csr_wmask : 32'b0;
    wire [31:0] tlbrentry_wdata = tlbrentry_wmask & csr_wvalue | ~tlbrentry_wmask & csr_tlbrentry;

    always @(posedge clk) begin
        csr_tlbrentry[`CSR_TLBRENTRY_ZERO] <= 6'b0;

        if (rst) begin
            csr_tlbrentry[`CSR_TLBRENTRY_PA] <= 26'b0;
        end
        else if (csr_we && tlbrentry_wsel) begin
            csr_tlbrentry[`CSR_TLBRENTRY_PA] <= tlbrentry_wdata[`CSR_TLBRENTRY_PA];
        end
    end

    // DMW0 fields
    wire       dmw0_rsel  = csr_rnum == `CSR_DMW0;
    wire       dmw0_wsel  = csr_wnum == `CSR_DMW0;
    wire [31:0] dmw0_wmask = dmw0_wsel ? csr_wmask : 32'b0;
    wire [31:0] dmw0_wdata = dmw0_wmask & csr_wvalue | ~dmw0_wmask & csr_dmw0;

    always @(posedge clk) begin
        csr_dmw0[`CSR_DMW_ZERO1] <= 2'b0;
        csr_dmw0[`CSR_DMW_ZERO2] <= 19'b0;
        csr_dmw0[`CSR_DMW_ZERO3] <= 1'b0;

        if (rst) begin
            csr_dmw0[`CSR_DMW_PLV0] <= 1'b0;
            csr_dmw0[`CSR_DMW_PLV3] <= 1'b0;
            csr_dmw0[`CSR_DMW_MAT] <= 2'b0;
            csr_dmw0[`CSR_DMW_PSEG] <= 3'b0;
            csr_dmw0[`CSR_DMW_VSEG] <= 3'b0;
        end
        else if (csr_we && dmw0_wsel) begin
            csr_dmw0[`CSR_DMW_PLV0] <= dmw0_wdata[`CSR_DMW_PLV0];
            csr_dmw0[`CSR_DMW_PLV3] <= dmw0_wdata[`CSR_DMW_PLV3];
            csr_dmw0[`CSR_DMW_MAT] <= dmw0_wdata[`CSR_DMW_MAT];
            csr_dmw0[`CSR_DMW_PSEG] <= dmw0_wdata[`CSR_DMW_PSEG];
            csr_dmw0[`CSR_DMW_VSEG] <= dmw0_wdata[`CSR_DMW_VSEG];
        end
    end

    // DMW1 fields
    wire       dmw1_rsel  = csr_rnum == `CSR_DMW1;
    wire       dmw1_wsel  = csr_wnum == `CSR_DMW1;
    wire [31:0] dmw1_wmask = dmw1_wsel ? csr_wmask : 32'b0;
    wire [31:0] dmw1_wdata = dmw1_wmask & csr_wvalue | ~dmw1_wmask & csr_dmw1;

    always @(posedge clk) begin
        csr_dmw1[`CSR_DMW_ZERO1] <= 2'b0;
        csr_dmw1[`CSR_DMW_ZERO2] <= 19'b0;
        csr_dmw1[`CSR_DMW_ZERO3] <= 1'b0;

        if (rst) begin
            csr_dmw1[`CSR_DMW_PLV0] <= 1'b0;
            csr_dmw1[`CSR_DMW_PLV3] <= 1'b0;
            csr_dmw1[`CSR_DMW_MAT] <= 2'b0;
            csr_dmw1[`CSR_DMW_PSEG] <= 3'b0;
            csr_dmw1[`CSR_DMW_VSEG] <= 3'b0;
        end
        else if (csr_we && dmw1_wsel) begin
            csr_dmw1[`CSR_DMW_PLV0] <= dmw1_wdata[`CSR_DMW_PLV0];
            csr_dmw1[`CSR_DMW_PLV3] <= dmw1_wdata[`CSR_DMW_PLV3];
            csr_dmw1[`CSR_DMW_MAT] <= dmw1_wdata[`CSR_DMW_MAT];
            csr_dmw1[`CSR_DMW_PSEG] <= dmw1_wdata[`CSR_DMW_PSEG];
            csr_dmw1[`CSR_DMW_VSEG] <= dmw1_wdata[`CSR_DMW_VSEG];
        end
    end

    // DMW2 fields
    wire       dmw2_rsel  = csr_rnum == `CSR_DMW2;
    wire       dmw2_wsel  = csr_wnum == `CSR_DMW2;
    wire [31:0] dmw2_wmask = dmw2_wsel ? csr_wmask : 32'b0;
    wire [31:0] dmw2_wdata = dmw2_wmask & csr_wvalue | ~dmw2_wmask & csr_dmw2;

    always @(posedge clk) begin
        csr_dmw2[`CSR_DMW_ZERO1] <= 2'b0;
        csr_dmw2[`CSR_DMW_ZERO2] <= 19'b0;
        csr_dmw2[`CSR_DMW_ZERO3] <= 1'b0;

        if (rst) begin
            csr_dmw2[`CSR_DMW_PLV0] <= 1'b0;
            csr_dmw2[`CSR_DMW_PLV3] <= 1'b0;
            csr_dmw2[`CSR_DMW_MAT]  <= 2'b0;
            csr_dmw2[`CSR_DMW_PSEG] <= 3'b0;
            csr_dmw2[`CSR_DMW_VSEG] <= 3'b0;
        end
        else if (csr_we && dmw2_wsel) begin
            csr_dmw2[`CSR_DMW_PLV0] <= dmw2_wdata[`CSR_DMW_PLV0];
            csr_dmw2[`CSR_DMW_PLV3] <= dmw2_wdata[`CSR_DMW_PLV3];
            csr_dmw2[`CSR_DMW_MAT]  <= dmw2_wdata[`CSR_DMW_MAT];
            csr_dmw2[`CSR_DMW_PSEG] <= dmw2_wdata[`CSR_DMW_PSEG];
            csr_dmw2[`CSR_DMW_VSEG] <= dmw2_wdata[`CSR_DMW_VSEG];
        end
    end

    // DMW3 fields
    wire       dmw3_rsel  = csr_rnum == `CSR_DMW3;
    wire       dmw3_wsel  = csr_wnum == `CSR_DMW3;
    wire [31:0] dmw3_wmask = dmw3_wsel ? csr_wmask : 32'b0;
    wire [31:0] dmw3_wdata = dmw3_wmask & csr_wvalue | ~dmw3_wmask & csr_dmw3;

    always @(posedge clk) begin
        csr_dmw3[`CSR_DMW_ZERO1] <= 2'b0;
        csr_dmw3[`CSR_DMW_ZERO2] <= 19'b0;
        csr_dmw3[`CSR_DMW_ZERO3] <= 1'b0;

        if (rst) begin
            csr_dmw3[`CSR_DMW_PLV0] <= 1'b0;
            csr_dmw3[`CSR_DMW_PLV3] <= 1'b0;
            csr_dmw3[`CSR_DMW_MAT]  <= 2'b0;
            csr_dmw3[`CSR_DMW_PSEG] <= 3'b0;
            csr_dmw3[`CSR_DMW_VSEG] <= 3'b0;
        end
        else if (csr_we && dmw3_wsel) begin
            csr_dmw3[`CSR_DMW_PLV0] <= dmw3_wdata[`CSR_DMW_PLV0];
            csr_dmw3[`CSR_DMW_PLV3] <= dmw3_wdata[`CSR_DMW_PLV3];
            csr_dmw3[`CSR_DMW_MAT]  <= dmw3_wdata[`CSR_DMW_MAT];
            csr_dmw3[`CSR_DMW_PSEG] <= dmw3_wdata[`CSR_DMW_PSEG];
            csr_dmw3[`CSR_DMW_VSEG] <= dmw3_wdata[`CSR_DMW_VSEG];
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
                      | {32{tlbidx_rsel}}     & csr_tlbidx
                      | {32{tlbehi_rsel}}     & csr_tlbehi
                      | {32{tlbelo0_rsel}}    & csr_tlbelo0
                      | {32{tlbelo1_rsel}}    & csr_tlbelo1
                      | {32{asid_rsel}}       & csr_asid
                      | {32{tlbrentry_rsel}}  & csr_tlbrentry
                      | {32{dmw0_rsel}}       & csr_dmw0
                      | {32{dmw1_rsel}}       & csr_dmw1
                      | {32{dmw2_rsel}}       & csr_dmw2
                      | {32{dmw3_rsel}}       & csr_dmw3
                      ;

    assign intr_stat = {13{csr_crmd[`CSR_CRMD_IE]}}
                     & csr_ecfg[`CSR_ECFG_LIE] & csr_estat[`CSR_ESTAT_IS];

    // TLB write port outputs (for TLBWR/TLBFILL)
    // w_index: use random index for TLBFILL, otherwise use TLBIDX.Index
    assign w_index = tlbfill_en ? tlbfill_rand_index : csr_tlbidx[`CSR_TLBIDX_INDEX];
    wire tlb_is_refill = (csr_estat[`CSR_ESTAT_ECODE] == `ECODE_TLBR);
    assign w_e = tlb_is_refill ? 1'b1 : ~csr_tlbidx[`CSR_TLBIDX_NE];  // E = !NE, or 1 if in refill
    assign w_vppn = csr_tlbehi[`CSR_TLBEHI_VPPN];
    assign w_ps = csr_tlbidx[`CSR_TLBIDX_PS];
    assign w_asid = csr_asid[`CSR_ASID_ASID];
    assign w_g = csr_tlbelo0[`CSR_TLBELO_G] & csr_tlbelo1[`CSR_TLBELO_G];  // G if both pages have G=1
    assign w_ppn0 = csr_tlbelo0[`CSR_TLBELO_PPN];
    assign w_plv0 = csr_tlbelo0[`CSR_TLBELO_PLV];
    assign w_mat0 = csr_tlbelo0[`CSR_TLBELO_MAT];
    assign w_d0 = csr_tlbelo0[`CSR_TLBELO_D];
    assign w_v0 = csr_tlbelo0[`CSR_TLBELO_V];
    assign w_ppn1 = csr_tlbelo1[`CSR_TLBELO_PPN];
    assign w_plv1 = csr_tlbelo1[`CSR_TLBELO_PLV];
    assign w_mat1 = csr_tlbelo1[`CSR_TLBELO_MAT];
    assign w_d1 = csr_tlbelo1[`CSR_TLBELO_D];
    assign w_v1 = csr_tlbelo1[`CSR_TLBELO_V];

    // TLB read index (for TLBRD)
    assign r_index = csr_tlbidx[`CSR_TLBIDX_INDEX];

    // Exposed CSR state
    assign crmd_value      = csr_crmd;
    assign asid_value      = csr_asid;
    assign tlbehi_value    = csr_tlbehi;
    assign tlbidx_value    = csr_tlbidx;
    assign tlbrentry_value = csr_tlbrentry;
    assign dmw0_value      = csr_dmw0;
    assign dmw1_value      = csr_dmw1;
    assign dmw2_value      = csr_dmw2;
    assign dmw3_value      = csr_dmw3;

endmodule
