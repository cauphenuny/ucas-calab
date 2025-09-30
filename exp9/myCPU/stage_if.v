`timescale 10ns / 1ps

module stage_if(
    input  wire clk, rst,
    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,
    input  wire cancel, // cancel current inst in reg, do not cancel refreshing inst.

    // pipeline data
    input  wire [31:0] input_pc,

    output wire [31:0] output_pc,
    output wire [31:0] output_inst,

    // I/O
    // output wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_rdata
);

    wire valid;

    cancelable_pipeline pipl(
        .clk(clk), .rst(rst),
        .allowout(allowout),
        .validin(validin & (~cancel)),
        .readygo(1'b1),
        .cancel(cancel),
        .validout(validout), .allowin(allowin), 
        .valid(valid)
    );

    reg [31:0] pc, inst;

    wire refreshing = allowin && validin;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
            inst <= 32'h0;
        end
        else if (refreshing) begin
            pc <= input_pc;
            inst <= inst_sram_rdata;
        end
    end

    /*******************************/

    assign output_pc = pc;
    assign output_inst = inst;

endmodule
