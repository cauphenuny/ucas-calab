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
    output wire         addr_ok,
    output wire         data_ok,
    output wire [31:0]  rdata,

    /* AXI */
    output wire         rd_req,
    output wire [ 2:0]  rd_type, // 3'b000: byte, 3'b001: half, 3'b010: word, 3'b100: cache line
    output wire [31:0]  rd_addr,
    input  wire         rd_rdy,

    input  wire         ret_valid,
    input  wire [ 1:0]  ret_last, // TODO: why width = 2?
    input  wire [31:0]  ret_data,

    output reg          wr_req,
    output wire [ 2:0]  wr_type, // 3'b000: byte, 3'b001: half, 3'b010: word, 3'b100: cache line
    output wire [31:0]  wr_addr,
    output wire [127:0] wr_data,
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

// request buffer
reg is_store;
reg [WIDTH_TAG-1:0] addr_tag;
reg [WIDTH_INDEX-1:0] addr_index;
reg [WIDTH_OFFSET-1:0] addr_offset;

// write buffer
reg [NUM_WAYS-1:0] write_way;
reg [WIDTH_BANK-1:0] write_bank; // addr[3:2]
reg [WIDTH_INDEX-1:0] write_index; // addr[11:4]
reg [3:0] write_strb; // 4'h0 if no write
reg [31:0] write_data;

// replace buffer
reg [WIDTH_BANK-1:0] num_received; // receive new cache-line data from AXI
wire [NUM_WAYS-1:0] replace_way;
reg [WIDTH_TAG-1:0] victim_tag;

// combinational logic data
wire [31:0] way_words[NUM_WAYS-1:0];
wire [31:0] hit_word;

wire [WIDTH_CACHE-1:0] way_lines[NUM_WAYS-1:0];
wire [WIDTH_CACHE-1:0] replace_line;

wire [WIDTH_TAG-1:0] way_tags[NUM_WAYS-1:0];
wire [WIDTH_TAG-1:0] replace_tag;

wire way_valids[NUM_WAYS-1:0];
wire replace_valid;
wire way_dirtys[NUM_WAYS-1:0];
wire replace_dirty;

/***************** ADDRESS DECODE *****************/

wire [WIDTH_BANK-1:0] addr_bank = addr_offset[WIDTH_BANK+1:2];

// effective address that without bank-offset
wire [31-2:0] addr_eff = {addr_tag, addr_index, addr_bank};

wire is_lookup, is_hitwrite, is_replace, is_refill;

/***************** CACHE STORAGES *****************/

wire [NUM_WAYS-1:0] hit_way;
wire [NUM_BANKS-1:0] hit_bank;

