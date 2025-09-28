`timescale 10ns / 1ps

module stage_mem(
    input  wire clk, rst,
    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,

    // pipeline data

    // ..data held for trace
    input  wire [31:0] input_pc,
    output wire [31:0] output_pc,

    // ....data held for WB stage
    input  wire [ 4:0] input_rf_waddr,
    input  wire        input_rf_we,
    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,

    // ....data processed in MEM stage
    input  wire        input_mem_read,
    input  wire [31:0] input_alu_result,

    output wire [31:0] output_rf_wdata,

    // I/O
    input  wire [31:0] data_sram_rdata
);

    wire valid;

    pipeline pipl(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(1'b1),
        .validout(validout), .allowin(allowin), 
        .valid(valid)
    );

/**************** memory access unit ****************/

    reg         mem_read;
    reg [31:0]  alu_result;

    always @(posedge clk) begin
        if (rst) begin
            mem_read   <= 1'b0;
            alu_result <= 32'h0;
        end
        else if (allowin && validin) begin
            mem_read   <= input_mem_read;
            alu_result <= input_alu_result;
        end
    end

    wire [31:0] mem_rdata = data_sram_rdata;

    assign output_rf_wdata = mem_read ? mem_rdata : alu_result;

/**************** hold trace data ****************/

    localparam TRACE_HOLD_WIDTH = 32; //$bits(input_pc);

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

/**************** hold write-back stage data ****************/

    localparam WB_HOLD_WIDTH = 5 // $bits(input_rf_waddr)
                             + 1;// $bits(input_rf_we);

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
