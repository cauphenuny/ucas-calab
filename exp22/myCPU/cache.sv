module cache #(
    parameter integer NUM_WAYS = 2
)(
    input wire clk, resetn,

    /* CPU */
    input  wire         valid,
    input  wire         op, // 1: write, 0: read
    input  wire [ 7:0]  index,
    input  wire [19:0]  tag,
    input  wire [ 3:0]  offset,
    input  wire [ 3:0]  wstrb,
    input  wire [31:0]  wdata,
    input  wire         cacheable,
    output wire         addr_ok,
    output wire         data_ok,
    output wire [31:0]  rdata,

    /* AXI */
    output wire         rd_req,
    output wire [ 2:0]  rd_type, // 3'b000: byte, 3'b001: half, 3'b010: word, 3'b100: cache line
    output wire [31:0]  rd_addr,
    input  wire         rd_rdy,

    input  wire         ret_valid,
    input  wire         ret_last,
    input  wire [31:0]  ret_data,

    output reg          wr_req,
    output wire [ 2:0]  wr_type, // 3'b000: byte, 3'b001: half, 3'b010: word, 3'b100: cache line
    output wire [31:0]  wr_addr,
    output wire [127:0] wr_data,
    output wire [3:0]   wr_wstrb,
    input  wire         wr_rdy
);

/* IP interface:

module cache_data_ram (
    input  wire        clka,
    input  wire        ena, // enable
    input  wire [3:0]  wea, // write enable
    input  wire [7:0]  addra, // address, 256 items
    input  wire [31:0] dina, // write data
    output wire [31:0] douta // read data
);

module cache_tagv_ram (
    input  wire        clka,
    input  wire        ena,
    input  wire        wea,
    input  wire [7:0]  addra,
    input  wire [20:0] dina,
    output wire [20:0] douta
);

END IP interface */

localparam WIDTH_TAG    = 20;
localparam WIDTH_OFFSET = 4;
localparam WIDTH_INDEX  = 8;
localparam WIDTH_CACHE = 128; // in bits, cache-line
localparam WIDTH_ELEM  = 8; // 256 cache-lines

localparam NUM_BANKS = (1 << (WIDTH_OFFSET - 2)); // a bank provides 4 bytes
localparam NUM_ELEM = (1 << WIDTH_INDEX); // 256 cache-lines


localparam WIDTH_BANK = $clog2(NUM_BANKS); // 2
localparam WIDTH_WAY = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;

localparam AXI_BYTE = 3'b000;
localparam AXI_HALF = 3'b001;
localparam AXI_WORD = 3'b010;
localparam AXI_LINE = 3'b100;

/***************** STATE MACHINE *****************/

localparam MAIN_IDLE    = 5'b00001;
localparam MAIN_LOOKUP  = 5'b00010;
localparam MAIN_MISS    = 5'b00100;
localparam MAIN_REPLACE = 5'b01000;
localparam MAIN_REFILL  = 5'b10000;

localparam WB_IDLE  = 2'b01;
localparam WB_WRITE = 2'b10;

reg [4:0] main_state, main_next_state;
reg [1:0] wb_state, wb_next_state;

always @(posedge clk) begin
    if (!resetn) begin
        main_state <= MAIN_IDLE;
    end else begin
        main_state <= main_next_state;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        wb_state <= WB_IDLE;
    end else begin
        wb_state <= wb_next_state;
    end
end

/***************** BUFFERS *****************/

// main buffer, a.k.a. request buffer
reg buf_isstore;
reg [WIDTH_TAG-1:0] buf_tag;
reg [WIDTH_INDEX-1:0] buf_index;
reg [WIDTH_OFFSET-1:0] buf_offset;
reg [31:0] buf_wdata;
reg [3:0] buf_wstrb;
reg buf_cacheable;

// write buffer
reg [NUM_WAYS-1:0] wrbuf_way;
reg [WIDTH_BANK-1:0] wrbuf_bank; // addr[3:2]
reg [WIDTH_INDEX-1:0] wrbuf_index; // addr[11:4]
reg [3:0] wrbuf_wstrb; // 4'h0 if no write
reg [31:0] wrbuf_wdata;

// replace buffer
reg [WIDTH_BANK-1:0] rpbuf_numrecv; // receive new cache-line data from AXI
reg [WIDTH_TAG-1:0] rpbuf_tag;
wire [NUM_WAYS-1:0] replace_way;

