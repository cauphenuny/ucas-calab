`timescale 10ns / 1ps

module stage_ex(
    input  wire clk, rst,

    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,

    // pipeline data

    // ....data held for trace
    input  wire [31:0] input_pc,
    output wire [31:0] output_pc,

    // ....data held for WB stage
    input  wire [ 4:0] input_rf_waddr,
    input  wire        input_rf_we,
    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,

    // ....data held for MEM stage
    input  wire [31:0] input_mem_data,
    input  wire        input_mem_read,
    input  wire        input_mem_write,
    output wire        output_mem_read,

    // ....data processed in EX stage
    input  wire [31:0] input_alu_src1, input_alu_src2,
    input  wire [11:0] input_alu_op,
    output wire [31:0] output_alu_result, // alu_result

    // I/O
    output wire [ 4:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);

    wire valid;

    pipeline pipl(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(1'b1),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

/**************** execute unit ****************/

    reg [31:0] alu_src1, alu_src2;
    reg [11:0] alu_op;
    wire [31:0] alu_result;

    always @(posedge clk) begin
        if (rst) begin
            alu_src1 <= 32'h0;
            alu_src2 <= 32'h0;
            alu_op   <= 12'h0;
        end
        else if (allowin && validin) begin
            alu_src1 <= input_alu_src1;
            alu_src2 <= input_alu_src2;
            alu_op   <= input_alu_op;
        end
    end

    alu u_alu(
        .alu_op(alu_op),
        .alu_src1(alu_src1),
        .alu_src2(alu_src2),
        .alu_result(alu_result)
    );

    assign output_alu_result = alu_result;

/**************** hold trace data ****************/

    localparam TRACE_HOLD_WIDTH = 32;

    reg [TRACE_HOLD_WIDTH-1:0] trace_regs;

    always @(posedge clk) begin
        if (rst) begin
            trace_regs <= {TRACE_HOLD_WIDTH{1'b0}};
        end
        else if (allowin && validin) begin
            trace_regs <= {input_pc};
        end
    end

    assign {output_pc} = trace_regs;

/**************** hold memory stage data ****************/

    reg         mem_read, mem_write;
    reg [31:0]  mem_data;

    always @(posedge clk) begin
        if (rst) begin
            mem_read <= 1'b0;
            mem_write <= 1'b0;
            mem_data <= 32'h0;
        end
        else if (allowin && validin) begin
            mem_read <= input_mem_read;
            mem_write <= input_mem_write;
            mem_data <= input_mem_data;
        end
    end

    assign data_sram_we    = {4{mem_write}};
    assign data_sram_addr  = alu_result;
    assign data_sram_wdata = mem_data;

    assign output_mem_read = mem_read;

/**************** hold write-back stage data ****************/

    localparam WB_HOLD_WIDTH = 5 // $bits(input_rf_waddr)
                             + 1 // $bits(input_rf_we)
                             ;

    reg [WB_HOLD_WIDTH-1:0] wb_regs;

    always @(posedge clk) begin
        if (rst) begin
            wb_regs <= {WB_HOLD_WIDTH{1'b0}};
        end
        else if (allowin && validin) begin
            wb_regs <= {input_rf_waddr, input_rf_we};
        end
    end

    assign {output_rf_waddr, output_rf_we} = wb_regs;

endmodule
