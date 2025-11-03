`timescale 10ns / 1ps

module stage_wb(
    input  wire clk, rst,

    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,

    // pipeline data

    // ....data held for trace
    input  wire [31:0] input_pc,
    output wire [31:0] output_pc,

    // ....data processed in WB stage
    input  wire [ 4:0] input_rf_waddr,
    input  wire        input_rf_we,
    input  wire [31:0] input_rf_wdata,

    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,
    output wire [31:0] output_rf_wdata,

    // ...data forwarded to ID stage of next inst
    output wire [31:0] forward_data,
    output wire        forward_ready,

    // CSR bundle
    input  wire        input_csr_en,
    input  wire [13:0] input_csr_num,
    input  wire        input_csr_we,
    input  wire [31:0] input_csr_wmask,
    input  wire [31:0] input_csr_wvalue,

    // ERTN flag
    input  wire        input_is_ertn,

    // CSR flag/value
    input  wire        input_is_csr,
    input  wire [31:0] input_csr_rvalue,

    // exception info
    input  wire        input_ex_valid,
    input  wire [ 5:0] input_ecode,
    input  wire [ 8:0] input_esubcode,

    // I/O
    output reg        rf_we,
    output reg [ 4:0] rf_waddr,
    output reg [31:0] rf_wdata,

    // exception handling / CSR interface
    output  wire [13:0]  csr_wnum,
    output  wire         csr_we,
    output  wire [31:0]  csr_wmask,
    output  wire [31:0]  csr_wvalue,
    output  wire         ertn_flush,
    output  wire         wb_ex_valid,
    output  wire [ 5:0]  wb_ecode,
    output  wire [ 8:0]  wb_esubcode
);

    wire valid;
    wire readygo = 1'b1;

    pipeline pipe (
        .clk(clk),
        .rst(rst),
        .allowout(allowout),
        .validin(validin),
        .readygo(readygo),
        .validout(validout),
        .allowin(allowin),
        .valid(valid)
    );

    reg [31:0] pc;
    reg        ex_valid_r;
    reg [5:0]  ecode_r;
    reg [8:0]  esubcode_r;
    reg        csr_en_r;
    reg [13:0] csr_num_r;
    reg        csr_we_r;
    reg [31:0] csr_wmask_r;
    reg [31:0] csr_wvalue_r;
    reg        is_ertn_r;
    reg        is_csr_r;
    reg [31:0] csr_rvalue_r;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
            rf_waddr <= 5'h0;
            rf_we <= 1'b0;
            rf_wdata <= 32'h0;
        end else if (pipe.refreshing) begin
            pc <= input_pc;
            rf_waddr <= input_rf_waddr;
            rf_we <= input_rf_we;
            rf_wdata <= input_rf_wdata;
            ex_valid_r <= input_ex_valid;
            ecode_r    <= input_ecode;
            esubcode_r <= input_esubcode;
            csr_en_r   <= input_csr_en;
            csr_num_r  <= input_csr_num;
            csr_we_r   <= input_csr_we;
            csr_wmask_r<= input_csr_wmask;
            csr_wvalue_r<= input_csr_wvalue;
            is_ertn_r  <= input_is_ertn;
            is_csr_r   <= input_is_csr;
            csr_rvalue_r<= input_csr_rvalue;
        end
    end

    assign output_pc = pc;
    assign output_rf_waddr = rf_waddr;

    wire [31:0] wb_data = is_csr_r ? csr_rvalue_r : rf_wdata;
    assign output_rf_wdata = wb_data;
    assign output_rf_we = rf_we;

    assign forward_data = wb_data;
    assign forward_ready = readygo;

    assign csr_wnum   = csr_num_r;
    assign csr_we     = csr_we_r & valid;
    assign csr_wmask  = csr_wmask_r;
    assign csr_wvalue = csr_wvalue_r;
    assign ertn_flush = valid & is_ertn_r;

    assign wb_ex_valid  = valid & ex_valid_r;
    assign wb_ecode     = ecode_r;
    assign wb_esubcode  = esubcode_r;

endmodule
