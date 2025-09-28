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
    output wire [ 3:0] output_rf_we,
    output wire [31:0] output_rf_wdata,

    // I/O
    output reg        rf_we,
    output reg [ 4:0] rf_waddr,
    output reg [31:0] rf_wdata
);

    wire valid;
    
    pipeline pipl(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(1'b1),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

    reg [31:0] pc;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
            rf_waddr <= 5'h0;
            rf_we <= 1'b0;
            rf_wdata <= 32'h0;
        end else if (allowin && validin) begin
            pc <= input_pc;
            rf_waddr <= input_rf_waddr;
            rf_we <= input_rf_we;
            rf_wdata <= input_rf_wdata;
        end
    end

    assign output_pc = pc;
    assign output_rf_waddr = rf_waddr;
    assign output_rf_wdata = rf_wdata;
    assign output_rf_we = rf_we;

endmodule
