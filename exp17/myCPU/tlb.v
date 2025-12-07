`timescale 1ns / 1ps
`define TLBNUMLG ($clog2(TLBNUM))
module tlb #(
    parameter integer TLBNUM = 16
)(
    input wire clk,

    // search port 0 (fetch)
    input  wire [18:0]          s0_vppn,
    input  wire                 s0_va_bit12,
    input  wire [ 9:0]          s0_asid,
    output wire                 s0_found,
    output wire [TLBNUMLG-1:0]  s0_index,
    output wire [19:0]          s0_ppn, // page number
    output wire [ 5:0]          s0_ps, // page size
    output wire [ 1:0]          s0_plv,
    output wire [ 1:0]          s0_mat, // memory assess type
    output wire                 s0_d, // dirty
    output wire                 s0_v, // valid

    // search port 1 (load/store)
    input  wire [18:0]          s1_vppn,
    input  wire                 s1_va_bit12,
    input  wire [ 9:0]          s1_asid,
    output wire                 s1_found,
    output wire [TLBNUMLG-1:0]  s1_index,
    output wire [19:0]          s1_ppn,
    output wire [ 5:0]          s1_ps,
    output wire [ 1:0]          s1_plv,
    output wire [ 1:0]          s1_mat,
    output wire                 s1_d,
    output wire                 s1_v,

    // invtlb opcode (reuse search port 1 signals)
    input  wire                 invtlb_valid,
    input  wire [ 4:0]          invtlb_op,

    // write port
    input  wire                 we, // write enable
    input  wire [TLBNUMLG-1:0]  w_index,
    input  wire                 w_e, // the e flag in pagetable entry
    input  wire [18:0]          w_vppn,
    input  wire [ 5:0]          w_ps,
    input  wire [ 9:0]          w_asid,
    input  wire                 w_g,
    input  wire [19:0]          w_ppn0,
    input  wire [ 1:0]          w_plv0,
    input  wire [ 1:0]          w_mat0,
    input  wire                 w_d0,
    input  wire                 w_v0,
    input  wire [19:0]          w_ppn1,
    input  wire [ 1:0]          w_plv1,
    input  wire [ 1:0]          w_mat1,
    input  wire                 w_d1,
    input  wire                 w_v1,

    // read port
    input  wire [TLBNUMLG-1:0]  r_index,
    output wire                 r_e,
    output wire [18:0]          r_vppn,
    output wire [ 5:0]          r_ps,
    output wire [ 9:0]          r_asid,
    output wire                 r_g,
    output wire [19:0]          r_ppn0,
    output wire [ 1:0]          r_plv0,
    output wire [ 1:0]          r_mat0,
    output wire                 r_d0,
    output wire                 r_v0,
    output wire [19:0]          r_ppn1,
    output wire [ 1:0]          r_plv1,
    output wire [ 1:0]          r_mat1,
    output wire                 r_d1,
    output wire                 r_v1

);

reg [TLBNUM-1:0] tlb_e;
reg [TLBNUM-1:0] tlb_ps4MB; // 1: 4MB, 0: 4KB
reg [      18:0] tlb_vppn   [TLBNUM-1:0];
reg [       9:0] tlb_asid   [TLBNUM-1:0];
reg              tlb_g      [TLBNUM-1:0];
reg [      19:0] tlb_ppn0   [TLBNUM-1:0];
reg [       1:0] tlb_plv0   [TLBNUM-1:0];
reg [       1:0] tlb_mat0   [TLBNUM-1:0];
reg              tlb_d0     [TLBNUM-1:0];
reg              tlb_v0     [TLBNUM-1:0];
reg [      19:0] tlb_ppn1   [TLBNUM-1:0];
reg [       1:0] tlb_plv1   [TLBNUM-1:0];
reg [       1:0] tlb_mat1   [TLBNUM-1:0];
reg              tlb_d1     [TLBNUM-1:0];
reg              tlb_v1     [TLBNUM-1:0];

wire [TLBNUM-1:0] match, match0, match1;
genvar i;
generate
    for (i = 0; i < TLBNUM; i++) begin
        assign match[i] = (vppn[18:9] == tlb_vppn[i][18:9])
                        && (tlb_ps4MB[i] || vppn[8:0] == tlb_vppn[i][8:0])
                        && (tlb_g[i] || asid == tlb_asid[i])
                        && tlb_e[i];
        assign match0[i] = match[i] && (!vppn[8] || !va_bit12);
        assign match1[i] = match[i] && (vppn[8] || va_bit12);
    end
endgenerate

wire [TLBNUM-1:0] r_select, w_select;
genvar i;
generate
    for (i = 0; i < TLBNUM; i++) begin
        assign r_select[i] = (r_index == i);
        assign w_select[i] = we && (w_index == i);
    end
endgenerate

