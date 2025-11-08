`timescale 10ns / 1ps

module alu(
    input  wire        clk, rst,
    input  wire        alu_req_valid,
    input  wire [18:0] alu_op,
    input  wire [31:0] alu_src1,
    input  wire [31:0] alu_src2,
    output wire        alu_result_valid,
    output wire [31:0] alu_result
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate
wire op_mul;
wire op_mulh;
wire op_mulhu;
wire op_div;
wire op_divu;
wire op_mod;
wire op_modu;

// control code decomposition
assign op_add   = alu_op[ 0];
assign op_sub   = alu_op[ 1];
assign op_slt   = alu_op[ 2];
assign op_sltu  = alu_op[ 3];
assign op_and   = alu_op[ 4];
assign op_nor   = alu_op[ 5];
assign op_or    = alu_op[ 6];
assign op_xor   = alu_op[ 7];
assign op_sll   = alu_op[ 8];
assign op_srl   = alu_op[ 9];
assign op_sra   = alu_op[10];
assign op_lui   = alu_op[11];
assign op_mul   = alu_op[12];
assign op_mulh  = alu_op[13];
assign op_mulhu = alu_op[14];
assign op_div   = alu_op[15];
assign op_divu  = alu_op[16];
assign op_mod   = alu_op[17];
assign op_modu  = alu_op[18];

wire sdiv_enable = op_div | op_mod;
wire udiv_enable = op_divu | op_modu;
wire div_enable = sdiv_enable | udiv_enable;

/****************** simple ALU operations ******************/

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;

/* verilator lint_off WIDTHEXPAND */
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;
/* verilator lint_on WIDTHEXPAND */

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

wire [ 1:0] _discard;
wire [31:0] mulh_result;
wire [31:0] mul_result;

assign {_discard, mulh_result, mul_result} = $signed({~op_mulhu & alu_src1[31], alu_src1}) * $signed({~op_mulhu & alu_src2[31], alu_src2});

/****************** division unit ******************/

/* verilator lint_off MODMISSING */

wire sdiv_divisor_ready, sdiv_divisor_valid;
wire sdiv_dividend_ready, sdiv_dividend_valid;
wire sdiv_result_valid;
wire [31:0] sdiv_quotient, sdiv_remainder;
sdiv u_sdiv(
    .aclk(clk),
    .s_axis_dividend_tready(sdiv_dividend_ready),
    .s_axis_dividend_tvalid(sdiv_dividend_valid),
    .s_axis_dividend_tdata(alu_src1),
    .s_axis_divisor_tready(sdiv_divisor_ready),
    .s_axis_divisor_tvalid(sdiv_divisor_valid),
    .s_axis_divisor_tdata(alu_src2),
    .m_axis_dout_tdata({sdiv_quotient, sdiv_remainder}),
    .m_axis_dout_tvalid(sdiv_result_valid)
);

wire udiv_divisor_ready, udiv_divisor_valid;
wire udiv_dividend_ready, udiv_dividend_valid;
wire udiv_result_valid;
wire [31:0] udiv_quotient, udiv_remainder;
udiv u_udiv(
    .aclk(clk),
    .s_axis_dividend_tready(udiv_dividend_ready),
    .s_axis_dividend_tvalid(udiv_dividend_valid),
    .s_axis_dividend_tdata(alu_src1),
    .s_axis_divisor_tready(udiv_divisor_ready),
    .s_axis_divisor_tvalid(udiv_divisor_valid),
    .s_axis_divisor_tdata(alu_src2),
    .m_axis_dout_tdata({udiv_quotient, udiv_remainder}),
    .m_axis_dout_tvalid(udiv_result_valid)
);

/* verilator lint_on MODMISSING */

// module udiv(aclk, s_axis_divisor_tvalid,
//   s_axis_divisor_tready, s_axis_divisor_tdata, s_axis_dividend_tvalid,
//   s_axis_dividend_tready, s_axis_dividend_tdata, m_axis_dout_tvalid, m_axis_dout_tdata)
// /* synthesis syn_black_box black_box_pad_pin="s_axis_divisor_tvalid,s_axis_divisor_tready,s_axis_divisor_tdata[31:0],s_axis_dividend_tvalid,s_axis_dividend_tready,s_axis_dividend_tdata[31:0],m_axis_dout_tvalid,m_axis_dout_tdata[63:0]" */
// /* synthesis syn_force_seq_prim="aclk" */;
//   input aclk /* synthesis syn_isclock = 1 */;
//   input s_axis_divisor_tvalid;
//   output s_axis_divisor_tready;
//   input [31:0]s_axis_divisor_tdata;
//   input s_axis_dividend_tvalid;
//   output s_axis_dividend_tready;
//   input [31:0]s_axis_dividend_tdata;
//   output m_axis_dout_tvalid;
//   output [63:0]m_axis_dout_tdata;
// endmodule

/****************** final result ******************/

assign alu_result = ({32{op_add|op_sub   }} & add_sub_result)
                  | ({32{op_slt          }} & slt_result)
                  | ({32{op_sltu         }} & sltu_result)
                  | ({32{op_and          }} & and_result)
                  | ({32{op_nor          }} & nor_result)
                  | ({32{op_or           }} & or_result)
                  | ({32{op_xor          }} & xor_result)
                  | ({32{op_lui          }} & lui_result)
                  | ({32{op_sll          }} & sll_result)
                  | ({32{op_srl|op_sra   }} & sr_result)
                  | ({32{op_mul          }} & mul_result)
                  | ({32{op_mulh|op_mulhu}} & mulh_result)
                  | ({32{op_div          }} & sdiv_quotient)
                  | ({32{op_divu         }} & udiv_quotient)
                  | ({32{op_mod          }} & sdiv_remainder)
                  | ({32{op_modu         }} & udiv_remainder)
                  ;

/****************** state machine ******************/

// INIT -> SIMPLE -> DIV_REQ -> DIV_RECV -+
//           |                            |
//           +------<----------<----------+

localparam [2:0] STATE_INIT = 3'd0;
localparam [2:0] STATE_SIMPLE = 3'd1;
localparam [2:0] STATE_DIV_REQ = 3'd2;
localparam [2:0] STATE_DIV_RECV = 3'd3;

reg [2:0] current_state, next_state;

always @(posedge clk) begin
    if (rst) current_state <= 3'h0;
    else current_state <= next_state;
end

wire div_result_valid = (sdiv_enable & sdiv_result_valid) | (udiv_enable & udiv_result_valid);

always @(*) begin
    case (current_state)
        STATE_INIT: begin
            next_state = STATE_SIMPLE;
        end
        STATE_SIMPLE: begin
            next_state = (alu_req_valid && div_enable) ? STATE_DIV_REQ : STATE_SIMPLE;
        end
        STATE_DIV_REQ: begin
            if (sdiv_enable && (sdiv_divisor_valid & sdiv_divisor_ready & sdiv_dividend_ready & sdiv_dividend_valid)) next_state = STATE_DIV_RECV;
            else if (udiv_enable && (udiv_divisor_valid & udiv_divisor_ready & udiv_dividend_ready & udiv_dividend_valid)) next_state = STATE_DIV_RECV;
            else next_state = STATE_DIV_REQ;
        end
        STATE_DIV_RECV: begin
            if (div_result_valid) next_state = STATE_SIMPLE;
            else next_state = STATE_DIV_RECV;
        end
        default: begin
            next_state = STATE_INIT;
        end
    endcase
end

assign sdiv_divisor_valid = (current_state == STATE_DIV_REQ) && sdiv_enable;
assign udiv_divisor_valid = (current_state == STATE_DIV_REQ) && udiv_enable;
assign sdiv_dividend_valid = (current_state == STATE_DIV_REQ) && sdiv_enable;
assign udiv_dividend_valid = (current_state == STATE_DIV_REQ) && udiv_enable;

assign alu_result_valid = ((current_state == STATE_SIMPLE) & ~div_enable)
                        | ((current_state == STATE_DIV_RECV) & div_result_valid)
                        ;

endmodule