// combinational logic data
wire [31:0] way_hit_words[NUM_WAYS-1:0];
wire [31:0] hit_word;

wire [31:0] way_refill_words[NUM_WAYS-1:0];
wire [31:0] refill_word;

wire [WIDTH_CACHE-1:0] way_lines[NUM_WAYS-1:0];
wire [WIDTH_CACHE-1:0] replace_line;

wire [WIDTH_TAG-1:0] way_tags[NUM_WAYS-1:0];
wire [WIDTH_TAG-1:0] replace_tag;

wire way_valids[NUM_WAYS-1:0];
wire replace_valid;
wire way_dirtys[NUM_WAYS-1:0];
wire replace_dirty;

/***************** ADDRESS DECODE *****************/

wire [WIDTH_BANK-1:0] bank = offset[WIDTH_BANK+1:2];
wire [WIDTH_BANK-1:0] buf_bank = buf_offset[WIDTH_BANK+1:2];

// effective address that without bank-offset
wire [31-2:0] buf_addr_eff = {buf_tag, buf_index, buf_bank};

wire is_lookup, is_hitwrite, is_replace, is_refill;

// 在 LOOKUP 时使用输入地址，其他状态使用 buffer 地址
wire [WIDTH_INDEX-1:0] lookup_index = is_lookup ? index : buf_index;
wire [WIDTH_TAG-1:0]   lookup_tag   = is_lookup ? tag   : buf_tag;
wire [WIDTH_BANK-1:0]  lookup_bank  = is_lookup ? bank  : buf_bank;

/***************** CACHE STORAGES *****************/

wire [NUM_WAYS-1:0] hit_way;
wire [NUM_BANKS-1:0] hit_bank;

decoder #(
    .WIDTH(WIDTH_BANK)
) bank_decoder (
    .in(buf_bank),
    .out(hit_bank)
);

