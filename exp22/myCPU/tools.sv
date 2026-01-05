/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */

// NOTE: one-hot selector
module selector #(
    parameter integer DATA_WIDTH = 32,
    parameter integer SEL_NUM = 16
)(
    input wire [SEL_NUM-1:0] sel,
    input wire [DATA_WIDTH-1:0] in [SEL_NUM-1:0],
    output wire [DATA_WIDTH-1:0] out
);

wire [SEL_NUM-1:0] mat[DATA_WIDTH-1:0];

// transpose
genvar i, j;
generate
    for (i = 0; i < SEL_NUM; i = i + 1) begin
        for (j = 0; j < DATA_WIDTH; j = j + 1) begin
            assign mat[j][i] = sel[i] & in[i][j];
        end
    end
endgenerate

// reduce
generate
    for (i = 0; i < DATA_WIDTH; i = i + 1) begin
        assign out[i] = |mat[i];
    end
endgenerate

endmodule

