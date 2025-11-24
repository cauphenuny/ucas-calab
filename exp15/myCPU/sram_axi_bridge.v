`timescale 1ns / 1ps

// sram_axi_bridge
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

    reg [ 2:0] state, next_state;

    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_I_AR = 3'd1;
    localparam [2:0] STATE_I_R = 3'd2;
    localparam [2:0] STATE_D_AR = 3'd3;
    localparam [2:0] STATE_D_R = 3'd4;
    localparam [2:0] STATE_D_AW = 3'd5;
    localparam [2:0] STATE_D_W = 3'd6;
    localparam [2:0] STATE_D_B = 3'd7;

    reg        pend_is_inst;
    reg        pend_is_write;
    reg [ 1:0] pend_size;
    reg [31:0] pend_addr;
    reg [31:0] pend_wdata;
    reg [ 3:0] pend_wstrb;

    reg aw_done, w_done;
    reg writing;

    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                if (data_req) begin
                    if (data_wr) next_state = STATE_D_AW;
                    else if (!writing) next_state = STATE_D_AR;
                end
                else if (inst_req && !writing)
                    next_state = STATE_I_AR;
            end
            STATE_I_AR: if (arvalid && arready) next_state = STATE_I_R;
            STATE_I_R : if (rvalid && rlast)    next_state = STATE_IDLE;
            STATE_D_AR: if (arvalid && arready) next_state = STATE_D_R;
            STATE_D_R : if (rvalid && rlast)    next_state = STATE_IDLE;
            STATE_D_AW: begin
                if (awvalid && awready && wvalid && wready)
                    next_state = STATE_D_B;
                else if ((awvalid && awready) ^ (wvalid && wready))
                    next_state = STATE_D_W;
                end
            STATE_D_W: begin
                if ((!aw_done && awvalid && awready) || (!w_done && wvalid && wready))
                        next_state = STATE_D_B;
            end
            STATE_D_B: if (bvalid) next_state = STATE_IDLE;
            default: next_state = STATE_IDLE;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= STATE_IDLE;
            pend_is_inst <= 0;
            pend_is_write <= 0;
            pend_size <= 0;
            pend_addr <= 0;
            pend_wdata <= 0;
            pend_wstrb <= 0;
            aw_done <= 0;
            w_done <= 0;
            writing <= 0;
        end else begin
            state <= next_state;
            if (state == STATE_D_AW) begin
                if (awvalid && awready) aw_done <= 1'b1;
                if (wvalid && wready) w_done <= 1'b1;
            end else if (state == STATE_D_W) begin
                if (!aw_done && awvalid && awready) aw_done <= 1'b1;
                if (!w_done && wvalid && wready) w_done <= 1'b1;
            end
            if (!writing && aw_done && w_done) writing <= 1'b1;
            if (state == STATE_D_B && bvalid) begin
                writing <= 1'b0;
                aw_done <= 1'b0;
                w_done <= 1'b0;
            end
            if (state == STATE_IDLE) begin
                if (data_req) begin
                    pend_is_inst  <= 0;
                    pend_is_write <= data_wr;
                    pend_size <= data_size;
                    pend_addr <= data_addr;
                    pend_wdata    <= data_wdata;
                    pend_wstrb <= data_wstrb;
                    aw_done <= 0;
                    w_done <= 0;
                end else if (inst_req && !writing) begin
                    pend_is_inst  <= 1;
                    pend_is_write <= 0;
                    pend_size <= inst_size;
                    pend_addr <= inst_addr;
                    pend_wdata    <= 0;
                    pend_wstrb <= 0;
                end
            end
        end
    end

    always @(*) begin
        arid = 0; awid = 0; wid = 0;
        arlen = 0; awlen = 0;
        arburst = 2'b01; awburst = 2'b01;
        arlock = 0; awlock = 0;
        arcache = 0; awcache = 0;
        arprot = 0; awprot = 0;
        wlast = 1'b1;
        arvalid = 0; awvalid = 0; wvalid = 0;
        rready = 0; bready = 0;
        araddr = 0; awaddr = 0;
        arsize = 3'b010; awsize = 3'b010;
        wdata = 0; wstrb = 0;
        case (state)
            STATE_I_AR, STATE_D_AR: begin
                arvalid = 1'b1;
                araddr  = pend_addr;
                arsize  = {1'b0, pend_size};
            end
            STATE_I_R, STATE_D_R: begin
                rready = 1'b1;
            end
            STATE_D_AW, STATE_D_W: begin
                awaddr  = pend_addr;
                awsize  = {1'b0, pend_size};
                wdata   = pend_wdata;
                wstrb   = pend_wstrb;
                awvalid = !aw_done;
                wvalid  = !w_done;
            end
            STATE_D_B: begin
                bready = 1'b1;
            end
            default: ;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            inst_addr_ok <= 0;
            inst_data_ok <= 0;
            data_addr_ok <= 0;
            data_data_ok <= 0;
            inst_rdata   <= 0;
            data_rdata   <= 0;
        end
        else begin
            inst_addr_ok <= 0;
            inst_data_ok <= 0;
            data_addr_ok <= 0;
            data_data_ok <= 0;
            if (state == STATE_I_AR && arvalid && arready) inst_addr_ok <= 1;
            if (state == STATE_D_AR && arvalid && arready) data_addr_ok <= 1;
            if ((state == STATE_D_AW || state == STATE_D_W) && awvalid && awready) data_addr_ok <= 1;
            if (state == STATE_I_R && rvalid && rlast) begin
                inst_data_ok <= 1;
                inst_rdata   <= rdata;
            end
            if (state == STATE_D_R && rvalid && rlast) begin
                data_data_ok <= 1;
                data_rdata   <= rdata;
            end
            if (state == STATE_D_B && bvalid) data_data_ok <= 1;
        end
    end

endmodule