wire [TLBNUM-1:0] inv_cond1, inv_cond2, inv_cond3, inv_cond4;
wire [TLBNUM-1:0] inv_match;
genvar i;
generate
    for (i = 0; i < TLBNUM; i++) begin
        assign inv_cond1[i] = tlb_g[i] == 1'b0;
        assign inv_cond2[i] = tlb_g[i] == 1'b1;
        assign inv_cond3[i] = (tlb_asid[i] == s1_asid);
        assign inv_cond4[i] = (tlb_vppn[i] == s1_vppn);
        assign inv_match[i] =
            (inv_op == 5'h0) | // clear all
            (inv_op == 5'h1) | // clear all
            (inv_op == 5'h2) & inv_cond2[i] | // clear global
            (inv_op == 5'h3) & inv_cond1[i] | // clear non-global
            (inv_op == 5'h4) & (inv_cond1[i] && inv_cond3[i]) | // clear non-global & asid
            (inv_op == 5'h5) & (inv_cond1[i] && inv_cond3[i] && inv_cond4[i]) | // clear non-global & asid & vppn
            (inv_op == 5'h6) & ((inv_cond2[i] || inv_cond3[i]) && inv_cond4[i]); // clear (global | asid) & vppn
    end
endgenerate

always @(posedge clk) begin
    if (we) begin
        tlb_e <= (tlb_e & ~w_select) | ({TLBNUMLG{w_e}} & w_select);
    end else if (invtlb_valid) begin
        tlb_e <= tlb_e & ~inv_match;
    end
end

always @(posedge clk) begin
    if (we) begin
        tlb_ps4MB <= (tlb_ps4MB & ~w_select) | ({TLBNUMLG{w_ps == 6'd21}} & w_select);
    end
end

genvar i;
generate
    for (i = 0; i < TLBNUM; i++) begin
        always @(posedge clk) begin
            if (we && w_select[i]) begin
                tlb_vppn[i] <= w_vppn;
                tlb_asid[i] <= w_asid;
                tlb_g[i] <= w_g;
                tlb_ppn0[i] <= w_ppn0;
                tlb_plv0[i] <= w_plv0;
                tlb_mat0[i] <= w_mat0;
                tlb_d0[i] <= w_d0;
                tlb_v0[i] <= w_v0;
                tlb_ppn1[i] <= w_ppn1;
                tlb_plv1[i] <= w_plv1;
                tlb_mat1[i] <= w_mat1;
                tlb_d1[i] <= w_d1;
                tlb_v1[i] <= w_v1;
            end
        end
    end
endgenerate

// search port 0 (fetch)

tlb_searcher #(
    .TLBNUM(TLBNUM)
) s0_searcher (
    .tlb_e(tlb_e), .tlb_ps4MB(tlb_ps4MB), .tlb_vppn(tlb_vppn), .tlb_asid(tlb_asid), .tlb_g(tlb_g),
    .tlb_ppn0(tlb_ppn0), .tlb_plv0(tlb_plv0), .tlb_mat0(tlb_mat0), .tlb_d0(tlb_d0), .tlb_v0(tlb_v0),
    .tlb_ppn1(tlb_ppn1), .tlb_plv1(tlb_plv1), .tlb_mat1(tlb_mat1), .tlb_d1(tlb_d1), .tlb_v1(tlb_v1),

    .match(match), .match0(match0), .match1(match1),
    .found(s0_found), .index(s0_index), .ppn(s0_ppn), .ps(s0_ps), .plv(s0_plv), .mat(s0_mat), .d(s0_d), .v(s0_v)
);

// search port 1 (load/store)

tlb_searcher #(
    .TLBNUM(TLBNUM)
) s1_searcher (
    .tlb_e(tlb_e), .tlb_ps4MB(tlb_ps4MB), .tlb_vppn(tlb_vppn), .tlb_asid(tlb_asid), .tlb_g(tlb_g),
    .tlb_ppn0(tlb_ppn0), .tlb_plv0(tlb_plv0), .tlb_mat0(tlb_mat0), .tlb_d0(tlb_d0), .tlb_v0(tlb_v0),
    .tlb_ppn1(tlb_ppn1), .tlb_plv1(tlb_plv1), .tlb_mat1(tlb_mat1), .tlb_d1(tlb_d1), .tlb_v1(tlb_v1),

    .match(match), .match0(match0), .match1(match1),
    .found(s1_found), .index(s1_index), .ppn(s1_ppn), .ps(s1_ps), .plv(s1_plv), .mat(s1_mat), .d(s1_d), .v(s1_v)
);

// read port

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_e_selector (
    .select(r_select),
    .in(tlb_e),
    .out(r_e)
);

selector #(
    .DATA_WIDTH(19),
    .SEL_NUM(TLBNUM)
) r_vppn_selector (
    .select(r_select),
    .in(tlb_vppn),
    .out(r_vppn)
);

selector #(
    .DATA_WIDTH(6),
    .SEL_NUM(TLBNUM)
) r_ps_selector (
    .select(r_select),
    .in(tlb_ps4MB),
    .out(r_ps)
);

selector #(
    .DATA_WIDTH(10),
    .SEL_NUM(TLBNUM)
) r_asid_selector (
    .select(r_select),
    .in(tlb_asid),
    .out(r_asid)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_g_selector (
    .select(r_select),
    .in(tlb_g),
    .out(r_g)
);

selector #(
    .DATA_WIDTH(20),
    .SEL_NUM(TLBNUM)
) r_ppn0_selector (
    .select(r_select),
    .in(tlb_ppn0),
    .out(r_ppn0)
);

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) r_plv0_selector (
    .select(r_select),
    .in(tlb_plv0),
    .out(r_plv0)
);

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) r_mat0_selector (
    .select(r_select),
    .in(tlb_mat0),
    .out(r_mat0)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_d0_selector (
    .select(r_select),
    .in(tlb_d0),
    .out(r_d0)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_v0_selector (
    .select(r_select),
    .in(tlb_v0),
    .out(r_v0)
);

selector #(
    .DATA_WIDTH(20),
    .SEL_NUM(TLBNUM)
) r_ppn1_selector (
    .select(r_select),
    .in(tlb_ppn1),
    .out(r_ppn1)
);

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) r_plv1_selector (
    .select(r_select),
    .in(tlb_plv1),
    .out(r_plv1)
);

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) r_mat1_selector (
    .select(r_select),
    .in(tlb_mat1),
    .out(r_mat1)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_d1_selector (
    .select(r_select),
    .in(tlb_d1),
    .out(r_d1)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) r_v1_selector (
    .select(r_select),
    .in(tlb_v1),
    .out(r_v1)
);

endmodule

