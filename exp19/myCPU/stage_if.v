`timescale 10ns / 1ps

`include "macro.v"

module stage_if(
    input wire clk, rst,
    
    // pipeline control
    input wire allowout, validin,
    output wire allowin, validout,
    input wire cancelin, cancelout,

    // pipeline data
    input wire [31:0] input_pc,
    output wire [31:0] output_pc,
    output wire [31:0] output_inst,

    // TLB exception input
    input wire        input_tlb_ex,
    input wire [5:0]  input_tlb_ecode,
    input wire        input_tlb_found,
    input wire [3:0]  input_tlb_index,
    input wire [5:0]  input_tlb_ps,

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
    output wire        output_tlb_found,
    output wire [3:0]  output_tlb_index,
    output wire [5:0]  output_tlb_ps,

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
        end else if (cancelin) begin
            cancelled <= 1'b1;
        end else if (allowin) begin
            cancelled <= 1'b0;
        end else if (cancelout) begin
            cancelled <= 1'b1;
        end
    end

    assign validout = raw_validout & ~cancelled & ~cancelout;

    reg [31:0] pc, inst;
    wire except_adef = (pc[1:0] != 2'b0);
    
    reg tlb_ex_r;
    reg tlb_found_r;
    reg [3:0] tlb_index_r;
    reg [5:0] tlb_ps_r;
    reg [5:0] tlb_ecode_r;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
            tlb_ex_r <= 1'b0;
            tlb_found_r <= 1'b0;
            tlb_index_r <= 4'h0;
            tlb_ps_r <= 6'h0;
            tlb_ecode_r <= 6'h0;
        end else if (refreshing) begin
            pc <= input_pc;
            tlb_ex_r <= input_tlb_ex;
            tlb_ecode_r <= input_tlb_ecode;
            tlb_found_r <= input_tlb_ex ? input_tlb_found : 1'b0;
            tlb_index_r <= input_tlb_ex ? input_tlb_index : 4'h0;
            tlb_ps_r <= input_tlb_ex ? input_tlb_ps : 6'h0;
        end
    end

    // 当前指令没有传到 ID 级的时候 sram 又返回了数据，就把数据存到 buffer 里
    reg buffer_valid;
    reg [31:0] inst_buffer;

    wire buffer_pop = refreshing && buffer_valid;
    wire buffer_push_case1 = inst_sram_data_ok && (refreshing && buffer_valid); // #1
    wire buffer_push_case2 = inst_sram_data_ok && (already_ok && ~refreshing); // #2
    wire buffer_push = buffer_push_case1 | buffer_push_case2;

    always @(posedge clk) begin
        if (rst) begin
            buffer_valid <= 1'b0;
            inst_buffer <= 32'h0;
        end else begin
            if (buffer_pop && ~buffer_push)
                buffer_valid <= 1'b0;
            else if (buffer_push)
                buffer_valid <= 1'b1;

            if (buffer_push)
                inst_buffer <= inst_sram_rdata;
        end
    end

    // 注意 inst_sram_data_ok == 1 时，可能有三个地方保存 inst_sram_rdata，
    // 而这三个地方的保存条件是互斥且完备的
    // A = refreshing && buffer_valid
    // B = ~refreshing && already_ok
    //
    // 更新点：
    // #1. A
    // #2. ~A && B
    // #3. ~A && ~B

    always @(posedge clk) begin
        if (rst) begin
            inst <= 32'h0;
        end else if (refreshing && buffer_valid) begin
            inst <= inst_buffer;
        end else if (inst_sram_data_ok && (~already_ok || refreshing)) begin // #3
            inst <= inst_sram_rdata;
        end
    end

    reg already_ok;

    always @(posedge clk) begin
        if (rst) begin
            already_ok <= 1'b0;
        end else if (refreshing && buffer_valid) begin
            already_ok <= 1'b1;
        end else if (inst_sram_data_ok && (~already_ok || refreshing)) begin
            already_ok <= 1'b1;
        end else if (refreshing) begin
            already_ok <= 1'b0;
        end
    end

    assign readygo = already_ok;

    // assign inst_sram_addr = pc;
    // assign inst_sram_req = ~except_adef & (state == REQ) & valid;
    // assign inst_sram_wr = 1'b0;
    // assign inst_sram_wstrb = 4'b0;
    // assign inst_sram_size = 2'b10; // word
    // assign inst_sram_wdata = 32'h0;

    assign output_pc = pc;
    assign output_inst = inst;

    wire has_exception = except_adef | tlb_ex_r;
    assign output_ex_valid = has_exception & validout;
    assign output_ecode = except_adef ? `ECODE_ADEF : tlb_ecode_r;
    assign output_esubcode = except_adef ? `ESUBCODE_ADEF : 9'h0;
    assign output_tlb_found = tlb_found_r;
    assign output_tlb_index = tlb_index_r;
    assign output_tlb_ps = tlb_ps_r;

    assign output_is_csr = has_exception;
    assign output_csr_en = has_exception;
    assign output_csr_num = `CSR_BADV;
    assign output_csr_we = has_exception;
    assign output_csr_wmask = 32'hffff_ffff;
    assign output_csr_wvalue = pc;

endmodule

