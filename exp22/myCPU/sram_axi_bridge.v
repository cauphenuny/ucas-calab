`timescale 1ns / 1ps

// sram_axi_bridge (multi-channel version)
// - 独立通道状态机：AR、R、AW/W、B
// - 严格保持 AXI 有效握手规则，输出寄存化，避免同通道 ready/valid 的组合依赖
module sram_axi_bridge (
        input  wire        aclk,
        input  wire        aresetn,
        // inst cache read side
        input  wire        inst_rd_req,
        input  wire [ 2:0] inst_rd_type,
        input  wire [31:0] inst_rd_addr,
        output wire        inst_rd_rdy,
        output wire        inst_ret_valid,
        output wire        inst_ret_last,
        output wire [31:0] inst_ret_data,
        // data sram side
        input  wire        data_req,
        input  wire        data_wr,
        input  wire [ 1:0] data_size,
        input  wire [31:0] data_addr,
        input  wire [ 3:0] data_wstrb,
        input  wire [31:0] data_wdata,
        output wire        data_addr_ok,
        output wire        data_data_ok,
        output reg  [31:0] data_rdata,
        // AXI read address
        output reg  [ 3:0] arid,
        output reg  [31:0] araddr,
        output reg  [ 7:0] arlen,
        output reg  [ 2:0] arsize,
        output reg  [ 1:0] arburst,
        output reg  [ 1:0] arlock,
        output reg  [ 3:0] arcache,
        output reg  [ 2:0] arprot,
        output reg         arvalid,
        input  wire        arready,
        // AXI read data
        input  wire [ 3:0] rid,
        input  wire [31:0] rdata,
        input  wire [ 1:0] rresp,
        input  wire        rlast,
        input  wire        rvalid,
        output wire        rready,
        // AXI write address
        output reg  [ 3:0] awid,
        output reg  [31:0] awaddr,
        output reg  [ 7:0] awlen,
        output reg  [ 2:0] awsize,
        output reg  [ 1:0] awburst,
        output reg  [ 1:0] awlock,
        output reg  [ 3:0] awcache,
        output reg  [ 2:0] awprot,
        output reg         awvalid,
        input  wire        awready,
        // AXI write data
        output reg  [ 3:0] wid,
        output reg  [31:0] wdata,
        output reg  [ 3:0] wstrb,
        output reg         wlast,
        output reg         wvalid,
        input  wire        wready,
        // AXI write response
        input  wire [ 3:0] bid,
        input  wire [ 1:0] bresp,
        input  wire        bvalid,
        output wire        bready
);
    reg inst_rd_ongoing;
    reg data_rd_ongoing;

    assign rready = inst_rd_ongoing || data_rd_ongoing;

    reg wr_ongoing;   // 写已发出，等待 B 响应
    assign bready = wr_ongoing;

    reg data_rd_addr_ok, data_wr_addr_ok;
    reg data_rd_data_ok, data_wr_data_ok;

    assign data_addr_ok = data_rd_addr_ok || data_wr_addr_ok;
    assign data_data_ok = data_rd_data_ok || data_wr_data_ok;

    localparam [3:0] ID_INST = 4'd0;
    localparam [3:0] ID_DATA = 4'd1;
    localparam [2:0] AXI_BYTE = 3'b000;
    localparam [2:0] AXI_HALF = 3'b001;
    localparam [2:0] AXI_WORD = 3'b010;
    localparam [2:0] AXI_LINE = 3'b100;

    wire [2:0] inst_rd_size = (inst_rd_type == AXI_BYTE) ? 3'b000 :
                              (inst_rd_type == AXI_HALF) ? 3'b001 :
                              3'b010;
    wire [7:0] inst_rd_len  = (inst_rd_type == AXI_LINE) ? 8'd3 : 8'd0;

    wire data_read_req = data_req && !data_wr;
    wire can_accept_ar = !arvalid && !inst_rd_ongoing && !data_rd_ongoing && !wr_ongoing;

    // AR 通道：仅驱动 AXI 读地址握手信号
    always @(posedge aclk) begin
        if (!aresetn) begin
            data_rd_addr_ok <= 1'b0;
            arvalid <= 1'b0;
            araddr  <= 32'h0;
            arsize  <= 3'b010;
            arid    <= 4'd0;
            arlen   <= 8'd0;
            arburst <= 2'b01;
            arlock  <= 2'b00;
            arcache <= 4'b0000;
            arprot  <= 3'b000;
        end else begin
            data_rd_addr_ok <= 1'b0;
            if (!arvalid && can_accept_ar) begin
                // 数据读优先：支持立即发起（同拍）或使用挂起
                if (data_read_req) begin
                    data_rd_addr_ok <= 1'b1;
                    araddr   <= data_addr;
                    arsize   <= {1'b0, data_size};
                    arlen    <= 8'd0;
                    arid     <= ID_DATA;
                    arvalid  <= 1'b1;
                end else if (inst_rd_req) begin
                    araddr   <= inst_rd_addr;
                    arsize   <= inst_rd_size;
                    arlen    <= inst_rd_len;
                    arid     <= ID_INST;
                    arvalid  <= 1'b1;
                end
            end
            if (arvalid && arready) begin
                arvalid <= 1'b0;
            end
        end
    end

    // R 通道
    wire inst_ret_fire = rvalid && rready && inst_rd_ongoing && (rid == ID_INST);
    wire data_ret_fire = rvalid && rready && data_rd_ongoing && (rid == ID_DATA);

    assign inst_ret_valid = inst_ret_fire;
    assign inst_ret_last  = inst_ret_fire && rlast;
    assign inst_ret_data  = rdata;
    assign inst_rd_rdy    = can_accept_ar && !data_read_req;

    always @(posedge aclk) begin
        if (!aresetn) begin
            // 读缓存/类SRAM握手
            inst_rd_ongoing <= 1'b0;
            data_rd_data_ok <= 1'b0;
            data_rd_ongoing <= 1'b0;
            data_rdata      <= 32'h0;
        end else begin
            data_rd_data_ok <= 1'b0;

            // AR 握手
            if (arvalid && arready) begin
                if (arid == ID_INST)
                    inst_rd_ongoing <= 1'b1;
                else if (arid == ID_DATA)
                    data_rd_ongoing <= 1'b1;
            end

            // R 响应：按 ID 分发，缓存并发出 data_ok 脉冲
            if (inst_ret_fire && rlast) begin
                inst_rd_ongoing <= 1'b0;
            end else if (data_ret_fire && rlast) begin
                data_rdata      <= rdata;
                data_rd_data_ok <= 1'b1;
                data_rd_ongoing <= 1'b0;
            end
        end
    end

    // 写通道（AW/W）
    always @(posedge aclk) begin
        if (!aresetn) begin
            data_wr_addr_ok <= 1'b0;
            // AXI 写地址/数据通道
            awvalid <= 1'b0;
            awaddr  <= 32'h0;
            awsize  <= 3'b010;
            awid    <= ID_DATA;
            awlen   <= 8'd0;
            awburst <= 2'b01;
            awlock  <= 2'b00;
            awcache <= 4'b0000;
            awprot  <= 3'b000;
            wvalid  <= 1'b0;
            wid     <= ID_DATA;
            wdata   <= 32'h0;
            wstrb   <= 4'h0;
            wlast   <= 1'b1;
        end else begin
            // AW/W：同步驱动 awvalid/wvalid，保持到握手
            // 两个通道独立握手，均完成后结束本次发送
            data_wr_addr_ok <= 1'b0;
            if (!awvalid && !wvalid && !wr_ongoing) begin
                if (data_req && data_wr) begin
                    data_wr_addr_ok <= 1'b1;
                    awaddr      <= data_addr;
                    awsize      <= {1'b0, data_size};
                    awid        <= ID_DATA;
                    wdata       <= data_wdata;
                    wstrb       <= data_wstrb;
                    wlast       <= 1'b1;
                    awvalid     <= 1'b1;
                    wvalid      <= 1'b1;
                end
            end
            if (awvalid && awready) begin
                awvalid <= 1'b0;
            end
            if (wvalid && wready) begin
                wvalid <= 1'b0;
            end
        end
    end

    // 写响应通道（B）
    always @(posedge aclk) begin
        if (!aresetn) begin
            data_wr_data_ok <= 1'b0;
            wr_ongoing <= 1'b0;
        end else begin
            data_wr_data_ok <= 1'b0;
            // AW/W 握手
            if (!awvalid && !wvalid && !wr_ongoing) begin
                if (data_req && data_wr)
                    wr_ongoing <= 1'b1;
            end
            if (bvalid && bready) begin
                data_wr_data_ok <= 1'b1;
                wr_ongoing <= 1'b0;
            end
        end
    end

endmodule
