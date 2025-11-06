// CSR addresses
`define CSR_CRMD    14'h000
`define CSR_PRMD    14'h001
`define CSR_ESTAT   14'h005
`define CSR_ERA     14'h006
`define CSR_EENTRY  14'h00c
`define CSR_SAVE(n) (14'h030 + n)
`define CSR_TICLR   14'h044

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
    output wire [31:0]  ex_entry,
    output wire [31:0]  ex_ra
);

    reg [31:0]  csr_crmd;
    reg [31:0]  csr_prmd;
    reg [31:0]  csr_estat;
    reg [31:0]  csr_era;
    reg [31:0]  csr_eentry;
    reg [31:0]  csr_save_i [0:3];

    wire [7:0]  hw_int_in  = 8'b0;   // temporarily set 0 for exp12
    wire        ipi_int_in = 1'b0;

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
        csr_prmd[`CSR_PRMD_ZERO] <= 29'b0;

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

        csr_estat[`CSR_ESTAT_IS_HWI] <= hw_int_in;
        csr_estat[`CSR_ESTAT_IS_PMI] <= 1'b0;
        csr_estat[`CSR_ESTAT_IS_TI]  <= 1'b0; // timer interruption, temporarily set 0 for exp12
        csr_estat[`CSR_ESTAT_IS_IPI] <= ipi_int_in;

        // ESTAT.Ecode
        if (wb_ex) begin
            csr_estat[`CSR_ESTAT_ECODE]     <= wb_ecode;
            csr_estat[`CSR_ESTAT_ESUBCODE]  <= wb_esubcode;
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

    // CSR read
    assign csr_rvalue = {32{crmd_rsel}}   & csr_crmd
                      | {32{prmd_rsel}}   & csr_prmd
                      | {32{estat_rsel}}  & csr_estat
                      | {32{era_rsel}}    & csr_era
                      | {32{eentry_rsel}} & csr_eentry
                      | {32{save_rsel}}   & csr_save;

endmodule
