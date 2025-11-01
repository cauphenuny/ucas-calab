`timescale 10ns / 1ps

module stage_mem(
    input  wire clk, rst,
    // pipeline control
    input  wire allowout, validin,
    output wire allowin, validout,

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
    input  wire [4:0]  input_mem_op_ld,
    input  wire [31:0] input_alu_result,

    output wire [31:0] output_rf_wdata,

    // ...data forwarded to ID stage of next inst
    output wire [31:0] forward_data,
    output wire        forward_ready,

    // I/O
    input  wire [31:0] data_sram_rdata
);

    wire valid;
    wire readygo = 1'b1;

    pipeline pipe(
        .clk(clk), .rst(rst),
        .allowout(allowout), .validin(validin),
        .readygo(readygo),
        .validout(validout), .allowin(allowin),
        .valid(valid)
    );

/**************** memory access unit ****************/

    reg         mem_read;
    reg         op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w;
    reg [31:0]  alu_result;

    always @(posedge clk) begin
        if (rst) begin
            mem_read   <= 1'b0;
            {op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w} <= 5'b0;
            alu_result <= 32'h0;
        end
        else if (pipe.refreshing) begin
            mem_read   <= input_mem_read;
            {op_ld_b, op_ld_h, op_ld_bu, op_ld_hu, op_ld_w} <= input_mem_op_ld;
            alu_result <= input_alu_result;
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
    assign forward_ready = readygo;

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
