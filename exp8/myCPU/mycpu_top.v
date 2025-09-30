`timescale 10ns / 1ps

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    reg         rst;
    always @(posedge clk) rst <= ~resetn;

    reg         valid;
    always @(posedge clk) begin
        if (rst) begin
            valid <= 1'b0;
        end else begin
            valid <= 1'b1;
        end
    end

    wire [31:0] nextpc, seq_pc, br_target;
    reg  [31:0] pc;
    wire br_taken, if_refreshing;
    wire if_allowin, if_validin;
    assign if_validin = valid;

    assign if_refreshing = if_allowin & if_validin;
    assign seq_pc        = pc + 3'h4;
    assign nextpc        = br_taken ? br_target : seq_pc;

    assign inst_sram_addr = nextpc;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h1c000000;
        end else if (if_refreshing) begin
            pc <= nextpc;
        end
    end

    wire [ 4:0] rf_raddr1, rf_raddr2, rf_waddr;
    wire [31:0] rf_rdata1, rf_rdata2, rf_wdata;
    wire rf_we;

    regfile u_regfile(
        .clk    (clk      ),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_rdata2),
        .we     (rf_we    ),
        .waddr  (rf_waddr ),
        .wdata  (rf_wdata )
    );

    /* verilator lint_off PINCONNECTEMPTY */

    stage_if u_stage_if(
        .clk(clk),
        .rst(rst),
        .validin(if_validin),
        .allowin(if_allowin),
        .validout(),
        .allowout(),
        .cancel(br_taken),

        .input_pc(pc),
        .output_pc(),
        .output_inst(),

        // .inst_sram_addr(inst_sram_addr),
        .inst_sram_rdata(inst_sram_rdata)
    );

    wire id_stall;

    stage_id u_stage_id(
        .clk(clk),
        .rst(rst),
        .validin(u_stage_if.validout),
        .allowin(u_stage_if.allowout),
        .validout(),
        .allowout(),
        .stall(id_stall),

        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),

        .input_pc(u_stage_if.output_pc),
        .input_inst(u_stage_if.output_inst),

        .output_pc(),
        .output_br_target(br_target),
        .output_br_taken(br_taken),
        .output_alu_src1(),
        .output_alu_src2(),
        .output_alu_op(),

        .output_mem_data(),
        .output_mem_read(),
        .output_mem_write(),

        .output_rf_waddr(),
        .output_rf_we()
    );

    stage_ex u_stage_ex(
        .clk(clk),
        .rst(rst),
        .validin(u_stage_id.validout),
        .allowin(u_stage_id.allowout),
        .validout(),
        .allowout(),

        .input_pc(u_stage_id.output_pc),
        .input_alu_src1(u_stage_id.output_alu_src1),
        .input_alu_src2(u_stage_id.output_alu_src2),
        .input_alu_op(u_stage_id.output_alu_op),

        .input_rf_waddr(u_stage_id.output_rf_waddr),
        .input_rf_we(u_stage_id.output_rf_we),

        .input_mem_data(u_stage_id.output_mem_data),
        .input_mem_read(u_stage_id.output_mem_read),
        .input_mem_write(u_stage_id.output_mem_write),

        .output_pc(),
        .output_rf_waddr(),
        .output_rf_we(),
        .output_mem_read(),
        .output_alu_result(),

        .data_sram_we(data_sram_we),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata)
    );

    stage_mem u_stage_mem(
        .clk(clk),
        .rst(rst),
        .validin(u_stage_ex.validout),
        .allowin(u_stage_ex.allowout),
        .validout(),
        .allowout(),
        
        .input_pc(u_stage_ex.output_pc),
        .output_pc(),

        .input_rf_waddr(u_stage_ex.output_rf_waddr),
        .input_rf_we(u_stage_ex.output_rf_we),
        .output_rf_waddr(),
        .output_rf_wdata(),
        .output_rf_we(),

        .input_mem_read(u_stage_ex.output_mem_read),
        .input_alu_result(u_stage_ex.output_alu_result),

        .data_sram_rdata(data_sram_rdata)
    );

    wire        wb_valid;
    wire        wb_rf_we;
    wire [ 4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    wire [31:0] wb_pc;

    stage_wb u_stage_wb(
        .clk(clk),
        .rst(rst),
        .allowin(u_stage_mem.allowout),
        .validin(u_stage_mem.validout),
        .allowout(1'b1),
        .validout(wb_valid),

        .input_pc(u_stage_mem.output_pc),
        .output_pc(wb_pc),

        .input_rf_waddr(u_stage_mem.output_rf_waddr),
        .input_rf_wdata(u_stage_mem.output_rf_wdata),
        .input_rf_we(u_stage_mem.output_rf_we),

        .output_rf_waddr(wb_rf_waddr),
        .output_rf_wdata(wb_rf_wdata),
        .output_rf_we(wb_rf_we),

        .rf_we(rf_we),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata)
    );

    wire conflict1 =
        rf_raddr1 == 5'h0 ? 0 :
        (u_stage_ex.valid && u_stage_ex.output_rf_we && (u_stage_ex.output_rf_waddr == rf_raddr1)) || 
        (u_stage_mem.valid && u_stage_mem.output_rf_we && (u_stage_mem.output_rf_waddr == rf_raddr1)) || 
        (u_stage_wb.valid && u_stage_wb.output_rf_we && (u_stage_wb.output_rf_waddr == rf_raddr1));
    wire conflict2 =
        rf_raddr2 == 5'h0 ? 0 :
        (u_stage_ex.valid && u_stage_ex.output_rf_we && (u_stage_ex.output_rf_waddr == rf_raddr2)) || 
        (u_stage_mem.valid && u_stage_mem.output_rf_we && (u_stage_mem.output_rf_waddr == rf_raddr2)) || 
        (u_stage_wb.valid && u_stage_wb.output_rf_we && (u_stage_wb.output_rf_waddr == rf_raddr2));

    assign id_stall = conflict1 || conflict2;

    /* verilator lint_on PINCONNECTEMPTY */

    assign data_sram_en = 1'h1;
    assign inst_sram_we = 4'h0;
    assign inst_sram_en = rst | if_refreshing;
    assign inst_sram_wdata = 32'h0;

    assign debug_wb_pc       = wb_pc;
    assign debug_wb_rf_we    = {4{wb_rf_we & wb_valid}};
    assign debug_wb_rf_wnum  = wb_rf_waddr;
    assign debug_wb_rf_wdata = wb_rf_wdata;

endmodule
