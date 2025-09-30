module decoder_2_4(
    input  wire [ 1:0] in,
    output wire [ 3:0] out
);

genvar i;
generate for (i=0; i<4; i=i+1) begin : gen_for_dec_2_4
    assign out[i] = (in == i);
end endgenerate

endmodule


module decoder_4_16(
    input  wire [ 3:0] in,
    output wire [15:0] out
);

genvar i;
generate for (i=0; i<16; i=i+1) begin : gen_for_dec_4_16
    assign out[i] = (in == i);
end endgenerate

endmodule


module decoder_5_32(
    input  wire [ 4:0] in,
    output wire [31:0] out
);

genvar i;
generate for (i=0; i<32; i=i+1) begin : gen_for_dec_5_32
    assign out[i] = (in == i);
end endgenerate

endmodule


module decoder_6_64(
    input  wire [ 5:0] in,
    output wire [63:0] out
);

genvar i;
generate for (i=0; i<64; i=i+1) begin : gen_for_dec_6_64
    assign out[i] = (in == i);
end endgenerate

endmodule

module pipeline(
    input  wire clk, rst,
    input  wire allowout, // -->? [next_stage]
    input  wire validin,  // valid? ---> [stage]
    input  wire readygo,  // [stage] -->?
    output wire validout, // [stage] --> valid?
    output wire allowin,  // --->? [stage]
    output reg  valid   // [stage?]
);

    assign allowin = ~valid | (readygo & allowout);
    assign validout = valid & readygo;

    always @(posedge clk) begin
        if (rst) begin
            valid <= 1'b0;
        end else if (allowin) begin
            valid <= validin;
        end
    end

  wire refreshing = validin & allowin;
endmodule

module cancelable_pipeline (
    input wire clk,
    rst,
    input wire allowout,  // -->? [next_stage]
    input wire validin,  // valid? ---> [stage]
    input wire readygo,  // [stage] -->?
    input wire cancel,  // cancel current stage, do not allow it to come out.
    output wire validout,  // [stage] --> valid?
    output wire allowin,  // --->? [stage]
    output reg valid  // [stage?]
);

  assign allowin  = ~valid | (readygo & allowout);
  assign validout = valid & readygo & ~cancel;

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0;
    end else if (allowin) begin
      valid <= validin;
    end else if (cancel) begin
      valid <= 1'b0;
    end
  end

  wire refreshing = validin & allowin;
endmodule

