`timescale 10ns / 1ps

module stage_ex(
    input  wire clk, rst,

    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,

    // pipeline data

    // ....data held for trace
    input  wire [31:0] input_pc,
    output wire [31:0] output_pc,

    // ....data held for WB stage
    input  wire [ 4:0] input_rf_waddr,
    input  wire        input_rf_we,
    output wire [ 4:0] output_rf_waddr,
    output wire        output_rf_we,

    // ....data held for MEM stage
    input  wire [31:0] input_mem_data,
    input  wire        input_mem_read,
    input  wire [4:0]  input_mem_op_ld,
    input  wire        input_mem_write,
    input  wire [2:0]  input_mem_op_st,
    output wire        output_mem_read,
    output wire [4:0]  output_mem_op_ld,

    // ....data processed in EX stage
    input  wire [31:0] input_alu_src1, input_alu_src2,
    input  wire [18:0] input_alu_op,
    output wire [31:0] output_alu_result, // alu_result

    // ...data forwarded to ID stage of next inst
    output wire [31:0] forward_data,
    output wire        forward_ready,

    // I/O
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);

    wire valid, readygo;

    pipeline pipe(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(readygo),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

    reg [31:0] alu_src1, alu_src2;
    reg [18:0] alu_op;
    reg [31:0] alu_output_sav;
    wire [31:0] alu_output, alu_result;
    wire alu_output_valid, alu_request_valid;

/**************** state machine ****************/

    // INIT -> REQ --> WAIT -->+
    //          |              |
    //          +---- DONE ----+

    // REQ: send request to ALU
    // WAIT: wait ALU to generate division result
    // DONE: ALU generated division result, wait for pipline transfering.

    localparam [2:0] STATE_INIT = 3'd0;
    localparam [2:0] STATE_REQ  = 3'd1;
    localparam [2:0] STATE_WAIT = 3'd2;
    localparam [2:0] STATE_DONE = 3'd3;

    reg [2:0] current_state, next_state;

    always @(*) begin
        case (current_state)
            STATE_INIT: begin
                next_state = STATE_REQ;
            end
            STATE_REQ: begin
                if (~valid) begin
                    next_state = STATE_REQ;
                end else begin
                    next_state = valid & alu_output_valid ? STATE_REQ : STATE_WAIT;
                end
            end
            STATE_WAIT: begin
                next_state = alu_output_valid ? STATE_DONE : STATE_WAIT;
            end
            STATE_DONE: begin
                next_state = pipe.refreshing ? STATE_REQ : STATE_DONE;
            end
            default: begin
                next_state = STATE_INIT;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) current_state <= STATE_INIT;
        else current_state <= next_state;
    end

    assign readygo = ((current_state == STATE_REQ) & alu_output_valid)
                   | (current_state == STATE_DONE)
                   ;

    wire alu_req_valid = valid && current_state == STATE_REQ;

/**************** execute unit ****************/

    always @(posedge clk) begin
        if (rst) begin
            alu_src1 <= 32'h0;
            alu_src2 <= 32'h0;
            alu_op   <= 19'h0;
        end
        else if (pipe.refreshing) begin
            alu_src1 <= input_alu_src1;
            alu_src2 <= input_alu_src2;
            alu_op   <= input_alu_op;
        end
    end

    alu u_alu(
        .clk(clk),
        .rst(rst),
        .alu_req_valid(alu_req_valid),
        .alu_op(alu_op),
        .alu_src1(alu_src1),
        .alu_src2(alu_src2),
        .alu_result_valid(alu_output_valid),
        .alu_result(alu_output)
    );

    always @(posedge clk) begin
        if (rst) begin
            alu_output_sav <= 32'h0;
        end else begin
            if (alu_output_valid) begin
                alu_output_sav <= alu_output;
            end
        end
    end
    assign alu_result = alu_output_valid ? alu_output : alu_output_sav;

    assign output_alu_result = alu_result;
    assign forward_data = alu_result;
    assign forward_ready = readygo & ~output_mem_read; // NOTE: not ready if data not prepared or is mem_read (need to be passed to MEM stage for reading actual data)

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

/**************** hold memory stage data ****************/

    reg         mem_read, mem_write;
    reg         op_st_b, op_st_h, op_st_w;
    reg [4:0]   mem_op_ld;
    reg [31:0]  mem_data;

    always @(posedge clk) begin
        if (rst) begin
            mem_read <= 1'b0;
            mem_op_ld <= 5'b0;
            mem_write <= 1'b0;
            {op_st_b, op_st_h, op_st_w} <= 3'b0;
            mem_data <= 32'h0;
        end
        else if (pipe.refreshing) begin
            mem_read <= input_mem_read;
            mem_op_ld <= input_mem_op_ld;
            mem_write <= input_mem_write;
            {op_st_b, op_st_h, op_st_w} <= input_mem_op_st;
            mem_data <= input_mem_data;
        end
    end

    assign data_sram_we    = op_st_w ? 4'b1111
                             : op_st_h ? (alu_result[1] ? 4'b1100 : 4'b0011)
                             : op_st_b ? (alu_result[1:0] == 2'b00 ? 4'b0001
                                         : alu_result[1:0] == 2'b01 ? 4'b0010
                                         : alu_result[1:0] == 2'b10 ? 4'b0100
                                         : alu_result[1:0] == 2'b11 ? 4'b1000
                                         : 4'b0000)
                             : 4'b0000;
    assign data_sram_addr  = alu_result;
    assign data_sram_wdata = op_st_b ? {4{mem_data[7:0]}}
                             : op_st_h ? {2{mem_data[15:0]}}
                             : op_st_w ? mem_data
                             : 32'h0;

    assign output_mem_read = mem_read;
    assign output_mem_op_ld = mem_op_ld;

/**************** hold write-back stage data ****************/

    localparam WB_HOLD_WIDTH = 5 // $bits(input_rf_waddr)
                             + 1 // $bits(input_rf_we)
                             ;

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
