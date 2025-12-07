module tlb_searcher #(
    parameter integer TLBNUM = 16
)(
    input wire [TLBNUM-1:0] tlb_e,
    input wire              tlb_ps4MB  [TLBNUM-1:0],
    input wire [      18:0] tlb_vppn   [TLBNUM-1:0],
    input wire [       9:0] tlb_asid   [TLBNUM-1:0],
    input wire              tlb_g      [TLBNUM-1:0],
    input wire [      19:0] tlb_ppn0   [TLBNUM-1:0],
    input wire [       1:0] tlb_plv0   [TLBNUM-1:0],
    input wire [       1:0] tlb_mat0   [TLBNUM-1:0],
    input wire              tlb_d0     [TLBNUM-1:0],
    input wire              tlb_v0     [TLBNUM-1:0],
    input wire [      19:0] tlb_ppn1   [TLBNUM-1:0],
    input wire [       1:0] tlb_plv1   [TLBNUM-1:0],
    input wire [       1:0] tlb_mat1   [TLBNUM-1:0],
    input wire              tlb_d1     [TLBNUM-1:0],
    input wire              tlb_v1     [TLBNUM-1:0],

    input wire match[TLBNUM-1:0],
    input wire match0[TLBNUM-1:0],
    input wire match1[TLBNUM-1:0],

    output wire       found,
    output wire [$clog2(TLBNUM)-1:0] index,
    output wire [19:0] ppn,
    output wire [ 5:0] ps,
    output wire [ 1:0] plv,
    output wire [ 1:0] mat,
    output wire       d,
    output wire       v
);

wire [$clog2(TLBNUM)-1:0] index_array[TLBNUM-1:0];

generate
    for (i = 0; i < TLBNUM; i++) begin
        assign index_array[i] = i;
    end
endgenerate

selector #(
    .DATA_WIDTH($clog2(TLBNUM)),
    .SEL_NUM(TLBNUM)
) index_selector (
    .sel(match),
    .in(index_array),
    .out(index)
);

wire [19:0] ppn0, ppn1;

selector #(
    .DATA_WIDTH(20),
    .SEL_NUM(TLBNUM)
) ppn0_selector (
    .sel(match0),
    .in(tlb_ppn0),
    .out(ppn0)
);
selector #(
    .DATA_WIDTH(20),
    .SEL_NUM(TLBNUM)
) ppn1_selector (
    .sel(match1),
    .in(tlb_ppn1),
    .out(ppn1)
);

wire [1:0] plv0, plv1;

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) plv0_selector (
    .sel(match0),
    .in(tlb_plv0),
    .out(plv0)
);
selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) plv1_selector (
    .sel(match1),
    .in(tlb_plv1),
    .out(plv1)
);

wire [1:0] mat0, mat1;

selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) mat0_selector (
    .sel(match0),
    .in(tlb_mat0),
    .out(mat0)
);
selector #(
    .DATA_WIDTH(2),
    .SEL_NUM(TLBNUM)
) mat1_selector (
    .sel(match1),
    .in(tlb_mat1),
    .out(mat1)
);

wire v0, v1;

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) v0_selector (
    .sel(match0),
    .in(tlb_v0),
    .out(v0)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) v1_selector (
    .sel(match1),
    .in(tlb_v1),
    .out(v1)
);

wire d0, d1;

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) d0_selector (
    .sel(match0),
    .in(tlb_d0),
    .out(d0)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) d1_selector (
    .sel(match1),
    .in(tlb_d1),
    .out(d1)
);

wire ps4MB;

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(TLBNUM)
) ps_selector (
    .sel(match),
    .in(tlb_ps4MB),
    .out(ps)
);

assign found = |match;
assign ppn = ppn0 | ppn1;
assign plv = plv0 | plv1;
assign mat = mat0 | mat1;
assign v = v0 | v1;
assign d = d0 | d1;
// NOTE: 虽然 4MB 是 2^22，但由于被两个物理页均分了，物理页的大小实际上是 2^21
assign ps = ps4MB ? 6'd21 : 6'd12; // 4MB : 4KB

// index assigned in index_selector


endmodule
