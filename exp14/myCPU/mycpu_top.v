`timescale 10ns / 1ps

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output reg         inst_sram_req,
    output wire        inst_sram_wr,
    output wire [1:0]  inst_sram_size,
    output reg  [31:0] inst_sram_addr,
    output wire [ 3:0] inst_sram_wstrb,
    output wire [31:0] inst_sram_wdata,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_req,
    output wire        data_sram_wr,
    output wire [1:0]  data_sram_size,
    output wire [31:0] data_sram_addr,
    output wire [ 3:0] data_sram_wstrb,
    output wire [31:0] data_sram_wdata,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    reg         rst;
    always @(posedge clk) rst <= ~resetn;

/**************** IF stage ****************/
    wire        fs_allowin;
    wire        pre_if_ready_go;

    reg         if_valid;   // IF级是否有尚未下发的指令
    reg  [31:0] if_inst_buf;  // 指令缓存
    reg         if_inst_buf_valid; // 指令缓存是否有效
    reg         if_need_drop; // 是否需要丢弃下一个返回的指令
    wire        if_ready_go; // IF级是否ready

    wire [31:0] nextpc, seq_pc, br_target;
    reg  [31:0] pc;
    wire        br_taken, id_refreshing;
    wire        flush = (wb_ex | ertn_flush);
    wire        if_allowout;
    wire        if_validout = if_valid & if_ready_go;
    wire        if_ex_valid;
    wire [ 5:0] if_ecode;
    wire [ 8:0] if_esubcode;
    wire        if_is_csr;
    wire        if_csr_en;
    wire        if_csr_we;
    wire [13:0] if_csr_num;
    wire [31:0] if_csr_wmask;
    wire [31:0] if_csr_wvalue;
    reg         if_ex_adef; // ADEF exception
    wire        if_next_ex_adef;

    assign id_refreshing = if_allowout & if_validout;
    assign seq_pc        = pc + 32'h4;
    assign nextpc        = br_pending ? br_target_buf :
                           first_fetch ? pc : 
                           (ertn_flush ? ex_ra : 
                           (wb_ex ? ex_entry : 
                           (br_taken ? br_target : seq_pc)));

    assign if_ready_go = if_inst_buf_valid | (inst_sram_data_ok & ~if_need_drop);
    assign fs_allowin = (~if_valid | (if_ready_go & if_allowout)) & ~br_stall;

    assign if_next_ex_adef = nextpc[1:0] != 2'b00;

    localparam ENTRYPOINT = 32'h1c000000;

    assign pre_if_ready_go = inst_sram_req & inst_sram_addr_ok;
    // br_stall=1 时阻塞取指，防止 Load-to-Branch 时取到错误的指令
    // assign inst_sram_req = rst | (fs_allowin & (id_refreshing | flush) & ~if_next_ex_adef & ~br_stall);
    assign inst_sram_size  = 2'b10;   // inst固定4字节
    // assign inst_sram_addr = rst ? ENTRYPOINT : nextpc;

    localparam IDLE=2'd0, WAIT_ADDR=2'd1, WAIT_DATA=2'd2;
    reg [1:0] pre_fs_state;

    always @(posedge clk) begin
        if (rst) begin
            if_inst_buf_valid <= 1'b0;
        end else if (flush) begin
            if_inst_buf_valid <= 1'b0;
        end else if (inst_sram_data_ok & !if_need_drop) begin
            if (if_allowout) begin
                // 可以立即流向下一级，不需要缓存
                if_inst_buf_valid <= 1'b0;
            end else begin
                // 需要缓存
                if_inst_buf_valid <= 1'b1;
            end
        end else if (if_allowout & if_inst_buf_valid) begin
            // 缓存的指令流向下一级
            if_inst_buf_valid <= 1'b0;
        end
    end

    // 异常时丢弃指令
    always @(posedge clk) begin
        if (rst) begin
            if_need_drop <= 1'b0;
        end else if (flush && (if_valid | pre_if_ready_go)) begin
            // 异常，若有请求已被接收，需要丢弃后续返回
            if_need_drop <= 1'b1;
        end else if (inst_sram_data_ok & if_need_drop) begin
            // 丢弃一次后清除标记
            if_need_drop <= 1'b0;
        end
    end

    reg first_fetch;
    reg        br_pending;      // 有待处理的分支
    reg [31:0] br_target_buf;   // 缓存的分支目标

    always @(posedge clk) begin
        if (rst) begin
            pre_fs_state <= IDLE;
            inst_sram_req <= 1'b0;
            inst_sram_addr <= ENTRYPOINT;
            if_inst_buf <= 32'b0;
            first_fetch <= 1'b1;
            br_pending <= 1'b0;
            br_target_buf <= 32'h0;
        end else begin
            // 分支缓存逻辑：只要有分支就缓存，等待状态机处理
            if (flush) begin
                // 异常或ERTN时清除待处理的分支
                br_pending <= 1'b0;
            end else if (br_taken) begin
                // 有分支来临，缓存分支信息
                br_pending <= 1'b1;
                br_target_buf <= br_target;
            end else if (br_pending && pre_fs_state == IDLE && fs_allowin) begin
                // 缓存的分支被状态机采样，清除标记
                br_pending <= 1'b0;
            end

            case (pre_fs_state)
            IDLE: begin
                if (fs_allowin) begin
                    inst_sram_addr <= nextpc;
                    inst_sram_req <= 1'b1;
                    pre_fs_state <= WAIT_ADDR;
                end
            end
            WAIT_ADDR: begin
                if (inst_sram_addr_ok && inst_sram_req) begin
                    // 地址握手成功
                    inst_sram_req <= 1'b0; // 停拉 req，等待数据
                    pre_fs_state <= WAIT_DATA;
                    first_fetch <= 1'b0;
                end else if (flush) begin
                    inst_sram_req <= 1'b0;
                    pre_fs_state <= IDLE;
                end
            end
            WAIT_DATA: begin
                if (inst_sram_data_ok) begin
                    if (!if_need_drop) begin
                        // 正常写入 IF
                        if (!if_allowout) begin
                            if_inst_buf <= inst_sram_rdata;
                        end
                    end
                    pre_fs_state <= IDLE;
                end
            end
            endcase
        end
    end

    wire [31:0] if_inst = if_inst_buf_valid ? if_inst_buf : inst_sram_rdata;

    always @(posedge clk) begin
        if (rst) begin
            pc <= ENTRYPOINT;
            if_ex_adef <= 1'b0;
        end else if (flush) begin
            // On exception/ERTN, override stall and update PC immediately
            pc <= nextpc;
            if_ex_adef <= if_next_ex_adef;
        end else if (pre_if_ready_go & fs_allowin) begin
            pc <= nextpc;
            if_ex_adef <= if_next_ex_adef;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            if_valid <= 1'b0;
        end else if (flush) begin
            if_valid <= 1'b0;
        end else if (pre_if_ready_go) begin
            if_valid <= 1'b1;
        end else if (if_allowout && if_validout) begin
            if_valid <= 1'b0;
        end
    end

    assign if_ex_valid = if_ex_adef;
    assign if_ecode = `ECODE_ADEF;
    assign if_esubcode = `ESUBCODE_ADEF;

    assign if_is_csr = if_ex_adef;
    assign if_csr_en = if_ex_adef;
    assign if_csr_num = `CSR_BADV;
    assign if_csr_we = if_ex_adef;
    assign if_csr_wmask = 32'hffff_ffff;
    assign if_csr_wvalue = pc;

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

    // mem记录需要丢弃的访存返回数据
    reg [1:0] mem_drop_cnt;    // 最多丢弃2个返回（只有ex与mem阶段最多2个）
    
    always @(posedge clk) begin
        if (rst) begin
            mem_drop_cnt <= 2'b0;
        end else begin
            case ({flush, data_sram_data_ok})
                2'b00: mem_drop_cnt <= mem_drop_cnt;
                2'b01: mem_drop_cnt <= (mem_drop_cnt > 0) ? mem_drop_cnt - 1 : 2'b0;
                2'b10: begin
                    // 异常清空时，统计有多少个已发出但未完成的访存请求
                    if (u_stage_ex.validout && u_stage_ex.output_is_mem_op && 
                        data_sram_req && data_sram_addr_ok) begin
                        mem_drop_cnt <= mem_drop_cnt + 1;    // EX级有一个刚被接收
                    end
                    if (u_stage_mem.valid && u_stage_mem.mem_read) begin
                        mem_drop_cnt <= mem_drop_cnt + 1;    // MEM级有一个等待返回
                    end
                end
                2'b11: begin
                    // 异常的同时有数据返回
                    mem_drop_cnt <= mem_drop_cnt;  // 一进一出
                end
            endcase
        end
    end
    
    wire mem_data_ok_real = data_sram_data_ok && (mem_drop_cnt == 0);

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
        .validin(~br_taken & if_validout & ~(wb_ex | ertn_flush)),
        .allowin(if_allowout),
        .validout(),
        .allowout(),
        .stall(id_stall),
        .cancel(wb_ex | ertn_flush),

        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),

        .input_pc(pc),
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
    .data_sram_data_ok(mem_data_ok_real)
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
