`timescale 1ns / 1ps

// key point：
// 1. 4个独立状态机：AR(读地址)、R(读数据)、AW/W(写地址/数据)、B(写响应)
// 2. 所有AXI输出信号直接来自寄存器，避免组合逻辑依赖同通道ready/valid
// 3. 读写分离，支持数据读优先于取指读
// 4. 写后读阻塞：有写在途时阻止读请求发起

module sram_axi_bridge (
    input  wire        aclk,
    input  wire        aresetn,
    
    // 取指类SRAM接口(从方)
    input  wire        inst_req,
    input  wire        inst_wr,
    input  wire [ 1:0] inst_size,
    input  wire [31:0] inst_addr,
    input  wire [ 3:0] inst_wstrb,
    input  wire [31:0] inst_wdata,
    output wire        inst_addr_ok,
    output wire        inst_data_ok,
    output wire [31:0] inst_rdata,
    
    // 数据类SRAM接口(从方)
    input  wire        data_req,
    input  wire        data_wr,
    input  wire [ 1:0] data_size,
    input  wire [31:0] data_addr,
    input  wire [ 3:0] data_wstrb,
    input  wire [31:0] data_wdata,
    output wire        data_addr_ok,
    output wire        data_data_ok,
    output wire [31:0] data_rdata,
    
    // AXI读地址通道(主方)
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output wire        arvalid,
    input  wire        arready,
    
    // AXI读数据通道(从方)
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,
    
    // AXI写地址通道(主方)
    output wire [ 3:0] awid,
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output wire        awvalid,
    input  wire        awready,
    
    // AXI写数据通道(主方)
    output wire [ 3:0] wid,
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    
    // AXI写响应通道(从方)
    input  wire [ 3:0] bid,
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready
);

    // 状态机
    localparam AR_IDLE = 2'd0;  // 读地址通道空闲
    localparam AR_SEND = 2'd1;  // 发送读地址
    
    localparam R_IDLE  = 1'd0;  // 读数据通道空闲
    localparam R_WAIT  = 1'd1;  // 等待读数据
    
    localparam W_IDLE  = 2'd0;  // 写通道空闲
    localparam W_SEND  = 2'd1;  // 发送写地址和数据
    localparam W_RESP  = 2'd2;  // 等待写响应
    
    // 读请求缓存
    reg        inst_rd_req_buf;      // 取指读请求缓存有效
    reg [31:0] inst_rd_addr_buf;     // 取指读地址缓存
    reg [ 2:0] inst_rd_size_buf;     // 取指读大小缓存
    
    reg        data_rd_req_buf;      // 数据读请求缓存有效
    reg [31:0] data_rd_addr_buf;     // 数据读地址缓存
    reg [ 2:0] data_rd_size_buf;     // 数据读大小缓存
    
    // 写请求缓存
    reg        wr_req_buf;           // 写请求缓存有效
    reg [31:0] wr_addr_buf;          // 写地址缓存
    reg [ 2:0] wr_size_buf;          // 写大小缓存
    reg [31:0] wr_data_buf;          // 写数据缓存
    reg [ 3:0] wr_strb_buf;          // 写字节使能缓存
    
    // 读响应缓存
    reg [31:0] inst_rdata_buf;       // 取指返回数据缓存
    reg [31:0] data_rdata_buf;       // 数据返回数据缓存
    
    // 在途标志
    reg        inst_rd_inflight;     // 取指读请求已发送，等待数据
    reg        data_rd_inflight;     // 数据读请求已发送，等待数据
    reg        wr_inflight;          // 写请求已发送，等待响应
    
    // 状态机
    reg [ 1:0] ar_state_curr;        // 读地址通道当前状态
    reg [ 1:0] ar_state_next;        // 读地址通道下一状态
    reg        r_state_curr;         // 读数据通道当前状态
    reg        r_state_next;         // 读数据通道下一状态
    reg [ 1:0] w_state_curr;         // 写通道当前状态
    reg [ 1:0] w_state_next;         // 写通道下一状态

    // AXI读地址通道输出
    reg [ 3:0] arid_r;
    reg [31:0] araddr_r;
    reg [ 7:0] arlen_r;
    reg [ 2:0] arsize_r;
    reg [ 1:0] arburst_r;
    reg [ 1:0] arlock_r;
    reg [ 3:0] arcache_r;
    reg [ 2:0] arprot_r;
    reg        arvalid_r;

    // AXI读数据通道输出
    reg        rready_r;
    
    // AXI写地址通道输出
    reg [ 3:0] awid_r;
    reg [31:0] awaddr_r;
    reg [ 7:0] awlen_r;
    reg [ 2:0] awsize_r;
    reg [ 1:0] awburst_r;
    reg [ 1:0] awlock_r;
    reg [ 3:0] awcache_r;
    reg [ 2:0] awprot_r;
    reg        awvalid_r;

    // AXI写数据通道输出
    reg [ 3:0] wid_r;
    reg [31:0] wdata_r;
    reg [ 3:0] wstrb_r;
    reg        wlast_r;
    reg        wvalid_r;

    // AXI写响应通道输出
    reg        bready_r;

    // 类SRAM握手信号
    reg        inst_addr_ok_r;
    reg        inst_data_ok_r;
    reg        data_addr_ok_r;
    reg        data_data_ok_r;

    assign arid     = arid_r;
    assign araddr   = araddr_r;
    assign arlen    = arlen_r;
    assign arsize   = arsize_r;
    assign arburst  = arburst_r;
    assign arlock   = arlock_r;
    assign arcache  = arcache_r;
    assign arprot   = arprot_r;
    assign arvalid  = arvalid_r;
    
    assign rready   = rready_r;
    
    assign awid     = awid_r;
    assign awaddr   = awaddr_r;
    assign awlen    = awlen_r;
    assign awsize   = awsize_r;
    assign awburst  = awburst_r;
    assign awlock   = awlock_r;
    assign awcache  = awcache_r;
    assign awprot   = awprot_r;
    assign awvalid  = awvalid_r;
    
    assign wid      = wid_r;
    assign wdata    = wdata_r;
    assign wstrb    = wstrb_r;
    assign wlast    = wlast_r;
    assign wvalid   = wvalid_r;
    
    assign bready   = bready_r;
    
    assign inst_addr_ok = inst_addr_ok_r;
    assign inst_data_ok = inst_data_ok_r;
    assign inst_rdata   = inst_rdata_buf;
    
    assign data_addr_ok = data_addr_ok_r;
    assign data_data_ok = data_data_ok_r;
    assign data_rdata   = data_rdata_buf;
    
    // 类SRAM接口请求接收
    // 功能：
    // 1. 接收取指和数据端的读写请求
    // 2. 数据写请求：无写在途时可接收
    // 3. 读请求：无写在途时可接收(写后读阻塞)，数据读优先于取指读
    // 4. 每类请求最多缓存1个
    always @(posedge aclk) begin
        if (!aresetn) begin
            inst_rd_req_buf  <= 1'b0;
            inst_rd_addr_buf <= 32'h0;
            inst_rd_size_buf <= 3'b010;
            data_rd_req_buf  <= 1'b0;
            data_rd_addr_buf <= 32'h0;
            data_rd_size_buf <= 3'b010;
            wr_req_buf       <= 1'b0;
            wr_addr_buf      <= 32'h0;
            wr_size_buf      <= 3'b010;
            wr_data_buf      <= 32'h0;
            wr_strb_buf      <= 4'h0;
            inst_addr_ok_r   <= 1'b0;
            data_addr_ok_r   <= 1'b0;
        end else begin
            // 默认握手信号为0(脉冲信号)
            inst_addr_ok_r <= 1'b0;
            data_addr_ok_r <= 1'b0;
            
            // 写请求接收：无写在途且无写缓存时可接收
            if (data_req && data_wr && !wr_inflight && !wr_req_buf) begin
                wr_req_buf     <= 1'b1;
                wr_addr_buf    <= data_addr;
                wr_size_buf    <= {1'b0, data_size};
                wr_data_buf    <= data_wdata;
                wr_strb_buf    <= data_wstrb;
                data_addr_ok_r <= 1'b1;
            end
            
            // 写请求被发送后，清除缓存
            if (wr_req_buf && w_state_curr == W_IDLE && ar_state_curr == AR_IDLE) begin
                wr_req_buf <= 1'b0;
            end
            
            // 读请求接收：无写在途时可接收
            if (!wr_inflight) begin
                // 数据读请求优先
                if (data_req && !data_wr && !data_rd_req_buf && !data_rd_inflight) begin
                    data_rd_req_buf  <= 1'b1;
                    data_rd_addr_buf <= data_addr;
                    data_rd_size_buf <= {1'b0, data_size};
                    data_addr_ok_r   <= 1'b1;
                end
                // 取指读请求
                else if (inst_req && !inst_wr && !inst_rd_req_buf && !inst_rd_inflight) begin
                    inst_rd_req_buf  <= 1'b1;
                    inst_rd_addr_buf <= inst_addr;
                    inst_rd_size_buf <= {1'b0, inst_size};
                    inst_addr_ok_r   <= 1'b1;
                end
            end
            
            // 取指读请求被发送后，清除缓存
            if (inst_rd_req_buf && ar_state_curr == AR_SEND && arvalid_r && arready && arid_r == 4'd0) begin
                inst_rd_req_buf <= 1'b0;
            end
            
            // 数据读请求被发送后，清除缓存
            if (data_rd_req_buf && ar_state_curr == AR_SEND && arvalid_r && arready && arid_r == 4'd1) begin
                data_rd_req_buf <= 1'b0;
            end
        end
    end

    // AXI读地址通道状态机(AR)
    // 功能：
    // 1. 数据读优先于取指读
    // 2. 无写在途时才能发起读请求(写后读阻塞)
    // 3. 发送读地址请求，设置arid(取指=0，数据=1)

    always @(posedge aclk) begin
        if (!aresetn) begin
            ar_state_curr <= AR_IDLE;
        end else begin
            ar_state_curr <= ar_state_next;
        end
    end

    always @(*) begin
        ar_state_next = ar_state_curr;
        case (ar_state_curr)
            AR_IDLE: begin
                // 无写在途时才能发起读请求
                if (!wr_inflight && !wr_req_buf) begin
                    // 数据读优先或取指读
                    if (data_rd_req_buf || inst_rd_req_buf) begin
                        ar_state_next = AR_SEND;
                    end
                end
            end
            
            AR_SEND: begin
                // 握手成功
                if (arvalid_r && arready) begin
                    ar_state_next = AR_IDLE;
                end
            end
            
            default: begin
                ar_state_next = AR_IDLE;
            end
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            arid_r           <= 4'd0;
            araddr_r         <= 32'h0;
            arlen_r          <= 8'd0;
            arsize_r         <= 3'b010;
            arburst_r        <= 2'b01;
            arlock_r         <= 2'b00;
            arcache_r        <= 4'h0;
            arprot_r         <= 3'h0;
            arvalid_r        <= 1'b0;
        end else begin
            case (ar_state_curr)
                AR_IDLE: begin
                    arvalid_r <= 1'b0;
                    // 无写在途时才能发起读请求
                    if (!wr_inflight && !wr_req_buf) begin
                        // 数据读优先
                        if (data_rd_req_buf) begin
                            arid_r           <= 4'd1;
                            araddr_r         <= data_rd_addr_buf;
                            arsize_r         <= data_rd_size_buf;
                            arlen_r          <= 8'd0;
                            arvalid_r        <= 1'b1;
                        end
                        // 取指读
                        else if (inst_rd_req_buf) begin
                            arid_r           <= 4'd0;
                            araddr_r         <= inst_rd_addr_buf;
                            arsize_r         <= inst_rd_size_buf;
                            arlen_r          <= 8'd0;
                            arvalid_r        <= 1'b1;
                        end
                    end
                end
                
                AR_SEND: begin
                    // 握手成功后清除valid
                    if (arvalid_r && arready) begin
                        arvalid_r <= 1'b0;
                    end
                end
                
                default: begin
                end
            endcase
        end
    end

    // AXI读数据通道R状态机(R)
    // 功能：
    // 1. 有读在途时保持rready为1
    // 2. 根据rid分发数据到取指或数据端
    // 3. 接收到数据后发出data_ok脉冲并清除在途标志

    always @(posedge aclk) begin
        if (!aresetn) begin
            r_state_curr <= R_IDLE;
        end else begin
            r_state_curr <= r_state_next;
        end
    end

    always @(*) begin
        r_state_next = r_state_curr;
        case (r_state_curr)
            R_IDLE: begin
                // 有读在途时进入等待状态
                if (inst_rd_inflight || data_rd_inflight) begin
                    r_state_next = R_WAIT;
                end
            end
            
            R_WAIT: begin
                // 接收到读数据且没有其他读在途，返回空闲
                if (rvalid && rready_r && rlast) begin
                    if (!inst_rd_inflight && !data_rd_inflight) begin
                        r_state_next = R_IDLE;
                    end
                end
            end
            
            default: begin
                r_state_next = R_IDLE;
            end
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rready_r         <= 1'b0;
            inst_rdata_buf   <= 32'h0;
            data_rdata_buf   <= 32'h0;
            inst_data_ok_r   <= 1'b0;
            data_data_ok_r   <= 1'b0;
            inst_rd_inflight <= 1'b0;
            data_rd_inflight <= 1'b0;
        end else begin
            // 默认data_ok为0(脉冲信号)
            inst_data_ok_r <= 1'b0;
            data_data_ok_r <= 1'b0;
            
            // 设置在途标志：当AR通道握手成功时
            if (ar_state_curr == AR_SEND && arvalid_r && arready) begin
                if (arid_r == 4'd0) begin
                    inst_rd_inflight <= 1'b1;
                end else if (arid_r == 4'd1) begin
                    data_rd_inflight <= 1'b1;
                end
            end
            
            // 写完成时产生data_ok
            if (w_state_curr == W_RESP && bvalid && bready_r) begin
                data_data_ok_r <= 1'b1;
            end
            
            case (r_state_curr)
                R_IDLE: begin
                    rready_r <= 1'b0;
                    // 有读在途时准备接收数据
                    if (inst_rd_inflight || data_rd_inflight) begin
                        rready_r <= 1'b1;
                    end
                end
                
                R_WAIT: begin
                    rready_r <= 1'b1;
                    // 接收到读数据
                    if (rvalid && rready_r && rlast) begin
                        // 根据rid分发数据
                        if (rid == 4'd0) begin
                            // 取指读数据
                            inst_rdata_buf <= rdata;
                            inst_data_ok_r <= 1'b1;
                            inst_rd_inflight <= 1'b0;
                        end else if (rid == 4'd1) begin
                            // 数据读数据
                            data_rdata_buf <= rdata;
                            data_data_ok_r <= 1'b1;
                            data_rd_inflight <= 1'b0;
                        end
                        
                        // 如果没有其他读在途，准备返回空闲
                        if (!inst_rd_inflight && !data_rd_inflight) begin
                            rready_r <= 1'b0;
                        end
                    end
                end
                
                default: begin
                end
            endcase
        end
    end
    
    // AXI写通道W状态机(AW/W/B)
    // 功能：
    // 1. 同时发起写地址和写数据
    // 2. 等待两个通道都握手成功
    // 3. 等待写响应
    // 4. 接收到写响应后发出data_ok脉冲
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            w_state_curr <= W_IDLE;
        end else begin
            w_state_curr <= w_state_next;
        end
    end

    always @(*) begin
        w_state_next = w_state_curr;
        case (w_state_curr)
            W_IDLE: begin
                // 有写请求缓存时发起写操作
                if (wr_req_buf) begin
                    w_state_next = W_SEND;
                end
            end
            
            W_SEND: begin
                // 两个通道都握手成功后，等待写响应
                if (!awvalid_r && !wvalid_r) begin
                    w_state_next = W_RESP;
                end
            end
            
            W_RESP: begin
                // 接收到写响应
                if (bvalid && bready_r) begin
                    w_state_next = W_IDLE;
                end
            end
            
            default: begin
                w_state_next = W_IDLE;
            end
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            awid_r       <= 4'd1;
            awaddr_r     <= 32'h0;
            awlen_r      <= 8'd0;
            awsize_r     <= 3'b010;
            awburst_r    <= 2'b01;
            awlock_r     <= 2'b00;
            awcache_r    <= 4'h0;
            awprot_r     <= 3'h0;
            awvalid_r    <= 1'b0;
            wid_r        <= 4'd1;
            wdata_r      <= 32'h0;
            wstrb_r      <= 4'h0;
            wlast_r      <= 1'b1;
            wvalid_r     <= 1'b0;
            bready_r     <= 1'b0;
            wr_inflight  <= 1'b0;
        end else begin
            case (w_state_curr)
                W_IDLE: begin
                    awvalid_r <= 1'b0;
                    wvalid_r  <= 1'b0;
                    bready_r  <= 1'b0;
                    
                    // 有写请求缓存时发起写操作
                    if (wr_req_buf) begin
                        awid_r       <= 4'd1;
                        awaddr_r     <= wr_addr_buf;
                        awsize_r     <= wr_size_buf;
                        awlen_r      <= 8'd0;
                        awvalid_r    <= 1'b1;
                        wid_r        <= 4'd1;
                        wdata_r      <= wr_data_buf;
                        wstrb_r      <= wr_strb_buf;
                        wlast_r      <= 1'b1;
                        wvalid_r     <= 1'b1;
                        wr_inflight  <= 1'b1;
                    end
                end
                
                W_SEND: begin
                    // 写地址握手成功
                    if (awvalid_r && awready) begin
                        awvalid_r <= 1'b0;
                    end
                    // 写数据握手成功
                    if (wvalid_r && wready) begin
                        wvalid_r <= 1'b0;
                    end
                    // 两个通道都握手成功后，准备接收写响应
                    if (!awvalid_r && !wvalid_r) begin
                        bready_r <= 1'b1;
                    end
                end
                
                W_RESP: begin
                    bready_r <= 1'b1;
                    // 接收到写响应
                    if (bvalid && bready_r) begin
                        wr_inflight    <= 1'b0;
                        bready_r       <= 1'b0;
                    end
                end
                
                default: begin
                end
            endcase
        end
    end

endmodule
