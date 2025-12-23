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
        output wire        inst_addr_ok,
        output reg         inst_data_ok,
        output reg  [31:0] inst_rdata,
        // data sram side
        input  wire        data_req,
        input  wire        data_wr,
        input  wire [ 1:0] data_size,
        input  wire [31:0] data_addr,
        input  wire [ 3:0] data_wstrb,
        input  wire [31:0] data_wdata,
        output wire        data_addr_ok,
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

    reg inst_rd_ongoing;
    reg data_rd_ongoing;

    reg        wr_pending;    // 已接收类SRAM写请求，等待发送 AW/W
    reg        wr_inflight;   // 写已发出，等待 B 响应
    reg [31:0] wr_addr;
    reg [ 1:0] wr_size;
    reg [31:0] wr_wdata;
    reg [ 3:0] wr_wstrb;

    reg inst_rd_addr_ok;
    reg data_rd_addr_ok, data_wr_addr_ok;

    assign inst_addr_ok = inst_rd_addr_ok;
    assign data_addr_ok = data_rd_addr_ok || data_wr_addr_ok;

    localparam [3:0] ID_INST = 4'd0,
                     ID_DATA = 4'd1;

    localparam [1:0] STATE_AR_IDLE = 2'b00,
                     STATE_AR_DATA = 2'b01,
                     STATE_AR_INST = 2'b10;
    reg [1:0] ar_state, ar_next;

    localparam  STATE_WR_IDLE = 1'b0,
                STATE_WR_SEND = 1'b1;
    reg wr_state, wr_next;

    reg       aw_inflight; // awvalid 尚未完成握手
    reg       w_inflight;  // wvalid 尚未完成握手

    localparam  STATE_B_IDLE = 1'b0,
                STATE_B_WAIT = 1'b1;
    reg b_state, b_next;

    always @(posedge aclk) begin
        if (!aresetn) ;
        else begin
            inst_data_ok <= 1'b0;
            data_data_ok <= 1'b0;
        end
    end

    // AR 通道：仅驱动 AXI 读地址握手信号
    always @(posedge aclk) begin
        if (!aresetn)
            ar_state <= STATE_AR_IDLE;
        else
            ar_state <= ar_next;
    end

    always @(*) begin
        case (ar_state)
            STATE_AR_IDLE:
                ar_next = (!wr_inflight) ? (
                    (data_req && !data_wr && !data_rd_ongoing) ? STATE_AR_DATA :
                    (inst_req && !inst_wr && !inst_rd_ongoing) ? STATE_AR_INST : STATE_AR_IDLE
                ) : STATE_AR_IDLE;
            STATE_AR_DATA:
                ar_next = (arvalid && arready) ? STATE_AR_IDLE : STATE_AR_DATA;
            STATE_AR_INST:
                ar_next = (arvalid && arready) ? STATE_AR_IDLE : STATE_AR_INST;
            default:
                ar_next = STATE_AR_IDLE;
        endcase
    end

    // ar_state 等于 arvalid

    always @(posedge aclk) begin
        if (!aresetn) begin
            inst_rd_addr_ok <= 1'b0;
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
            inst_rd_addr_ok <= 1'b0;
            data_rd_addr_ok <= 1'b0;
            case (ar_state)
                STATE_AR_IDLE: begin
                    arvalid <= 1'b0;
                    if (!wr_inflight) begin
                        // 数据读优先：支持立即发起（同拍）或使用挂起
                        if (data_req && !data_wr && !data_rd_ongoing) begin
                            data_rd_addr_ok <= 1'b1;
                            araddr   <= data_addr;
                            arsize   <= {1'b0, data_size};
                            arid     <= ID_DATA;
                            arvalid  <= 1'b1;
                        end else if (inst_req && !inst_wr && !inst_rd_ongoing) begin
                            inst_rd_addr_ok <= 1'b1;
                            araddr   <= inst_addr;
                            arsize   <= {1'b0, inst_size};
                            arid     <= ID_INST;
                            arvalid  <= 1'b1;
                        end
                    end
                end
                STATE_AR_DATA,
                STATE_AR_INST: begin
                    if (arvalid && arready)
                        arvalid  <= 1'b0;
                end
                default:
                    ;
            endcase
        end
    end

    // R 通道

    always @(posedge aclk) begin
        if (!aresetn) begin
            // 读缓存/类SRAM握手
            inst_data_ok    <= 1'b0;
            inst_rdata      <= 32'h0;
            data_data_ok    <= 1'b0;
            data_rdata      <= 32'h0;
            inst_rd_ongoing <= 1'b0;
            data_rd_ongoing <= 1'b0;
            // AXI 读响应通道
            rready  <= 1'b0; // 复位期 ready 非 X
        end else begin

            // rready 仅在任一读在途时拉高
            rready <= (inst_rd_ongoing || data_rd_ongoing);
            if (arvalid && arready) begin
                if (arid == ID_INST)
                    inst_rd_ongoing <= 1'b1;
                else if (arid == ID_DATA)
                    data_rd_ongoing <= 1'b1;
            end

            // R 响应：按 ID 分发，缓存并发出 data_ok 脉冲
            if (rvalid && rready && rlast) begin
                if (rid == ID_INST) begin
                    inst_rdata      <= rdata;
                    inst_data_ok    <= 1'b1;
                    inst_rd_ongoing <= 1'b0;
                end else if (rid == ID_DATA) begin
                    data_rdata      <= rdata;
                    data_data_ok    <= 1'b1;
                    data_rd_ongoing <= 1'b0;
                end
            end else
            // B 响应到来（写完成）也需要对 data 端口发出 data_ok 脉冲
            if (bvalid && wr_inflight) begin
                inst_data_ok <= 1'b0;
                data_data_ok <= 1'b1;
            end else begin
                inst_data_ok <= 1'b0;
                data_data_ok <= 1'b0;
            end
        end
    end

    // 写通道（AW/W）
    always @(posedge aclk) begin
        if (!aresetn)
            wr_state <= STATE_WR_IDLE;
        else
            wr_state <= wr_next;
    end

    always @(*) begin
        case (wr_state)
            STATE_WR_IDLE:
                wr_next = wr_pending ? STATE_WR_SEND : STATE_WR_IDLE;
            STATE_WR_SEND:
                wr_next = (!aw_inflight && !w_inflight) ? STATE_WR_IDLE : STATE_WR_SEND;
            default:
                wr_next = STATE_WR_IDLE;
        endcase
    end

    // wr_state 差不多就是 aw_inflight || w_inflight

    always @(posedge aclk) begin
        if (!aresetn) begin
            data_wr_addr_ok <= 1'b0;
            // 写请求暂存
            wr_pending      <= 1'b0;
            wr_addr         <= 32'h0;
            wr_size         <= 2'b00;
            wr_wdata        <= 32'h0;
            wr_wstrb        <= 4'h0;
        end else begin
            data_wr_addr_ok <= 1'b0;
            // 写请求接受：仅当无在途写，且写通道空闲
            if (data_req && data_wr && !wr_inflight
                && (wr_state==STATE_WR_IDLE) && !wr_pending) begin
                wr_pending   <= 1'b1;
                wr_addr      <= data_addr;
                wr_size      <= data_size;
                wr_wdata     <= data_wdata;
                wr_wstrb     <= data_wstrb;
                data_wr_addr_ok <= 1'b1;
            end

            if (wr_state==STATE_WR_IDLE && wr_pending) begin
                wr_pending <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
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
            aw_inflight <= 1'b0;
            w_inflight  <= 1'b0;
            wr_inflight <= 1'b0;

        end else begin
            // AW/W：同步驱动 awvalid/wvalid，保持到握手
            // 两个通道独立握手，均完成后结束本次发送
            case (wr_state)
                STATE_WR_IDLE: begin
                    if (wr_pending) begin
                        awaddr      <= wr_addr;
                        awsize      <= {1'b0, wr_size};
                        awid        <= ID_DATA;
                        wdata       <= wr_wdata;
                        wstrb       <= wr_wstrb;
                        wlast       <= 1'b1;
                        awvalid     <= 1'b1;
                        wvalid      <= 1'b1;
                        aw_inflight <= 1'b1;
                        w_inflight  <= 1'b1;
                        wr_inflight <= 1'b1;
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
                end
                default: ;
            endcase

        end
    end

    // 写响应通道（B）

    always @(posedge aclk) begin
        if (!aresetn)
            b_state <= STATE_B_IDLE;
        else
            b_state <= b_next;
    end

    always @(*) begin
        case (b_state)
            STATE_B_IDLE:
                b_next = wr_inflight ? STATE_B_WAIT : STATE_B_IDLE;
            STATE_B_WAIT:
                b_next = bvalid ? STATE_B_IDLE : STATE_B_WAIT;
            default:
                b_next = STATE_B_IDLE;
        endcase
    end

    // b_state 差不多等于 wr_inflight，bready

    always @(posedge aclk) begin
        if (!aresetn) begin
            // AXI 写响应通道
            bready  <= 1'b0;
        end else begin
            // B 响应：在写时保持 ready，接收响应
            case (b_state)
                STATE_B_IDLE: begin
                    bready <= 1'b0;
                    if (wr_inflight) begin
                        bready  <= 1'b1;
                    end
                end
                STATE_B_WAIT: begin
                    bready <= 1'b1;
                    if (bvalid) begin
                        wr_inflight <= 1'b0;
                    end
                end
                default: ;
            endcase
        end
    end

endmodule
