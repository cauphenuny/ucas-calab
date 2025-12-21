`timescale 1ns / 1ps

// sram_axi_bridge (multi-channel version)
// - 独立通道状态机：AR、R、AW/W、B
// - 严格保持 AXI 有效握手规则，输出寄存化，避免同通道 ready/valid 的组合依赖
module sram_axi_bridge (
        input  wire        aclk,
        input  wire        aresetn,
        // inst sram side
        input  wire        inst_req,
        input  wire        inst_wr,
        input  wire [ 1:0] inst_size,
        input  wire [31:0] inst_addr,
        input  wire [ 3:0] inst_wstrb,
        input  wire [31:0] inst_wdata,
        output reg         inst_addr_ok,
        output reg         inst_data_ok,
        output reg  [31:0] inst_rdata,
        // data sram side
        input  wire        data_req,
        input  wire        data_wr,
        input  wire [ 1:0] data_size,
        input  wire [31:0] data_addr,
        input  wire [ 3:0] data_wstrb,
        input  wire [31:0] data_wdata,
        output reg         data_addr_ok,
        output reg         data_data_ok,
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
        output reg         rready,
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
        output reg         bready
);

    reg        inst_rd_pending;
    reg [31:0] inst_rd_addr;
    reg [ 1:0] inst_rd_size;
    reg        data_rd_pending;
    reg [31:0] data_rd_addr;
    reg [ 1:0] data_rd_size;

    reg inst_rd_ongoing;
    reg data_rd_ongoing;

    reg        wr_pending;    // 已接收类SRAM写请求，等待发送 AW/W
    reg        wr_inflight;   // 写已发出，等待 B 响应
    reg [31:0] wr_addr;
    reg [ 1:0] wr_size;
    reg [31:0] wr_wdata;
    reg [ 3:0] wr_wstrb;

    reg        inst_rbuf_valid;
    reg [31:0] inst_rbuf_data;
    reg        data_rbuf_valid;
    reg [31:0] data_rbuf_data;

    localparam [0:0] STATE_AR_IDLE = 1'b0, STATE_AR_SEND = 1'b1;
    reg ar_state;

    localparam [0:0] STATE_WR_IDLE = 1'b0, STATE_WR_SEND = 1'b1;
    reg [0:0] wr_state;
    reg       aw_inflight; // awvalid 尚未完成握手
    reg       w_inflight;  // wvalid 尚未完成握手

    localparam [0:0] STATE_B_IDLE = 1'b0, STATE_B_WAIT = 1'b1;
    reg b_state;

    always @(posedge aclk) begin
        if (!aresetn) begin
            inst_rd_pending <= 1'b0;
            data_rd_pending <= 1'b0;
            inst_rd_ongoing <= 1'b0;
            data_rd_ongoing <= 1'b0;
            wr_pending      <= 1'b0;

            // 读缓存/类SRAM握手
            inst_rbuf_valid <= 1'b0;
            inst_rbuf_data  <= 32'h0;
            data_rbuf_valid <= 1'b0;
            data_rbuf_data  <= 32'h0;
            inst_addr_ok    <= 1'b0;
            inst_data_ok    <= 1'b0;
            inst_rdata      <= 32'h0;
            data_addr_ok    <= 1'b0;
            data_data_ok    <= 1'b0;
            data_rdata      <= 32'h0;

            // 写请求暂存
            wr_addr         <= 32'h0;
            wr_size         <= 2'b00;
            wr_wdata        <= 32'h0;
            wr_wstrb        <= 4'h0;

            // AXI 读响应通道
            rready  <= 1'b0; // 复位期 ready 非 X
        end else begin
            inst_addr_ok <= 1'b0;
            inst_data_ok <= 1'b0;
            data_addr_ok <= 1'b0;
            data_data_ok <= 1'b0;
            inst_rbuf_valid <= 1'b0;
            data_rbuf_valid <= 1'b0;

            // 写请求接受：仅当无在途写，且写通道空闲
            if (data_req && data_wr && !wr_inflight
                && (wr_state==STATE_WR_IDLE) && !wr_pending) begin
                wr_pending   <= 1'b1;
                wr_addr      <= data_addr;
                wr_size      <= data_size;
                wr_wdata     <= data_wdata;
                wr_wstrb     <= data_wstrb;
                data_addr_ok <= 1'b1;
            end

            // 读请求接受：无写在途（RAW 阻塞），各自仅 1 个 pending
            if (!wr_inflight) begin
                // 数据读优先
                if (data_req && !data_wr && !data_rd_pending && !data_rd_ongoing) begin
                    data_rd_pending <= 1'b1;
                    data_rd_addr    <= data_addr;
                    data_rd_size    <= data_size;
                    data_addr_ok    <= 1'b1;
                end else if (inst_req && !inst_wr && !inst_rd_pending && !inst_rd_ongoing) begin
                    inst_rd_pending <= 1'b1;
                    inst_rd_addr    <= inst_addr;
                    inst_rd_size    <= inst_size;
                    inst_addr_ok    <= 1'b1;
                end
            end

            // AR 握手完成后，更新 pending/ongoing
            if (arvalid && arready) begin
                if (arid==4'd1) begin
                    data_rd_pending <= 1'b0;
                    data_rd_ongoing <= 1'b1;
                end else begin
                    inst_rd_pending <= 1'b0;
                    inst_rd_ongoing <= 1'b1;
                end
            end

            // rready 仅在任一读在途时拉高
            rready <= (inst_rd_ongoing || data_rd_ongoing);

            // R 响应：按 ID 分发，缓存并发出 data_ok 脉冲
            if (rvalid && rready && rlast) begin
                if (rid==4'd0) begin
                    inst_rbuf_valid <= 1'b1;
                    inst_rbuf_data  <= rdata;
                    inst_rdata      <= rdata;
                    inst_data_ok    <= 1'b1;
                    inst_rd_ongoing <= 1'b0;
                end else if (rid==4'd1) begin
                    data_rbuf_valid <= 1'b1;
                    data_rbuf_data  <= rdata;
                    data_rdata      <= rdata;
                    data_data_ok    <= 1'b1;
                    data_rd_ongoing <= 1'b0;
                end
            end

            // B 响应到来（写完成）也需要对 data 端口发出 data_ok 脉冲
            if (bvalid && wr_inflight) begin
                data_data_ok <= 1'b1;
            end

            if (wr_state==STATE_WR_IDLE && wr_pending) begin
                wr_pending <= 1'b0;
            end
        end
    end

    // AR 通道：仅驱动 AXI 读地址握手信号
    always @(posedge aclk) begin
        if (!aresetn) begin
            arvalid <= 1'b0;
            araddr  <= 32'h0;
            arsize  <= 3'b010;
            arid    <= 4'd0;
            arlen   <= 8'd0;
            arburst <= 2'b01;
            arlock  <= 2'b00;
            arcache <= 4'b0000;
            arprot  <= 3'b000;
            ar_state<= STATE_AR_IDLE;
        end else begin
            case (ar_state)
                STATE_AR_IDLE: begin
                    arvalid <= 1'b0;
                    if (!wr_inflight) begin
                        // 数据读优先：支持立即发起（同拍）或使用挂起
                        if (data_rd_pending || (data_req && !data_wr && !data_rd_ongoing)) begin
                            araddr   <= data_rd_pending ? data_rd_addr : data_addr;
                            arsize   <= data_rd_pending ? {1'b0, data_rd_size} : {1'b0, data_size};
                            arid     <= 4'd1;
                            arvalid  <= 1'b1;
                            ar_state <= STATE_AR_SEND;
                        end else if (inst_rd_pending ||
                                     (inst_req && !inst_wr && !inst_rd_ongoing)) begin
                            araddr   <= inst_rd_pending ? inst_rd_addr : inst_addr;
                            arsize   <= inst_rd_pending ? {1'b0, inst_rd_size} : {1'b0, inst_size};
                            arid     <= 4'd0;
                            arvalid  <= 1'b1;
                            ar_state <= STATE_AR_SEND;
                        end
                    end
                end
                STATE_AR_SEND: begin
                    if (arvalid && arready) begin
                        arvalid  <= 1'b0;
                        ar_state <= STATE_AR_IDLE;
                    end
                end
                default: begin
                    ar_state <= STATE_AR_IDLE;
                end
            endcase
        end
    end

    // 写通道（AW/W）与写响应通道（B）
    always @(posedge aclk) begin
        if (!aresetn) begin
            // AXI 写地址/数据通道
            awvalid <= 1'b0;
            awaddr  <= 32'h0;
            awsize  <= 3'b010;
            awid    <= 4'd1;
            awlen   <= 8'd0;
            awburst <= 2'b01;
            awlock  <= 2'b00;
            awcache <= 4'b0000;
            awprot  <= 3'b000;
            wvalid  <= 1'b0;
            wid     <= 4'd1;
            wdata   <= 32'h0;
            wstrb   <= 4'h0;
            wlast   <= 1'b1;
            wr_state    <= STATE_WR_IDLE;
            aw_inflight <= 1'b0;
            w_inflight  <= 1'b0;
            wr_inflight <= 1'b0;

            // AXI 写响应通道
            bready  <= 1'b0; // 复位期 ready 非 X
            b_state <= STATE_B_IDLE;

        end else begin
            // AW/W：同步驱动 awvalid/wvalid，保持到握手
            // 两个通道独立握手，均完成后结束本次发送
            case (wr_state)
                STATE_WR_IDLE: begin
                    awvalid     <= 1'b0;
                    wvalid      <= 1'b0;
                    aw_inflight <= 1'b0;
                    w_inflight  <= 1'b0;
                    if (wr_pending) begin
                        awaddr      <= wr_addr;
                        awsize      <= {1'b0, wr_size};
                        awid        <= 4'd1;
                        wdata       <= wr_wdata;
                        wstrb       <= wr_wstrb;
                        wlast       <= 1'b1;
                        awvalid     <= 1'b1;
                        wvalid      <= 1'b1;
                        aw_inflight <= 1'b1;
                        w_inflight  <= 1'b1;
                        wr_inflight <= 1'b1;
                        wr_state    <= STATE_WR_SEND;
                    end
                end
                STATE_WR_SEND: begin
                    if (aw_inflight && awvalid && awready) begin
                        awvalid     <= 1'b0;
                        aw_inflight <= 1'b0;
                    end
                    if (w_inflight && wvalid && wready) begin
                        wvalid     <= 1'b0;
                        w_inflight <= 1'b0;
                    end
                    if (!aw_inflight && !w_inflight) begin
                        wr_state <= STATE_WR_IDLE;
                    end
                end
                default: begin
                    wr_state <= STATE_WR_IDLE;
                end
            endcase

            // B 响应：在写时保持 ready，接收响应
            case (b_state)
                STATE_B_IDLE: begin
                    bready <= 1'b0;
                    if (wr_inflight) begin
                        bready  <= 1'b1;
                        b_state <= STATE_B_WAIT;
                    end
                end
                STATE_B_WAIT: begin
                    bready <= 1'b1;
                    if (bvalid) begin
                        wr_inflight <= 1'b0;
                        b_state     <= STATE_B_IDLE;
                    end
                end
                default: begin
                    b_state <= STATE_B_IDLE;
                end
            endcase
        end
    end

endmodule
