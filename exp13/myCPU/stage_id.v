`timescale 10ns / 1ps

module stage_id(
    input  wire clk, rst,
    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,
    input  wire stall,
    input  wire cancel,

    // pipeline data
    input  wire [31:0] input_pc,
    input  wire [31:0] input_inst,

    output wire [31:0] output_pc,

    output wire [31:0] output_br_target,
    output wire        output_br_taken,

    output wire [31:0] output_alu_src1, output_alu_src2,
    output wire [20:0] output_alu_op,

    output wire [31:0] output_mem_data, // addr: alu_result
    output wire        output_mem_read,
    output wire [4:0]  output_mem_op_ld,
    output wire        output_mem_write,
    output wire [2:0]  output_mem_op_st,

    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,

    // exception info
    input  wire        input_ex_valid, // ADEF exception from IF
    input  wire [ 5:0] input_ecode,
    input  wire [ 8:0] input_esubcode,
    output wire        output_ex_valid,
    output wire [ 5:0] output_ecode,
    output wire [ 8:0] output_esubcode,

    // CSR bundle for WB
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

    // CSR value/flag
    input  wire [31:0] csr_rvalue,
    input  wire [12:0] intr_stat,
    output wire        output_is_csr,
    output wire [31:0] output_csr_rvalue,

    // ERTN flag
    output wire        output_is_ertn,

    // I/O
    input  wire [31:0] rf_rdata1, rf_rdata2,
    output wire [ 4:0] rf_raddr1, rf_raddr2
);

    wire valid; // pipeline status
    wire legal; // no unexpected exception

    cancelable_pipeline pipe(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(~stall), // stall when waiting for prev inst write back
        .cancel(cancel),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

/**************** input ****************/

    reg [31:0] pc, inst;
    reg ex_valid_r; // exception from previous pipeline stage
    reg [ 5:0] ecode_r;
    reg [ 8:0] esubcode_r;
    reg        csr_en_r;
    reg [13:0] csr_num_r;
    reg        csr_we_r;
    reg [31:0] csr_wmask_r;
    reg [31:0] csr_wvalue_r;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0;
            inst <= 32'h0;
            ex_valid_r <= 1'b0;
            ecode_r <= 6'h0;
            esubcode_r <= 9'h0;
            csr_en_r    <= 1'b0;
            csr_num_r   <= 14'h0;
            csr_we_r    <= 1'b0;
            csr_wmask_r <= 32'h0;
            csr_wvalue_r<= 32'h0;
        end
        else if (pipe.refreshing) begin
            pc <= input_pc;
            inst <= input_inst;

            ex_valid_r  <= input_ex_valid;
            ecode_r     <= input_ecode;
            esubcode_r  <= input_esubcode;

            csr_en_r    <= input_csr_en;
            csr_num_r   <= input_csr_num;
            csr_we_r    <= input_csr_we;
            csr_wmask_r <= input_csr_wmask;
            csr_wvalue_r<= input_csr_wvalue;
        end
    end

/**************** wire definition ****************/

    wire [ 5:0] op_31_26;
    wire [ 3:0] op_25_22;
    wire [ 1:0] op_21_20;
    wire [ 4:0] op_19_15;

    wire        br_taken;
    wire [31:0] br_target;

    wire        src1_is_pc;
    wire        src2_is_imm;
    wire        res_from_mem;
    wire        dst_is_r1;
    wire        dst_is_rj;
    wire        gr_we;
    wire        mem_we;
    wire        src_reg_is_rd;
    wire [31:0] imm;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;

    wire [ 4:0] rd;
    wire [ 4:0] rj;
    wire [ 4:0] rk;
    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;
    wire [4: 0] dest;
    wire [31:0] rj_value;
    wire [31:0] rkd_value;
    wire        rj_eq_rd;
    wire        rj_lt_rd;
    wire        rj_ult_rd;

    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [ 3:0] op_21_20_d;
    wire [31:0] op_19_15_d;

    wire        inst_add_w;
    wire        inst_sub_w;
    wire        inst_slt;
    wire        inst_sltu;
    wire        inst_nor;
    wire        inst_and;
    wire        inst_or;
    wire        inst_xor;
    wire        inst_sll_w;
    wire        inst_srl_w;
    wire        inst_sra_w;
    wire        inst_slli_w;
    wire        inst_srli_w;
    wire        inst_srai_w;
    wire        inst_addi_w;
    wire        inst_slti;
    wire        inst_sltui;
    wire        inst_andi;
    wire        inst_ori;
    wire        inst_xori;
    wire        inst_ld_w;
    wire        inst_ld_b;
    wire        inst_ld_h;
    wire        inst_ld_bu;
    wire        inst_ld_hu;
    wire        inst_st_b;
    wire        inst_st_h;
    wire        inst_st_w;
    wire        inst_jirl;
    wire        inst_b;
    wire        inst_bl;
    wire        inst_beq;
    wire        inst_bne;
    wire        inst_blt;
    wire        inst_bge;
    wire        inst_bltu;
    wire        inst_bgeu;
    wire        inst_lu12i_w;
    wire        inst_mul_w;
    wire        inst_mulh_w;
    wire        inst_mulh_wu;
    wire        inst_pcaddu12i;
    wire        inst_div_w;
    wire        inst_div_wu;
    wire        inst_mod_w;
    wire        inst_mod_wu;
    wire        inst_syscall;
    wire        inst_break;
    wire        inst_ertn;
    wire        inst_csrrd;
    wire        inst_csrwr;
    wire        inst_csrxchg;
    wire        inst_rdtimel_w;
    wire        inst_rdtimeh_w;
    wire        inst_rdcntvl_w;
    wire        inst_rdcntvh_w;
    wire        inst_rdcntid;

    wire        exception_ine;
    wire        exception_intr;

    wire        need_ui5;
    wire        need_si12;
    wire        need_ui12;
    wire        need_si16;
    wire        need_si20;
    wire        need_si26;
    wire        src2_is_4;

    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [20:0] alu_op;

    // syscall/CSR/ERTN detect
    wire        ex_valid;
    wire [5:0]  ex_ecode;
    wire [8:0]  ex_esubcode;
    wire        is_csr;

/**************** decoder ****************/

    assign op_31_26  = inst[31:26];
    assign op_25_22  = inst[25:22];
    assign op_21_20  = inst[21:20];
    assign op_19_15  = inst[19:15];

    assign rd   = inst[ 4: 0];
    assign rj   = inst[ 9: 5];
    assign rk   = inst[14:10];

    assign i12  = inst[21:10];
    assign i20  = inst[24: 5];
    assign i16  = inst[25:10];
    assign i26  = {inst[ 9: 0], inst[25:10]};

    decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
    decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
    decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
    decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

    assign inst_add_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
    assign inst_sub_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
    assign inst_slt     = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
    assign inst_sltu    = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
    assign inst_nor     = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
    assign inst_and     = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
    assign inst_or      = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
    assign inst_xor     = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
    assign inst_slli_w  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    assign inst_srli_w  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    assign inst_srai_w  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    assign inst_sll_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b01110];
    assign inst_srl_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b01111];
    assign inst_sra_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b10000];
    assign inst_mul_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b11000];
    assign inst_mulh_w  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b11001];
    assign inst_mulh_wu = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'b11010];
    assign inst_div_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'b00000];
    assign inst_mod_w   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'b00001];
    assign inst_div_wu  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'b00010];
    assign inst_mod_wu  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'b00011];

    assign inst_slti   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1000];
    assign inst_sltui  = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1001];
    assign inst_addi_w = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1010];
    assign inst_andi   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1101];
    assign inst_ori    = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1110];
    assign inst_xori   = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'b1111];

    assign inst_ld_b   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h0];
    assign inst_ld_h   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h1];
    assign inst_ld_bu  = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h8];
    assign inst_ld_hu  = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h9];
    assign inst_ld_w   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    assign inst_st_b   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h4];
    assign inst_st_h   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h5];
    assign inst_st_w   = ~ex_valid_r & op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    assign inst_jirl   = ~ex_valid_r & op_31_26_d[6'h13];
    assign inst_b      = ~ex_valid_r & op_31_26_d[6'h14];
    assign inst_bl     = ~ex_valid_r & op_31_26_d[6'h15];
    assign inst_beq    = ~ex_valid_r & op_31_26_d[6'h16];
    assign inst_bne    = ~ex_valid_r & op_31_26_d[6'h17];
    assign inst_blt    = ~ex_valid_r & op_31_26_d[6'h18];
    assign inst_bge    = ~ex_valid_r & op_31_26_d[6'h19];
    assign inst_bltu   = ~ex_valid_r & op_31_26_d[6'h1a];
    assign inst_bgeu   = ~ex_valid_r & op_31_26_d[6'h1b];

    assign inst_lu12i_w   = ~ex_valid_r & op_31_26_d[6'b000101] & ~inst[25];
    assign inst_pcaddu12i = ~ex_valid_r & op_31_26_d[6'b000111] & ~inst[25];

    assign inst_syscall = ~ex_valid_r & (inst[31:15] == 17'b00000000001010110);
    assign inst_break   = ~ex_valid_r & (inst[31:15] == 17'b00000000001010100);
    assign inst_ertn    = ~ex_valid_r & (inst == 32'h06483800);

    assign inst_csrrd   = ~ex_valid_r & is_csr_op & (inst[9:5]  == 5'b00000);
    assign inst_csrwr   = ~ex_valid_r & is_csr_op & (inst[9:5]  == 5'b00001);
    assign inst_csrxchg = ~ex_valid_r & is_csr_op & (inst[9:5]  != 5'b00000) & (inst[9:5] != 5'b00001);

    assign inst_rdtimel_w = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & inst[14:10] == 5'b11000;
    assign inst_rdtimeh_w = ~ex_valid_r & op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & inst[14:10] == 5'b11001;

    assign inst_rdcntvl_w = inst_rdtimel_w & (rj == 5'h0);
    assign inst_rdcntvh_w = inst_rdtimeh_w & (rj == 5'h0);
    assign inst_rdcntid   = inst_rdtimel_w & (rd == 5'h0);

    assign exception_ine = ~ex_valid_r      &
                           ~inst_add_w      & ~inst_sub_w       & ~inst_slt     & ~inst_sltu &
                           ~inst_nor        & ~inst_and         & ~inst_or      & ~inst_xor &
                           ~inst_sll_w      & ~inst_srl_w       & ~inst_sra_w   & ~inst_slli_w &
                           ~inst_srli_w     & ~inst_srai_w      & ~inst_addi_w  & ~inst_slti &
                           ~inst_sltui      & ~inst_andi        & ~inst_ori     & ~inst_xori &
                           ~inst_ld_w       & ~inst_ld_b        & ~inst_ld_h    & ~inst_ld_bu &
                           ~inst_ld_hu      & ~inst_st_b        & ~inst_st_h    & ~inst_st_w &
                           ~inst_jirl       & ~inst_b           & ~inst_bl      & ~inst_beq &
                           ~inst_bne        & ~inst_blt         & ~inst_bge     & ~inst_bltu &
                           ~inst_bgeu       & ~inst_lu12i_w     & ~inst_mul_w   & ~inst_mulh_w &
                           ~inst_mulh_wu    & ~inst_pcaddu12i   & ~inst_div_w   & ~inst_div_wu &
                           ~inst_mod_w      & ~inst_mod_wu      & ~inst_syscall & ~inst_ertn &
                           ~inst_csrrd      & ~inst_csrwr       & ~inst_csrxchg & ~inst_rdcntvl_w &
                           ~inst_rdcntvh_w  & ~inst_rdcntid     & ~inst_break   ;

    assign exception_intr = valid & (intr_stat != 13'h0);

    assign legal = ~ex_valid_r & ~exception_ine;

    wire is_csr_op = (inst[31:24] == 8'h04);
    assign is_csr       = valid & (
                            inst_csrrd | inst_csrwr | inst_csrxchg |
                            inst_rdcntid
                        );

    assign alu_op[ 0] = inst_add_w | inst_addi_w| inst_ld_b | inst_ld_h
                        | inst_ld_bu | inst_ld_hu | inst_ld_w | inst_st_b | inst_st_h | inst_st_w
                        | inst_jirl | inst_bl | inst_pcaddu12i;
    assign alu_op[ 1] = inst_sub_w;
    assign alu_op[ 2] = inst_slt | inst_slti;
    assign alu_op[ 3] = inst_sltu | inst_sltui;
    assign alu_op[ 4] = inst_and | inst_andi;
    assign alu_op[ 5] = inst_nor;
    assign alu_op[ 6] = inst_or | inst_ori;
    assign alu_op[ 7] = inst_xor | inst_xori;
    assign alu_op[ 8] = inst_slli_w | inst_sll_w;
    assign alu_op[ 9] = inst_srli_w | inst_srl_w;
    assign alu_op[10] = inst_srai_w | inst_sra_w;
    assign alu_op[11] = inst_lu12i_w;
    assign alu_op[12] = inst_mul_w;
    assign alu_op[13] = inst_mulh_w;
    assign alu_op[14] = inst_mulh_wu;
    assign alu_op[15] = inst_div_w;
    assign alu_op[16] = inst_div_wu;
    assign alu_op[17] = inst_mod_w;
    assign alu_op[18] = inst_mod_wu;
    assign alu_op[19] = inst_rdcntvl_w;
    assign alu_op[20] = inst_rdcntvh_w;

    assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
    assign need_si12  =  inst_addi_w | inst_ld_b | inst_ld_h | inst_ld_bu 
                        | inst_ld_hu | inst_ld_w | inst_st_b | inst_st_h | inst_st_w | inst_slti | inst_sltui;
    assign need_ui12  =  inst_andi | inst_ori | inst_xori;
    assign need_si16  =  inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
    assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
    assign need_si26  =  inst_b | inst_bl;
    assign src2_is_4  =  inst_jirl | inst_bl;

    assign imm = src2_is_4 ? 32'h4                      :
                 need_si20 ? {i20[19:0], 12'b0}         :
                 need_ui12 ? {20'b0, i12[11:0]}         :
    /*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

    assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                {{14{i16[15]}}, i16[15:0], 2'b0} ;

    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    assign src_reg_is_rd = inst_beq | inst_bne | inst_st_b | inst_st_h | inst_st_w | inst_blt
                         | inst_bge | inst_bltu | inst_bgeu
                         | inst_csrwr | inst_csrxchg;

    assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

    assign src2_is_imm   = inst_slli_w
                         | inst_srli_w
                         | inst_srai_w
                         | inst_addi_w
                         | inst_ld_b
                         | inst_ld_h
                         | inst_ld_bu
                         | inst_ld_hu
                         | inst_ld_w
                         | inst_st_b
                         | inst_st_h
                         | inst_st_w
                         | inst_lu12i_w
                         | inst_pcaddu12i
                         | inst_jirl
                         | inst_bl
                         | inst_slti
                         | inst_sltui
                         | inst_andi
                         | inst_ori
                         | inst_xori
                         ;

    assign res_from_mem  = inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_ld_w;
    assign dst_is_r1     = inst_bl;
    assign dst_is_rj     = inst_rdcntid;

    assign gr_we         = legal &
                           ~inst_st_b & ~inst_st_h & ~inst_st_w & ~inst_beq & ~inst_bne &
                           ~inst_b & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu & 
                           ~inst_syscall & ~inst_ertn & ~inst_syscall;

    assign mem_we        = inst_st_b | inst_st_h | inst_st_w;
    assign dest          = dst_is_r1 ? 5'd1 : dst_is_rj ? rj : rd;

    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd :rk;

    assign rj_value  = rf_rdata1;
    assign rkd_value = rf_rdata2;

    comparator u_comparator (
        .a(rj_value),
        .b(rkd_value),
        .a_eq_b(rj_eq_rd),
        .a_lt_b_signed(rj_lt_rd),
        .a_lt_b_unsigned(rj_ult_rd)
    );

    assign br_taken = (   inst_beq  &&  rj_eq_rd
                    || inst_bne  && !rj_eq_rd
                    || inst_blt  &&  rj_lt_rd
                    || inst_bge  && !rj_lt_rd
                    || inst_bltu &&  rj_ult_rd
                    || inst_bgeu && !rj_ult_rd
                    || inst_jirl
                    || inst_bl
                    || inst_b
                    ) && valid;
    assign br_target = (inst_beq || inst_bne || inst_blt 
                        || inst_bge || inst_bltu || inst_bgeu 
                        || inst_bl || inst_b) ? (pc + br_offs) :
                                                    /*inst_jirl*/ (rj_value + jirl_offs);

    assign alu_src1 = src1_is_pc  ? pc[31:0] : rj_value;
    assign alu_src2 = src2_is_imm ? imm : rkd_value;

/**************** exception detect & output ****************/

    // TODO: remove redunctant valid
    assign ex_valid = inst_break & valid
                    | inst_syscall & valid
                    | exception_ine & valid
                    | exception_intr & valid
                    ;
    assign ex_ecode = {6{inst_break & valid}} & `ECODE_SYS
                    | {6{inst_syscall & valid}} & `ECODE_BRK
                    | {6{exception_ine & valid}} & `ECODE_INE
                    | {6{exception_intr & valid}} & `ECODE_INTR // WARN: assert ECFG.VS = 0
                    ;
    assign ex_esubcode = {9{inst_syscall & valid}} & 9'h0
                       | {9{exception_ine & valid}} & 9'h0
                       | {9{exception_intr & valid}} & 9'h0
                       ;

/**************** CSR/ERTN outputs ****************/
    wire [13:0] csr_num_imm = {14{is_csr_op}} & inst[23:10]
                            | {14{inst_rdcntid}} & `CSR_TID
                            ;
    wire        csr_en = is_csr;
    wire        csr_do_write = (inst_csrwr | inst_csrxchg) & valid;
    // csrxchg: wmask = rj_value, wvalue = rd_value(rkd_value)
    // csrwr  : wmask = all-1,  wvalue = rd_value(rkd_value)
    // csrrd  : no write
    wire [31:0] csr_wmask = inst_csrxchg ? rf_rdata1
                             : inst_csrwr ? 32'hffff_ffff
                             : 32'h0;
    wire [31:0] csr_wvalue = (inst_csrwr | inst_csrxchg) ? rkd_value : 32'h0;

