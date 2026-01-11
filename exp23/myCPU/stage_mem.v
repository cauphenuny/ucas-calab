`timescale 10ns / 1ps

module stage_mem(
    input  wire clk, rst,
    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,
    input  wire cancel,

    // pipeline data

    // ..data held for trace
    input  wire [31:0] input_pc,
    output wire [31:0] output_pc,

    // ....data held for WB stage
    input  wire [ 4:0] input_rf_waddr,
    input  wire        input_rf_we,
    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,

    // ....data processed in MEM stage
    input  wire        input_mem_read,
    input  wire        input_mem_write,
    input  wire [4:0]  input_mem_op_ld,
    input  wire [31:0] input_alu_result,

    output wire [31:0] output_rf_wdata,

    // ...data forwarded to ID stage of next inst
    output wire [31:0] forward_data,
    output wire        forward_ready,

    // exception info
    input  wire        input_ex_valid,
    input  wire [ 5:0] input_ecode,
    input  wire [ 8:0] input_esubcode,
    input  wire        input_tlb_found,
    input  wire [ 3:0] input_tlb_index,
    input  wire [ 5:0] input_tlb_ps,
    output wire        output_ex_valid,
    output wire [ 5:0] output_ecode,
    output wire [ 8:0] output_esubcode,
    output wire        output_tlb_found,
    output wire [ 3:0] output_tlb_index,
    output wire [ 5:0] output_tlb_ps,

    // CSR bundle
    input  wire        input_csr_en,
    input  wire [13:0] input_csr_num,
    input  wire        input_csr_we,
    input  wire [31:0] input_csr_wmask,
    input  wire [31:0] input_csr_wvalue,
    output wire        output_csr_en,
    output wire [13:0] output_csr_num,
    output wire        output_csr_we,
    output wire [31:0] output_csr_wmask,
    output wire [31:0] output_csr_wvalue,

    // ERTN flag
    input  wire        input_is_ertn,
    output wire        output_is_ertn,

    // TLB instructions
    input  wire        input_inst_tlbsrch,
    input  wire        input_inst_tlbrd,
    input  wire        input_inst_tlbwr,
    input  wire        input_inst_tlbfill,
    input  wire        input_inst_invtlb,
    input  wire [ 4:0] input_invtlb_op,
    input  wire [ 9:0] input_invtlb_asid,
    input  wire [31:0] input_invtlb_vaddr,
    output wire        output_inst_tlbsrch,
    output wire        output_inst_tlbrd,
    output wire        output_inst_tlbwr,
    output wire        output_inst_tlbfill,
    output wire        output_inst_invtlb,
    output wire [ 4:0] output_invtlb_op,
    output wire [ 9:0] output_invtlb_asid,
    output wire [31:0] output_invtlb_vaddr,
    
    // TLBSRCH result
    input  wire        input_tlbsrch_found,
    input  wire [ 3:0] input_tlbsrch_index,
    output wire        output_tlbsrch_found,
    output wire [ 3:0] output_tlbsrch_index,

    // CSR flag/value
    input  wire        input_is_csr,
    input  wire [31:0] input_csr_rvalue,
    output wire        output_is_csr,
    output wire [31:0] output_csr_rvalue,

    // I/O
    input  wire [31:0] data_sram_rdata,
    input  wire        data_sram_data_ok
);

    wire valid;
    wire is_mem_op;
    wire drop_now;
    wire data_ok_effective;
    wire have_exception;

    wire readygo = ~valid | (~is_mem_op | data_ok_effective | have_exception);

    cancelable_pipeline pipe(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(readygo),
        .cancel(cancel),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

/**************** memory access unit ****************/

    reg         mem_read;
    reg         mem_write;
    reg         op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w;
    reg [31:0]  alu_result;
    reg         drop_data_ok;

    assign is_mem_op   = mem_read | mem_write;
    assign drop_now         = cancel & valid & is_mem_op;
    assign data_ok_effective= data_sram_data_ok & ~(drop_data_ok | drop_now);

    always @(posedge clk) begin
        if (rst) begin
            mem_read   <= 1'b0;
            mem_write  <= 1'b0;
            {op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w} <= 5'b0;
            alu_result <= 32'h0;
        end
        else if (pipe.refreshing) begin
            mem_read   <= input_mem_read;
            mem_write  <= input_mem_write;
            {op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w} <= input_mem_op_ld;
            alu_result <= input_alu_result;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            drop_data_ok <= 1'b0;
        end else if (data_sram_data_ok && (drop_data_ok | drop_now)) begin
            drop_data_ok <= 1'b0;
        end else if (drop_now) begin
            drop_data_ok <= 1'b1;
        end
    end

    wire [31:0] mem_rdata = data_sram_rdata;
    
    wire [7:0] selected_byte = (alu_result[1:0] == 2'b00) ? mem_rdata[7:0]
                             : (alu_result[1:0] == 2'b01) ? mem_rdata[15:8]
                             : (alu_result[1:0] == 2'b10) ? mem_rdata[23:16]
                             : mem_rdata[31:24];
    wire [31:0] mem_byte_rdata = {{24{selected_byte[7] & op_ld_b}}, selected_byte};
    
    wire [15:0] selected_half = alu_result[1] ? mem_rdata[31:16] : mem_rdata[15:0];
    wire [31:0] mem_half_data = {{16{selected_half[15] & op_ld_h}}, selected_half};
    
    wire [31:0] mem_read_result = op_ld_w ? mem_rdata
                                : (op_ld_b | op_ld_bu) ? mem_byte_rdata
                                : (op_ld_h | op_ld_hu) ? mem_half_data
                                : 32'h0;

    assign output_rf_wdata = mem_read ? mem_read_result : alu_result;
    assign forward_data = output_rf_wdata;
    // 前递信号更改：只有当MEM级能流向WB级时，前递数据才真正ready
    assign forward_ready = validout;

/**************** exception info ****************/
    reg        ex_valid_r;
    reg [5:0]  ecode_r;
    reg [8:0]  esubcode_r;
    reg        tlb_found_r;
    reg [3:0]  tlb_index_r;
    reg [5:0]  tlb_ps_r;

    always @(posedge clk) begin
        if (rst) begin
            ex_valid_r <= 1'b0;
            ecode_r    <= 6'h0;
            esubcode_r <= 9'h0;
            tlb_found_r <= 1'b0;
            tlb_index_r <= 4'h0;
            tlb_ps_r    <= 6'h0;
        end else if (pipe.refreshing) begin
            ex_valid_r <= input_ex_valid;
            ecode_r    <= input_ecode;
            esubcode_r <= input_esubcode;
            tlb_found_r <= input_tlb_found;
            tlb_index_r <= input_tlb_index;
            tlb_ps_r    <= input_tlb_ps;
        end
    end

    assign output_ex_valid  = ex_valid_r && valid;
    assign output_ecode     = ecode_r;
    assign output_esubcode  = esubcode_r;
    assign output_tlb_found = tlb_found_r;
    assign output_tlb_index = tlb_index_r;
    assign output_tlb_ps    = tlb_ps_r;

    assign have_exception = ex_valid_r;

/**************** CSR bundle & ERTN ****************/
    reg        csr_en_r;
    reg [13:0] csr_num_r;
    reg        csr_we_r;
    reg [31:0] csr_wmask_r;
    reg [31:0] csr_wvalue_r;
    reg        is_ertn_r;
    reg        is_csr_r;
    reg [31:0] csr_rvalue_r;
    
    // TLB instruction registers
    reg        inst_tlbsrch_r;
    reg        inst_tlbrd_r;
    reg        inst_tlbwr_r;
    reg        inst_tlbfill_r;
    reg        inst_invtlb_r;
    reg [ 4:0] invtlb_op_r;
    reg [ 9:0] invtlb_asid_r;
    reg [31:0] invtlb_vaddr_r;
    
    // TLBSRCH result registers
    reg        tlbsrch_found_r;
    reg [ 3:0] tlbsrch_index_r;

    always @(posedge clk) begin
        if (rst) begin
            csr_en_r    <= 1'b0;
            csr_num_r   <= 14'h0;
            csr_we_r    <= 1'b0;
            csr_wmask_r <= 32'h0;
            csr_wvalue_r<= 32'h0;
            is_ertn_r   <= 1'b0;
            inst_tlbsrch_r <= 1'b0;
            inst_tlbrd_r   <= 1'b0;
            inst_tlbwr_r   <= 1'b0;
            inst_tlbfill_r <= 1'b0;
            inst_invtlb_r  <= 1'b0;
            invtlb_op_r    <= 5'b0;
            invtlb_asid_r  <= 10'b0;
            invtlb_vaddr_r <= 32'h0;
            tlbsrch_found_r <= 1'b0;
            tlbsrch_index_r <= 4'b0;
        end else if (pipe.refreshing) begin
            csr_en_r    <= input_csr_en;
            csr_num_r   <= input_csr_num;
            csr_we_r    <= input_csr_we;
            csr_wmask_r <= input_csr_wmask;
            csr_wvalue_r<= input_csr_wvalue;
            is_ertn_r   <= input_is_ertn;
            is_csr_r    <= input_is_csr;
            csr_rvalue_r<= input_csr_rvalue;
            inst_tlbsrch_r <= input_inst_tlbsrch;
            inst_tlbrd_r   <= input_inst_tlbrd;
            inst_tlbwr_r   <= input_inst_tlbwr;
            inst_tlbfill_r <= input_inst_tlbfill;
            inst_invtlb_r  <= input_inst_invtlb;
            invtlb_op_r    <= input_invtlb_op;
            invtlb_asid_r  <= input_invtlb_asid;
            invtlb_vaddr_r <= input_invtlb_vaddr;
            tlbsrch_found_r <= input_tlbsrch_found;
            tlbsrch_index_r <= input_tlbsrch_index;
        end
    end

    assign output_csr_en    = csr_en_r;
    assign output_csr_num   = csr_num_r;
    assign output_csr_we    = csr_we_r;
    assign output_csr_wmask = csr_wmask_r;
    assign output_csr_wvalue= csr_wvalue_r;
    assign output_is_ertn   = is_ertn_r & valid;
    assign output_is_csr    = is_csr_r;
    assign output_csr_rvalue= csr_rvalue_r;
    
    // TLB instruction outputs
    assign output_inst_tlbsrch = inst_tlbsrch_r & valid;
    assign output_inst_tlbrd   = inst_tlbrd_r & valid;
    assign output_inst_tlbwr   = inst_tlbwr_r & valid;
    assign output_inst_tlbfill = inst_tlbfill_r & valid;
    assign output_inst_invtlb  = inst_invtlb_r & valid;
    assign output_invtlb_op    = invtlb_op_r;
    assign output_invtlb_asid  = invtlb_asid_r;
    assign output_invtlb_vaddr = invtlb_vaddr_r;
    
    // TLBSRCH result outputs
    assign output_tlbsrch_found = tlbsrch_found_r;
    assign output_tlbsrch_index = tlbsrch_index_r;

/**************** hold trace data ****************/

    reg [31:0] pc;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
        end
        else if (pipe.refreshing) begin
            pc <= input_pc;
        end
    end

    assign output_pc = pc;

/**************** hold write-back stage data ****************/

    localparam WB_HOLD_WIDTH = 5 // $bits(input_rf_waddr)
                             + 1;// $bits(input_rf_we);

    reg [WB_HOLD_WIDTH-1:0] wb_regs;

    always @(posedge clk) begin
        if (rst) begin
            wb_regs <= {WB_HOLD_WIDTH{1'b0}};
        end
        else if (pipe.refreshing) begin
            wb_regs <= {input_rf_waddr, input_rf_we};
        end
    end

    assign {output_rf_waddr, output_rf_we} = wb_regs;

endmodule
