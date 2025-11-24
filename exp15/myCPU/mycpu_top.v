`timescale 10ns / 1ps

module mycpu_top(
    input  wire        aclk,
    input  wire        aresetn,
    // AXI AR
    output wire [3:0]  arid,
    output wire [31:0] araddr,
    output wire [7:0]  arlen,
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,
    output wire [1:0]  arlock,
    output wire [3:0]  arcache,
    output wire [2:0]  arprot,
    output wire        arvalid,
    input  wire        arready,
    // AXI R
    input  wire [3:0]  rid,
    input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,
    // AXI AW
    output wire [3:0]  awid,
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,
    output wire [1:0]  awlock,
    output wire [3:0]  awcache,
    output wire [2:0]  awprot,
    output wire        awvalid,
    input  wire        awready,
    // AXI W
    output wire [3:0]  wid,
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    // AXI B
    input  wire [3:0]  bid,
    input  wire [1:0]  bresp,
    input  wire        bvalid,
    output wire        bready,
    // debug
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    reg         rst;
    always @(posedge clk) rst <= ~resetn;

/************ sram axi bridge ************/
    wire clk = aclk;
    wire resetn = aresetn;

    // inst sram interface
    wire        inst_sram_req;
    wire        inst_sram_wr;
    wire [1:0]  inst_sram_size;
    wire [31:0] inst_sram_addr;
    wire [ 3:0] inst_sram_wstrb;
    wire [31:0] inst_sram_wdata;
    wire        inst_sram_addr_ok;
    wire        inst_sram_data_ok;
    wire [31:0] inst_sram_rdata;

    // data sram interface
    wire        data_sram_req;
    wire        data_sram_wr;
    wire [1:0]  data_sram_size;
    wire [31:0] data_sram_addr;
    wire [ 3:0] data_sram_wstrb;
    wire [31:0] data_sram_wdata;
    wire        data_sram_addr_ok;
    wire        data_sram_data_ok;
    wire [31:0] data_sram_rdata;

    sram_axi_bridge u_bridge(
        .aclk(aclk), .aresetn(aresetn),

        .inst_req(inst_sram_req), .inst_wr(inst_sram_wr), .inst_size(inst_sram_size),
        .inst_addr(inst_sram_addr), .inst_wstrb(inst_sram_wstrb), .inst_wdata(inst_sram_wdata),
        .inst_addr_ok(inst_sram_addr_ok), .inst_data_ok(inst_sram_data_ok), .inst_rdata(inst_sram_rdata),

        .data_req(data_sram_req), .data_wr(data_sram_wr), .data_size(data_sram_size),
        .data_addr(data_sram_addr), .data_wstrb(data_sram_wstrb), .data_wdata(data_sram_wdata),
        .data_addr_ok(data_sram_addr_ok), .data_data_ok(data_sram_data_ok), .data_rdata(data_sram_rdata),

        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arlock(arlock), .arcache(arcache), .arprot(arprot), .arvalid(arvalid), .arready(arready),

        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),

        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awlock(awlock), .awcache(awcache), .awprot(awprot), .awvalid(awvalid), .awready(awready),

        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),

        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

/**************** IF stage ****************/
    wire [31:0] seq_pc, br_target, flush_pc;
    reg  [31:0] pc, next_pc;
    wire        br_taken;
    wire        flush = (wb_ex | ertn_flush | br_taken);
    reg         flushed;

    // pre-IF to IF
    wire        if_allowin;
    wire        if_allowout;
    wire        if_refreshing;
    wire        if_validin;
    wire        if_validout;

    // IF to ID
    wire        if_ex_valid;
    wire [ 5:0] if_ecode;
    wire [ 8:0] if_esubcode;
    wire        if_is_csr;
    wire        if_csr_en;
    wire        if_csr_we;
    wire [13:0] if_csr_num;
    wire [31:0] if_csr_wmask;
    wire [31:0] if_csr_wvalue;
    wire [31:0] if_pc;
    wire [31:0] if_inst;

    wire addr_sending;

    assign seq_pc = pc + 32'h4;
    assign flush_pc = ertn_flush ? ex_ra :
                      wb_ex ? ex_entry :
                      br_target;

    localparam ENTRYPOINT = 32'h1c000000;

    always @(posedge clk) begin
        if (rst)
            next_pc <= ENTRYPOINT + 4;
        else if (flush) begin
            if (if_refreshing)
                next_pc <= flush_pc + 4;
            else
                next_pc <= flush_pc;
        end
        else if (if_refreshing)
            next_pc <= next_pc + 4;
    end

    always @(posedge clk) begin
        if (rst) begin
            pc <= ENTRYPOINT;
        end else if (if_refreshing) begin
            if (flush) begin
                pc <= flush_pc;
            end else begin
                pc <= next_pc;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            flushed <= 1'b0;
        end else if (if_refreshing) begin
            flushed <= 1'b0;
        end else if (flush) begin
            flushed <= 1'b1;
        end
    end

    reg addr_sent;
    assign addr_sending = inst_sram_req & inst_sram_addr_ok;

    always @(posedge clk) begin
        if (rst) begin
            addr_sent <= 1'b0;
        end else if (if_refreshing) begin
            addr_sent <= 1'b0;
        end else if (addr_sending) begin
            addr_sent <= 1'b1;
        end
    end

    assign if_validin = addr_sent;
    assign inst_sram_req = ~addr_sent;
    assign inst_sram_addr = pc;
    assign inst_sram_wr = 1'b0;
    assign inst_sram_size = 2'b10; // word
    assign inst_sram_wstrb = 4'b0;
    assign inst_sram_wdata = 32'h0;

    stage_if u_stage_if(
        .clk(clk),
        .rst(rst),
        .allowin(if_allowin),
        .validin(if_validin),
        .validout(if_validout),
        .allowout(if_allowout),
        .cancelin(flush | flushed),
        .cancelout(flush),

        .input_pc(pc),
        .output_pc(if_pc),
        .output_inst(if_inst),

        .output_ecode(if_ecode),
        .output_esubcode(if_esubcode),
        .output_is_csr(if_is_csr),
        .output_csr_en(if_csr_en),
        .output_csr_we(if_csr_we),
        .output_csr_num(if_csr_num),
        .output_csr_wmask(if_csr_wmask),
        .output_csr_wvalue(if_csr_wvalue),
        .output_ex_valid(if_ex_valid),

        // .inst_sram_req(inst_sram_req),
        // .inst_sram_wr(inst_sram_wr),
        // .inst_sram_size(inst_sram_size),
        // .inst_sram_addr(inst_sram_addr),
        // .inst_sram_wstrb(inst_sram_wstrb),
        // .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata),
        // .inst_sram_addr_ok(inst_sram_addr_ok),
        .inst_sram_data_ok(inst_sram_data_ok)
    );

    assign if_refreshing = if_allowin && if_validin;

/**************** other units ****************/

    wire [ 4:0] rf_raddr1, rf_raddr2, rf_waddr;
    wire [31:0] raw_rf_rdata1, raw_rf_rdata2, rf_wdata; // NOTE: raw_*: data directly outputed by RF
    wire [31:0] rf_rdata1, rf_rdata2; // NOTE: considering data forwarding, passed to ID stage
    wire rf_we;

    regfile u_regfile(
        .clk    (clk      ),
        .raddr1 (rf_raddr1),
        .rdata1 (raw_rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (raw_rf_rdata2),
        .we     (rf_we    ),
        .waddr  (rf_waddr ),
        .wdata  (rf_wdata )
    );

    wire [13:0]  csr_num;      // write selector from WB
    wire [31:0]  csr_rvalue;   // async read data to ID
    wire         csr_we;
    wire [31:0]  csr_wmask;
    wire [31:0]  csr_wvalue;
    wire         wb_ex;
    wire [ 5:0]  wb_ecode;
    wire [ 8:0]  wb_esubcode;
    wire         ertn_flush;
    wire [31:0]  ex_entry;
    wire [31:0]  ex_ra;
    wire [12:0]  intr_stat;

    csr u_csr(
        .clk        (clk),
        .rst        (rst),

        .csr_rnum   (id_csr_num),
        .csr_wnum   (csr_num),
        .csr_rvalue (csr_rvalue),
        .csr_we     (csr_we),
        .csr_wmask  (csr_wmask),
        .csr_wvalue (csr_wvalue),

        .wb_ex      (wb_ex),
        .wb_pc      (wb_pc),
        .wb_ecode   (wb_ecode),
        .wb_esubcode(wb_esubcode),
        .ertn_flush (ertn_flush),
        .intr_stat  (intr_stat),
        .ex_entry   (ex_entry),
        .ex_ra      (ex_ra)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off ASSIGNIN */

    wire ex_wen = u_stage_ex.valid && u_stage_ex.output_rf_we && u_stage_ex.output_rf_waddr != 5'h0;
    wire mem_wen = u_stage_mem.valid && u_stage_mem.output_rf_we && u_stage_mem.output_rf_waddr != 5'h0;
    wire wb_wen = u_stage_wb.valid && u_stage_wb.output_rf_we && u_stage_wb.output_rf_waddr != 5'h0;

    wire hazard_ex1 = ex_wen && (u_stage_ex.output_rf_waddr == rf_raddr1);
    wire hazard_ex2 = ex_wen && (u_stage_ex.output_rf_waddr == rf_raddr2);
    wire hazard_mem1 = mem_wen && (u_stage_mem.output_rf_waddr == rf_raddr1);
    wire hazard_mem2 = mem_wen && (u_stage_mem.output_rf_waddr == rf_raddr2);
    wire hazard_wb1 = wb_wen && (u_stage_wb.output_rf_waddr == rf_raddr1);
    wire hazard_wb2 = wb_wen && (u_stage_wb.output_rf_waddr == rf_raddr2);
    wire [31:0] ex_forward_data;
    wire [31:0] mem_forward_data;
    wire [31:0] wb_forward_data;
    wire ex_forward_ready;
    wire mem_forward_ready;
    wire wb_forward_ready;

    assign rf_rdata1 = hazard_ex1 ? ex_forward_data :
                       hazard_mem1 ? mem_forward_data :
                       hazard_wb1 ? wb_forward_data :
                       raw_rf_rdata1;

    assign rf_rdata2 = hazard_ex2 ? ex_forward_data :
                       hazard_mem2 ? mem_forward_data :
                       hazard_wb2 ? wb_forward_data :
                       raw_rf_rdata2;

    // CSR hazard: results are only available at WB (no forwarding). If a CSR writer
    // is in EX/MEM, treat it as not-ready and stall the reader in ID.
    wire ex_ready_for_id  = u_stage_ex.output_is_csr  ? 1'b0 : ex_forward_ready;
    wire mem_ready_for_id = u_stage_mem.output_is_csr ? 1'b0 : mem_forward_ready;

    wire id_stall1 = hazard_ex1 ? ~ex_ready_for_id :
                     hazard_mem1 ? ~mem_ready_for_id :
                     hazard_wb1 ? ~wb_forward_ready :
                     1'b0;

    wire id_stall2 = hazard_ex2 ? ~ex_ready_for_id :
                     hazard_mem2 ? ~mem_ready_for_id :
                     hazard_wb2 ? ~wb_forward_ready :
                     1'b0;

    // CSR write-after-read hazard: if ID is CSR op and earlier stage will write the same CSR,
    // stall until that write commits in WB (no forwarding for CSR state changes).
    wire csr_hazard_ex  = u_stage_ex.valid  & ex_csr_we  & (ex_csr_num  == id_csr_num);
    wire csr_hazard_mem = u_stage_mem.valid & mem_csr_we & (mem_csr_num == id_csr_num);
    wire csr_hazard_wb  = wb_valid & csr_we & (csr_num == id_csr_num);
    wire id_stall_csr   = id_is_csr & (csr_hazard_ex | csr_hazard_mem | csr_hazard_wb);

    wire id_stall = id_stall1 | id_stall2 | id_stall_csr;

    // Exception info
    wire        id_ex_valid;
    wire [5:0]  id_ecode;
    wire [8:0]  id_esubcode;
    wire        ex_ex_valid;
    wire [5:0]  ex_ecode;
    wire [8:0]  ex_esubcode;
    wire        mem_ex_valid;
    wire [5:0]  mem_ecode;
    wire [8:0]  mem_esubcode;
    wire        wb_ex_valid;

    // CSR bundle
    wire        id_csr_en;
    wire [13:0] id_csr_num;
    wire        id_csr_we;
    wire [31:0] id_csr_wmask;
    wire [31:0] id_csr_wvalue;
    wire        ex_csr_en;
    wire [13:0] ex_csr_num;
    wire        ex_csr_we;
    wire [31:0] ex_csr_wmask;
    wire [31:0] ex_csr_wvalue;
    wire        mem_csr_en;
    wire [13:0] mem_csr_num;
    wire        mem_csr_we;
    wire [31:0] mem_csr_wmask;
    wire [31:0] mem_csr_wvalue;

    // ERTN flags
    wire        id_is_ertn;
    wire        ex_is_ertn;
    wire        mem_is_ertn;

    // CSR value/flag
    wire        id_is_csr;
    wire        ex_is_csr;
    wire        mem_is_csr;
    wire [31:0] id_csr_rvalue;
    wire [31:0] ex_csr_rvalue;
    wire [31:0] mem_csr_rvalue;
    
    // br_stall: 转移指令计算未完成，阻塞取指
    wire        br_stall;

    stage_id u_stage_id(
        .clk(clk),
        .rst(rst),
        .validin(if_validout),
        .allowin(if_allowout),
        .validout(),
        .allowout(),
        .stall(id_stall),
        .cancel(wb_ex | ertn_flush),

        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),

        .input_pc(if_pc),
        .input_inst(if_inst),

        .output_pc(),
        .output_br_target(br_target),
        .output_br_taken(br_taken),
        .br_stall(br_stall),        // 连接 br_stall 信号
        .output_alu_src1(),
        .output_alu_src2(),
        .output_alu_op(),

        .output_mem_data(),
        .output_mem_read(),
        .output_mem_op_ld(),
        .output_mem_write(),
        .output_mem_op_st(),

        .output_rf_waddr(),
        .output_rf_we(),

        .input_ex_valid(if_ex_valid),
        .input_ecode(if_ecode),
        .input_esubcode(if_esubcode),

        .input_is_csr(if_is_csr),
        .input_csr_en(if_csr_en),
        .input_csr_num(if_csr_num),
        .input_csr_we(if_csr_we),
        .input_csr_wmask(if_csr_wmask),
        .input_csr_wvalue(if_csr_wvalue),

        .output_csr_en(id_csr_en),
        .output_csr_num(id_csr_num),
        .output_csr_we(id_csr_we),
        .output_csr_wmask(id_csr_wmask),
        .output_csr_wvalue(id_csr_wvalue),

        .csr_rvalue(csr_rvalue),
        .intr_stat(intr_stat),
        .output_is_csr(id_is_csr),
        .output_csr_rvalue(id_csr_rvalue),

        .output_is_ertn(id_is_ertn),

        .output_ex_valid(id_ex_valid),
        .output_ecode(id_ecode),
        .output_esubcode(id_esubcode)
    );

    stage_ex u_stage_ex(
        .clk(clk),
        .rst(rst),
        .validin(u_stage_id.validout),
        .allowin(u_stage_id.allowout),
        .validout(),
        .allowout(),
        .cancel(wb_ex | ertn_flush),

        .input_pc(u_stage_id.output_pc),
        .input_alu_src1(u_stage_id.output_alu_src1),
        .input_alu_src2(u_stage_id.output_alu_src2),
        .input_alu_op(u_stage_id.output_alu_op),

        .input_rf_waddr(u_stage_id.output_rf_waddr),
        .input_rf_we(u_stage_id.output_rf_we),

        .input_mem_data(u_stage_id.output_mem_data),
        .input_mem_read(u_stage_id.output_mem_read),
        .input_mem_op_ld(u_stage_id.output_mem_op_ld),
        .input_mem_write(u_stage_id.output_mem_write),
        .input_mem_op_st(u_stage_id.output_mem_op_st),

        .output_pc(),
        .output_rf_waddr(),
        .output_rf_we(),
        .output_mem_read(),
        .output_mem_op_ld(),
        .output_is_mem_op(),
        .output_mem_write(),
        .output_alu_result(),

        .input_ex_valid(id_ex_valid),
        .input_ecode(id_ecode),
        .input_esubcode(id_esubcode),
        .output_ex_valid(ex_ex_valid),
        .output_ecode(ex_ecode),
        .output_esubcode(ex_esubcode),

        .input_csr_en(id_csr_en),
        .input_csr_num(id_csr_num),
        .input_csr_we(id_csr_we),
        .input_csr_wmask(id_csr_wmask),
        .input_csr_wvalue(id_csr_wvalue),
        .output_csr_en(ex_csr_en),
        .output_csr_num(ex_csr_num),
        .output_csr_we(ex_csr_we),
        .output_csr_wmask(ex_csr_wmask),
        .output_csr_wvalue(ex_csr_wvalue),

        .input_is_ertn(id_is_ertn),
        .output_is_ertn(ex_is_ertn),

        .input_is_csr(id_is_csr),
        .input_csr_rvalue(id_csr_rvalue),
        .output_is_csr(ex_is_csr),
        .output_csr_rvalue(ex_csr_rvalue),

        .forward_data(ex_forward_data),
        .forward_ready(ex_forward_ready),

        .older_ex(mem_ex_valid | wb_ex),
        .older_ertn(mem_is_ertn | ertn_flush),

        .data_sram_req(data_sram_req),
        .data_sram_wr(data_sram_wr),
        .data_sram_size(data_sram_size),
        .data_sram_addr(data_sram_addr),
        .data_sram_wstrb(data_sram_wstrb),
        .data_sram_wdata(data_sram_wdata),
        .data_sram_addr_ok(data_sram_addr_ok)
    );

    stage_mem u_stage_mem(
        .clk(clk),
        .rst(rst),
        .validin(u_stage_ex.validout),
        .allowin(u_stage_ex.allowout),
        .validout(),
        .allowout(),
        .cancel(wb_ex | ertn_flush),

        .input_pc(u_stage_ex.output_pc),
        .output_pc(),

        .input_rf_waddr(u_stage_ex.output_rf_waddr),
        .input_rf_we(u_stage_ex.output_rf_we),
        .output_rf_waddr(),
        .output_rf_wdata(),
        .output_rf_we(),

        .input_mem_read(u_stage_ex.output_mem_read),
        .input_mem_write(u_stage_ex.output_mem_write),
        .input_alu_result(u_stage_ex.output_alu_result),

        .forward_data(mem_forward_data),
        .input_mem_op_ld(u_stage_ex.output_mem_op_ld),
        .forward_ready(mem_forward_ready),

        .input_csr_en(ex_csr_en),
        .input_csr_num(ex_csr_num),
        .input_csr_we(ex_csr_we),
        .input_csr_wmask(ex_csr_wmask),
        .input_csr_wvalue(ex_csr_wvalue),
        .output_csr_en(mem_csr_en),
        .output_csr_num(mem_csr_num),
        .output_csr_we(mem_csr_we),
        .output_csr_wmask(mem_csr_wmask),
        .output_csr_wvalue(mem_csr_wvalue),

        .input_ex_valid(ex_ex_valid),
        .input_ecode(ex_ecode),
        .input_esubcode(ex_esubcode),
        .output_ex_valid(mem_ex_valid),
        .output_ecode(mem_ecode),
        .output_esubcode(mem_esubcode),

        .input_is_ertn(ex_is_ertn),
        .output_is_ertn(mem_is_ertn),

        .input_is_csr(ex_is_csr),
        .input_csr_rvalue(ex_csr_rvalue),
        .output_is_csr(mem_is_csr),
        .output_csr_rvalue(mem_csr_rvalue),

    .data_sram_rdata(data_sram_rdata),
    .data_sram_data_ok(data_sram_data_ok)
    );

    wire        wb_valid;
    wire        wb_rf_we;
    wire [ 4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    wire [31:0] wb_pc;

    stage_wb u_stage_wb(
        .clk(clk),
        .rst(rst),
        .allowin(u_stage_mem.allowout),
        .validin(u_stage_mem.validout),
        .allowout(1'b1),
        .validout(wb_valid),

        .input_pc(u_stage_mem.output_pc),
        .output_pc(wb_pc),

        .input_rf_waddr(u_stage_mem.output_rf_waddr),
        .input_rf_wdata(u_stage_mem.output_rf_wdata),
        .input_rf_we(u_stage_mem.output_rf_we),
        .input_csr_en(mem_csr_en),
        .input_csr_num(mem_csr_num),
        .input_csr_we(mem_csr_we),
        .input_csr_wmask(mem_csr_wmask),
        .input_csr_wvalue(mem_csr_wvalue),
        .input_is_ertn(mem_is_ertn),
        .input_is_csr(mem_is_csr),
        .input_csr_rvalue(mem_csr_rvalue),
        .input_ex_valid(mem_ex_valid),
        .input_ecode(mem_ecode),
        .input_esubcode(mem_esubcode),

        .output_rf_waddr(wb_rf_waddr),
        .output_rf_wdata(wb_rf_wdata),
        .output_rf_we(wb_rf_we),

        .forward_data(wb_forward_data),
        .forward_ready(wb_forward_ready),

        .rf_we(rf_we),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata),

        .csr_wnum(csr_num),
        .csr_we(csr_we),
        .csr_wmask(csr_wmask),
        .csr_wvalue(csr_wvalue),
        .ertn_flush(ertn_flush),
        .wb_ex_valid(wb_ex_valid),
        .wb_ecode(wb_ecode),
        .wb_esubcode(wb_esubcode)
    );
    assign wb_ex = wb_ex_valid;

    /* verilator lint_on PINCONNECTEMPTY */
    /* verilator lint_on ASSIGNIN */

    assign inst_sram_wstrb = 4'h0;
    assign inst_sram_wr = (|inst_sram_wstrb);
    assign inst_sram_wdata = 32'h0;

    assign debug_wb_pc       = wb_pc;
    assign debug_wb_rf_we    = {4{wb_rf_we & wb_valid}};
    assign debug_wb_rf_wnum  = wb_rf_waddr;
    assign debug_wb_rf_wdata = wb_rf_wdata;

endmodule
