`timescale 10ns / 1ps

module stage_if(
    input wire clk, rst,
    
    // pipeline control
    input wire allowout, validin,
    output wire allowin, validout,
    input wire cancel,

    // pipeline data
    input wire [31:0] input_pc,
    output wire [31:0] output_pc,
    output wire [31:0] output_inst,

    // exception info
    output wire [5:0]  output_ecode,
    output wire [8:0]  output_esubcode,
    output wire        output_csr_en,
    output wire        output_csr_we,
    output wire        output_is_csr,
    output wire [31:0] output_csr_wmask,
    output wire [31:0] output_csr_wvalue,
    output wire [13:0] output_csr_num,

    output wire        output_ex_valid,

    // I/O
    // output wire inst_sram_req,
    // output wire inst_sram_wr,
    // output wire [1:0] inst_sram_size,
    // output wire [31:0] inst_sram_addr,
    // output wire [3:0] inst_sram_wstrb,
    // output wire [31:0] inst_sram_wdata,
    // input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata
);

    wire valid, readygo;

    wire raw_validout;

    pipeline pipe(
        .clk(clk),
        .rst(rst),
        .allowout(allowout),
        .validin(validin),
        .readygo(readygo),
        .validout(raw_validout),
        .allowin(allowin),
        .valid(valid)
    );

    reg cancelled;

    wire refreshing = allowin & validin;

    always @(posedge clk) begin
        if (rst) begin
            cancelled <= 1'b0;
        end else if (allowin) begin
            cancelled <= 1'b0;
        end else if (cancel) begin
            cancelled <= 1'b1;
        end
    end

    assign validout = raw_validout & ~cancelled & ~cancel;

    reg [31:0] pc, inst;
    wire except_adef = (pc[1:0] != 2'b0);

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
        end else if (refreshing) begin
            pc <= input_pc;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            inst <= 32'h0;
        end else if (inst_sram_data_ok) begin
            inst <= inst_sram_rdata;
        end
    end

    reg already_ok;

    always @(posedge clk) begin
        if (rst) begin
            already_ok <= 1'b0;
        end else if (inst_sram_data_ok) begin
            already_ok <= 1'b1;
        end else if (refreshing) begin
            already_ok <= 1'b0;
        end
    end

    assign readygo = already_ok | inst_sram_data_ok;

    // assign inst_sram_addr = pc;
    // assign inst_sram_req = ~except_adef & (state == REQ) & valid;
    // assign inst_sram_wr = 1'b0;
    // assign inst_sram_wstrb = 4'b0;
    // assign inst_sram_size = 2'b10; // word
    // assign inst_sram_wdata = 32'h0;

    assign output_pc = pc;
    assign output_inst = inst_sram_data_ok ? inst_sram_rdata : inst;

    assign output_ex_valid = except_adef & validout;
    assign output_ecode = `ECODE_ADEF;
    assign output_esubcode = `ESUBCODE_ADEF;

    assign output_is_csr = except_adef;
    assign output_csr_en = except_adef;
    assign output_csr_num = `CSR_BADV;
    assign output_csr_we = except_adef;
    assign output_csr_wmask = 32'hffff_ffff;
    assign output_csr_wvalue = pc;

endmodule