genvar i, j;
generate
for (i = 0; i < NUM_WAYS; i = i + 1) begin : cache_way
    // Dirty
    reg [NUM_ELEM-1:0] dirty;
    for (j = 0; j < NUM_ELEM; j = j + 1) begin : dirty_bit
        always @(posedge clk) begin
            if (!resetn) begin
                dirty[j] <= 1'b0;
            end else if (is_hitwrite && wrbuf_way[i] && wrbuf_index == j) begin
                dirty[j] <= 1'b1;
            end else if (is_refill && replace_way[i] && buf_cacheable && buf_index == j) begin
                dirty[j] <= 1'b0;
            end
        end
    end

    // Tag+Valid RAM
    wire [WIDTH_TAG-1:0] rtag, wtag;
    wire rvalid, wvalid;
    wire tagv_wen, tagv_en;

    assign wtag = buf_tag;
    assign wvalid = 1'b1;
    assign tagv_wen = is_refill && (replace_way[i]) && buf_cacheable;
    assign tagv_en = is_lookup
                   | (is_replace && (replace_way[i]))
                   | (is_refill && (replace_way[i]));

    assign hit_way[i] = rvalid && rtag == lookup_tag;
    assign way_tags[i] = rtag;
    assign way_valids[i] = rvalid;
    assign way_dirtys[i] = dirty[buf_index];

    /* verilator lint_off MODMISSING */
    cache_tagv_ram tagv_ram(
        .clka(clk),
        .ena(1'b1),
        .wea(tagv_wen),
        .addra(lookup_index),
        .dina({wtag, wvalid}),
        .douta({rtag, rvalid})
    );
    /* verilator lint_on MODMISSING */

    wire [31:0] bank_rdata_array[NUM_BANKS-1:0];
    wire [31:0] bank_refill_array[NUM_BANKS-1:0];

    for (j = 0; j < NUM_BANKS; j = j + 1) begin : gen_bank
        // Bank RAM
        wire en;
        wire [3:0] data_wstrb;
        wire [WIDTH_INDEX-1:0] data_index;
        wire [31:0] data_wdata, data_rdata;

        /* verilator lint_off MODMISSING */
        cache_data_ram data_ram(
            .clka(clk),
            .ena(en),
            .wea(data_wstrb),
            .addra(data_index),
            .dina(data_wdata),
            .douta(data_rdata)
        );
        /* verilator lint_on MODMISSING */

        wire bank_lookup = is_lookup && (lookup_bank == j);
        wire bank_hitwrite = is_hitwrite && (wrbuf_way[i]) && (wrbuf_bank == j) && buf_cacheable;
        wire bank_replace = is_replace && (replace_way[i]); // replace: replace all banks
        wire bank_refill = is_refill && (replace_way[i]) && buf_cacheable;

        always @(posedge clk) begin
            if (resetn) begin
                assert ($countones({bank_lookup, bank_hitwrite, bank_replace, bank_refill}) <= 1)
                else $fatal("Assertion failed: multiple state in one bank");
            end
        end

        assign en = bank_lookup
              | bank_hitwrite
              | bank_refill;

        wire write_hit = bank_hitwrite;
        wire write_ref = bank_refill && (rpbuf_numrecv == j) && ret_valid;

        wire refill_matchstore = (buf_bank == j) && buf_isstore; // Refill + Store: write combined data

        wire [3:0] refill_wstrb = refill_matchstore ? buf_wstrb : 4'b0000; // 1: use wdata, 0: use ret_data

        wire [31:0] refill_mask = {
            {8{refill_wstrb[3]}},
            {8{refill_wstrb[2]}},
            {8{refill_wstrb[1]}},
            {8{refill_wstrb[0]}}
        };

        wire [31:0] refill_data = buf_wdata & refill_mask
                                | ret_data & ~refill_mask;

        assign data_wstrb = {4{write_hit}} & wrbuf_wstrb
                          | {4{write_ref}} & 4'b1111;

        assign data_wdata = {32{write_hit}} & wrbuf_wdata
                          | {32{write_ref}} & refill_data;

        assign data_index = {WIDTH_INDEX{bank_lookup}} & lookup_index
                          | {WIDTH_INDEX{bank_hitwrite}} & wrbuf_index
                          | {WIDTH_INDEX{bank_replace | bank_refill}} & buf_index;

        assign way_lines[i][j*32 +: 32] = data_rdata;

        assign bank_rdata_array[j] = data_rdata;
        assign bank_refill_array[j] = refill_data;
    end

    selector #(
        .DATA_WIDTH(32),
        .SEL_NUM(NUM_BANKS)
    ) bank_selector (
        .sel(hit_bank),
        .in(bank_rdata_array),
        .out(way_hit_words[i])
    );

    selector #(
        .DATA_WIDTH(32),
        .SEL_NUM(NUM_BANKS)
    ) bank_refill_selector (
        .sel(hit_bank),
        .in(bank_refill_array),
        .out(way_refill_words[i])
    );
end
endgenerate

selector #(
    .DATA_WIDTH(32),
    .SEL_NUM(NUM_WAYS)
) way_word_selector (
    .sel(hit_way),
    .in(way_hit_words),
    .out(hit_word)
);

selector #(
    .DATA_WIDTH(WIDTH_CACHE),
    .SEL_NUM(NUM_WAYS)
) way_line_selector (
    .sel(replace_way),
    .in(way_lines),
    .out(replace_line)
);

selector #(
    .DATA_WIDTH(WIDTH_TAG),
    .SEL_NUM(NUM_WAYS)
) way_victimtag_selector (
    .sel(replace_way),
    .in(way_tags),
    .out(replace_tag)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(NUM_WAYS)
) way_victimvalid_selector (
    .sel(replace_way),
    .in(way_valids),
    .out(replace_valid)
);

selector #(
    .DATA_WIDTH(1),
    .SEL_NUM(NUM_WAYS)
) way_victimdirty_selector (
    .sel(replace_way),
    .in(way_dirtys),
    .out(replace_dirty)
);

selector #(
    .DATA_WIDTH(32),
    .SEL_NUM(NUM_WAYS)
) way_refillword_selector (
    .sel(replace_way),
    .in(way_refill_words),
    .out(refill_word)
);

wire need_writeback = replace_valid && replace_dirty && buf_cacheable;

/***************** PROCESSING *****************/

wire hit = |hit_way;
wire effective_hit = hit && buf_cacheable;

// effective addr (ignore address inside bank)
wire [31-2:0] next_addr_eff = {tag, index, bank};
wire next_isload = valid & ~op;

wire write_conflict = (main_state == MAIN_LOOKUP) && buf_isstore && (buf_addr_eff == next_addr_eff) && next_isload
                    | (wb_state == WB_WRITE) && (bank == wrbuf_bank) && next_isload;