decoder #(
    .WIDTH(WIDTH_BANK)
) bank_decoder (
    .in(addr_bank),
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
            end else if (is_hitwrite && write_way[i] && write_index == j) begin
                dirty[j] <= 1'b1;
            end else if (is_refill && replace_way[i] && addr_index == j) begin
                dirty[j] <= 1'b0;
            end
        end
    end
    // TODO: skip replace when not dirty

    // Tag+Valid RAM
    wire [WIDTH_TAG-1:0] rtag, wtag;
    wire rvalid, wvalid;
    wire [WIDTH_INDEX-1:0] tagv_index;
    wire tagv_wen, tagv_en;

    assign wtag = addr_tag;
    assign wvalid = 1'b1;
    assign tagv_index = {WIDTH_INDEX{is_lookup}} & addr_index
                      | {WIDTH_INDEX{is_refill | is_replace}} & addr_index;
    assign tagv_wen = is_refill && (replace_way[i]);
    assign tagv_en = is_lookup
                   | (is_replace && (replace_way[i]))
                   | (is_refill && (replace_way[i]));

    assign hit_way[i] = rvalid && rtag == addr_tag;
    assign way_tags[i] = rtag;
    assign way_valids[i] = rvalid;
    assign way_dirtys[i] = dirty[addr_index];

    /* verilator lint_off MODMISSING */
    cache_tagv_ram tagv_ram(
        .clka(clk),
        .ena(1'b1),
        .wea(tagv_wen),
        .addra(tagv_index),
        .dina({wtag, wvalid}),
        .douta({rtag, rvalid})
    );
    /* verilator lint_on MODMISSING */

    wire [31:0] bank_rdata_array[NUM_BANKS-1:0];

    for (j = 0; j < NUM_BANKS; j = j + 1) begin : bank
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

        assign en = (is_lookup && (addr_bank == j))
                  | (is_hitwrite && (write_way[i]) && (write_bank == j))
                  | (is_replace && (replace_way[i]))
                  | (is_refill && (replace_way[i]));

        wire write_hit = is_hitwrite && (write_way[i]) && (write_bank == j);
        wire write_ref = is_refill && (replace_way[i]) && (num_received == j) && ret_valid;

        assign data_wstrb = {4{write_hit}} & write_strb
                          | {4{write_ref}} & 4'b1111;
        assign data_wdata = {32{write_hit}} & write_data
                          | {32{write_ref}} & ret_data;

        assign data_index = {WIDTH_INDEX{is_lookup}} & addr_index
                          | {WIDTH_INDEX{is_hitwrite}} & write_index
                          | {WIDTH_INDEX{is_replace || is_refill}} & addr_index;

        assign way_lines[i][j*32 +: 32] = data_rdata;

        assign bank_rdata_array[j] = data_rdata;
    end

    selector #(
        .DATA_WIDTH(32),
        .SEL_NUM(NUM_BANKS)
    ) bank_selector (
        .sel(hit_bank),
        .in(bank_rdata_array),
        .out(way_words[i])
    );
end
endgenerate

selector #(
    .DATA_WIDTH(32),
    .SEL_NUM(NUM_WAYS)
) way_word_selector (
    .sel(hit_way),
    .in(way_words),
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

wire need_replace = replace_valid && replace_dirty;

/***************** PROCESSING *****************/

wire hit = |hit_way;

wire load_req = valid & ~op;

// effective addr (ignore address inside bank)
wire [1:0] bank = offset[3:2];
wire [31-2:0] req_addr_eff = {tag, index, bank};

wire write_conflict = (main_state == MAIN_LOOKUP) && is_store && (req_addr_eff == addr_eff) && load_req
                    | (wb_state == WB_WRITE) && (bank == write_bank) && load_req; // FIXME: why not compare index too ?

// request buffer
always @(posedge clk) begin
    if (!resetn) begin
        is_store <= 1'b0;
        addr_tag <= {WIDTH_TAG{1'b0}};
        addr_index <= {WIDTH_INDEX{1'b0}};
        addr_offset <= {WIDTH_OFFSET{1'b0}};
    end else begin
        if (main_next_state == MAIN_LOOKUP) begin
            is_store <= op;
            addr_tag <= tag;
            addr_index <= index;
            addr_offset <= offset;
        end
    end
end

// write buffer
always @(posedge clk) begin
    if (!resetn) begin
        write_way <= {NUM_WAYS{1'b0}};
        write_bank <= {WIDTH_BANK{1'b0}};
        write_index <= {WIDTH_INDEX{1'b0}};
        write_strb <= 4'b0000;
        write_data <= 32'b0;
    end else begin
        if (wb_next_state == WB_WRITE) begin
            write_way <= hit_way;
            write_bank <= addr_bank;
            write_index <= addr_index;
            write_strb <= wstrb;
            write_data <= wdata;
        end
    end
end


// replace buffer
always @(posedge clk) begin
    if (!resetn) begin
        num_received <= 0;
    end else if (repl2ref) begin
        num_received <= 0;
    end else if (is_refill && ret_valid) begin
        num_received <= num_received + 1;
    end
end

wire miss2repl = main_state == MAIN_MISS && main_next_state == MAIN_REPLACE;
wire repl2ref = main_state == MAIN_REPLACE && main_next_state == MAIN_REFILL;

always @(posedge clk) begin
    if (!resetn) begin
        victim_tag <= {WIDTH_TAG{1'b0}};
    end else begin
        if (miss2repl) begin
            victim_tag <= replace_tag;
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
        else if (miss2repl)
            current_replace_way <= ~current_replace_way;
    end
end else begin : widthN
    // >=4-way: LFSR-based pseudo-random
    always @(posedge clk) begin
        if (!resetn)
            current_replace_way <= 'b1; // avoid all-zero lockup
        else if (miss2repl)
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
            if (!hit) begin
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
            if (need_replace && wr_rdy == 1'b0) begin
                main_next_state = MAIN_MISS;
            end else begin
                main_next_state = MAIN_REPLACE; // need replace even if need_replace == 0, to fetch new line
            end
        end
        MAIN_REPLACE: begin
            if (rd_rdy == 1'b0) begin
                main_next_state = MAIN_REPLACE;
            end else begin
                main_next_state = MAIN_REFILL;
            end
        end
        MAIN_REFILL: begin
            if (ret_valid == 1'b1 && ret_last == 2'b1) begin
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
            if (main_state == MAIN_LOOKUP && is_store && hit) begin
                wb_next_state = WB_WRITE;
            end else begin
                wb_next_state = WB_IDLE;
            end
        end
        WB_WRITE: begin
            if (main_state == MAIN_LOOKUP && is_store && hit) begin
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

assign is_lookup = (main_state == MAIN_LOOKUP);
assign is_hitwrite = (wb_state == WB_WRITE);
assign is_replace = (main_state == MAIN_REPLACE);
assign is_refill = (main_state == MAIN_REFILL);

// Simulation-time check: hit_way must be one-hot or all-zero (allow no-hit).
// Use posedge clock to avoid races during combinational updates.
always @(posedge clk) begin
    if (resetn) begin
        assert ($countones(hit_way) <= 1)
        else $fatal("Assertion failed: hit_way has more than one bit set");
        assert ($countones({is_lookup, is_hitwrite, is_replace, is_refill}) <= 1)
        else $fatal("Assertion failed: multiple state in one cycle");
    end
end

/***************** OUTPUT SIGNALS *****************/

assign addr_ok = (main_state == MAIN_IDLE)
               | (main_state == MAIN_LOOKUP && main_next_state == MAIN_LOOKUP);

assign rdata = hit_word;
assign data_ok = (main_state == MAIN_LOOKUP && hit)
               | (main_state == MAIN_LOOKUP && is_store)
               | (main_state == MAIN_REFILL && ret_valid == 1'b1 && num_received == addr_bank);

assign rd_type = AXI_LINE;
assign rd_req = (main_state == MAIN_REPLACE);
assign rd_addr = {addr_tag, addr_index, {WIDTH_OFFSET{1'b0}}};

always @(posedge clk) begin
    if (!resetn) begin
        wr_req <= 1'b0;
    end else begin
        if (miss2repl && need_replace) begin
            wr_req <= 1'b1;
        end else if (wr_rdy == 1'b1) begin
            wr_req <= 1'b0;
        end
    end
end

assign wr_type = AXI_LINE;
assign wr_addr = {victim_tag, addr_index, {WIDTH_OFFSET{1'b0}}};
assign wr_data = replace_line;

endmodule