/**************** output ****************/

    assign output_pc        = pc;
    assign output_alu_src1  = alu_src1;
    assign output_alu_src2  = alu_src2;
    assign output_alu_op    = alu_op;
    assign output_rf_waddr  = dest;
    assign output_rf_we     = gr_we;
    assign output_ex_valid  = ex_valid;
    assign output_ecode     = ex_ecode;
    assign output_esubcode  = ex_esubcode;
    assign output_csr_en    = csr_en | csr_en_r;
    assign output_csr_num   = {14{csr_en}} & csr_num_imm
                            | {14{csr_en_r}} & csr_num_r
                            ;
    assign output_csr_we    = csr_en & csr_do_write
                            | csr_en_r & csr_we_r
                            ;
    assign output_csr_wmask = {32{csr_en}} & csr_wmask
                            | {32{csr_en_r}} & csr_wmask_r
                            ;
    assign output_csr_wvalue= {32{csr_en}} & csr_wvalue
                            | {32{csr_en_r}} & csr_wvalue_r
                            ;
    assign output_is_csr    = is_csr;
    assign output_csr_rvalue= csr_rvalue;
    assign output_is_ertn   = inst_ertn & valid;
    assign output_br_taken  = br_taken & ~stall; // when stall, can not take br_taken
    assign output_br_target = br_target;
    assign output_mem_data  = rkd_value;
    assign output_mem_read  = inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_ld_w;
    assign output_mem_op_ld = {inst_ld_b, inst_ld_h, inst_ld_bu, inst_ld_hu, inst_ld_w};
    assign output_mem_write = inst_st_b | inst_st_h | inst_st_w;
    assign output_mem_op_st = {inst_st_b, inst_st_h, inst_st_w};

endmodule