// request buffer
always @(posedge clk) begin
    if (!resetn) begin
        buf_isstore <= 1'b0;
        buf_tag <= {WIDTH_TAG{1'b0}};
        buf_index <= {WIDTH_INDEX{1'b0}};
        buf_offset <= {WIDTH_OFFSET{1'b0}};
        buf_wdata <= 32'h0;
        buf_wstrb <= 4'h0;
        buf_cacheable <= 1'b0;
    end else if (valid && addr_ok && !write_conflict) begin
        // 在握手时锁存请求，确保 miss/refill 期间 PC 变化不会污染当前 miss 的地址
        buf_isstore <= op;
        buf_tag <= tag;
        buf_index <= index;
        buf_offset <= offset;
        buf_wdata <= wdata;
        buf_wstrb <= wstrb;
        buf_cacheable <= cacheable;
    end
end

// write buffer
always @(posedge clk) begin
    if (!resetn) begin
        wrbuf_way <= {NUM_WAYS{1'b0}};
        wrbuf_bank <= {WIDTH_BANK{1'b0}};
        wrbuf_index <= {WIDTH_INDEX{1'b0}};
        wrbuf_wstrb <= 4'b0000;
        wrbuf_wdata <= 32'b0;
    end else begin
        if (wb_next_state == WB_WRITE && buf_cacheable) begin
            wrbuf_way <= hit_way;
            wrbuf_bank <= buf_bank;
            wrbuf_index <= buf_index;
            wrbuf_wstrb <= buf_wstrb;
            wrbuf_wdata <= buf_wdata;
        end
    end
end

// replace buffer
always @(posedge clk) begin
    if (!resetn) begin
        rpbuf_numrecv <= 0;
    end else if (repl2ref) begin
        rpbuf_numrecv <= 0;
    end else if (is_refill && ret_valid && buf_cacheable) begin
        rpbuf_numrecv <= rpbuf_numrecv + 1;
    end
end

wire miss2repl = main_state == MAIN_MISS && main_next_state == MAIN_REPLACE;
wire repl2ref = main_state == MAIN_REPLACE && main_next_state == MAIN_REFILL;
wire lookup2miss = main_state == MAIN_LOOKUP && main_next_state == MAIN_MISS;

always @(posedge clk) begin
    if (!resetn) begin
        rpbuf_tag <= {WIDTH_TAG{1'b0}};
    end else begin
        if (miss2repl) begin
            rpbuf_tag <= replace_tag;
        end
    end
end

/***************** LFSR *****************/

reg [WIDTH_WAY-1:0] current_replace_way;

generate
if (WIDTH_WAY == 1) begin : width1
    // 2-way cache: simple toggle (optimal)
    always @(posedge clk) begin
        if (!resetn)
            current_replace_way <= 1'b0;
        else if (lookup2miss)
            current_replace_way <= ~current_replace_way;
    end
end else begin : widthN
    // >=4-way: LFSR-based pseudo-random
    always @(posedge clk) begin
        if (!resetn)
            current_replace_way <= 'b1; // avoid all-zero lockup
        else if (lookup2miss)
            current_replace_way <= {
                current_replace_way[WIDTH_WAY-2:0],
                ^current_replace_way
            };
    end
end
endgenerate

decoder #(
    .WIDTH(WIDTH_WAY)
) repl_way_decoder (
    .in(current_replace_way),
    .out(replace_way)
);

/***************** STATE TRANSFER *****************/

always @(*) begin
    case (main_state)
        MAIN_IDLE: begin
            if (valid && (!write_conflict)) begin
                main_next_state = MAIN_LOOKUP;
            end else begin
                main_next_state = MAIN_IDLE;
            end
        end
        MAIN_LOOKUP: begin
            if (!effective_hit) begin
                main_next_state = MAIN_MISS;
            end else begin
                if (!valid || write_conflict) begin
                    main_next_state = MAIN_IDLE;
                end else begin
                    main_next_state = MAIN_LOOKUP;
                end
            end
        end
        MAIN_MISS: begin
            if (need_writeback && wr_rdy == 1'b0) begin
                main_next_state = MAIN_MISS;
            end else begin
                main_next_state = MAIN_REPLACE; // need replace even if need_writeback == 0, to fetch new line
            end
        end
        MAIN_REPLACE: begin
            if (uncached_store) begin
                if (wr_rdy == 1'b0)
                    main_next_state = MAIN_REPLACE;
                else
                    main_next_state = MAIN_IDLE;
            end else begin
                if (rd_rdy == 1'b0) begin
                    main_next_state = MAIN_REPLACE;
                end else begin
                    main_next_state = MAIN_REFILL;
                end
            end
        end
        MAIN_REFILL: begin
            if (ret_valid == 1'b1 && ret_last == 1'b1) begin
                main_next_state = MAIN_IDLE;
            end else begin
                main_next_state = MAIN_REFILL;
            end
        end
        default: begin
            main_next_state = MAIN_IDLE;
        end
    endcase
end

always @(*) begin
    case (wb_state)
        WB_IDLE: begin
            if (main_state == MAIN_LOOKUP && buf_isstore && effective_hit) begin
                wb_next_state = WB_WRITE;
            end else begin
                wb_next_state = WB_IDLE;
            end
        end
        WB_WRITE: begin
            if (main_state == MAIN_LOOKUP && buf_isstore && effective_hit) begin
                wb_next_state = WB_WRITE;
            end else begin
                wb_next_state = WB_IDLE;
            end
        end
        default: begin
            wb_next_state = WB_IDLE;
        end
    endcase
end

/***************** STATE SIGNALS *****************/

assign is_lookup = (main_next_state == MAIN_LOOKUP);
assign is_hitwrite = (wb_state == WB_WRITE);
assign is_replace = (main_state == MAIN_REPLACE);
assign is_refill = (main_state == MAIN_REFILL);

// Simulation-time check: hit_way must be one-hot or all-zero (allow no-hit).
// Use posedge clock to avoid races during combinational updates.
always @(posedge clk) begin
    if (resetn) begin
        assert ($countones(hit_way) <= 1)
        else $fatal("Assertion failed: hit_way has more than one bit set");
    end
end

/***************** OUTPUT SIGNALS *****************/

assign addr_ok = (main_state == MAIN_IDLE && valid && !write_conflict)
               | (main_state == MAIN_LOOKUP && valid && !write_conflict && (effective_hit || !buf_cacheable));

assign rdata = {32{main_state == MAIN_LOOKUP}} & hit_word
             | {32{main_state == MAIN_REFILL}} & refill_word;

wire uncached_store_ok = (main_state == MAIN_REPLACE) && buf_isstore && !buf_cacheable && wr_rdy;
wire refill_data_ok = (main_state == MAIN_REFILL) && ret_valid && ~buf_isstore
                && (buf_cacheable ? (rpbuf_numrecv == buf_bank) : 1'b1);

assign data_ok = (main_state == MAIN_LOOKUP && effective_hit)
               | (main_state == MAIN_LOOKUP && buf_isstore && buf_cacheable)
               | refill_data_ok
               | uncached_store_ok;

wire uncached_store = buf_isstore && !buf_cacheable;
wire uncached_load  = (~buf_isstore) && !buf_cacheable;

assign rd_type = buf_cacheable ? AXI_LINE : AXI_WORD;
assign rd_req = (main_state == MAIN_REPLACE) && ~uncached_store;
assign rd_addr = buf_cacheable ? {buf_tag, buf_index, {WIDTH_OFFSET{1'b0}}}
                               : {buf_tag, buf_index, buf_offset};

always @(posedge clk) begin
    if (!resetn) begin
        wr_req <= 1'b0;
    end else begin
        if (miss2repl && (need_writeback || uncached_store)) begin
            wr_req <= 1'b1;
        end else if (wr_rdy == 1'b1) begin
            wr_req <= 1'b0;
        end
    end
end

function [2:0] store_axi_type;
    input [3:0] strb;
    begin
        case (strb)
            4'b1111: store_axi_type = AXI_WORD;
            4'b0011,
            4'b1100: store_axi_type = AXI_HALF;
            default: store_axi_type = AXI_BYTE;
        endcase
    end
endfunction

assign wr_type = buf_cacheable ? AXI_LINE : store_axi_type(buf_wstrb);
assign wr_addr = buf_cacheable ? {rpbuf_tag, buf_index, {WIDTH_OFFSET{1'b0}}}
                               : {buf_tag, buf_index, buf_offset};
assign wr_data = buf_cacheable ? replace_line : {96'h0, buf_wdata};
assign wr_wstrb = buf_cacheable ? 4'b1111 : buf_wstrb;

endmodule
