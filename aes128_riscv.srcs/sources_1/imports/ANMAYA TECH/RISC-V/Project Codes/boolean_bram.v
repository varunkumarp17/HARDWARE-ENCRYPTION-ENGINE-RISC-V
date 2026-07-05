//-----------------------------------------------------------------
// boolean_bram.v  (v2 - proper BRAM inference)
// AXI4 BRAM Memory Controller for Boolean Board (Spartan-7 XC7S50)
//
// KEY FIX vs v1: Memory split into 4 separate byte-wide arrays.
// This is the ONLY pattern Vivado reliably infers as Block RAM with
// byte write enables. The monolithic 32-bit array with conditional
// byte assignments was being mapped to 178K LUTs instead of BRAMs.
//
// Memory size: 128KB (32768 x 32-bit words)
//   - Uses ~32 RAMB36 tiles out of 75 available on XC7S50
//   - Sufficient for RISC-V bare-metal / embedded Linux image
//
// Read latency: 1 cycle (synchronous BRAM read)
//   - AXI read FSM adds a RD_WAIT state to absorb this latency
//-----------------------------------------------------------------

module boolean_bram (
    input           clk100_i,
    input           clk200_i,       // unused, kept for compatibility

    // AXI4 Write Address
    input           inport_awvalid_i,
    input  [31:0]   inport_awaddr_i,
    input  [ 3:0]   inport_awid_i,
    input  [ 7:0]   inport_awlen_i,
    input  [ 1:0]   inport_awburst_i,

    // AXI4 Write Data
    input           inport_wvalid_i,
    input  [31:0]   inport_wdata_i,
    input  [ 3:0]   inport_wstrb_i,
    input           inport_wlast_i,

    // AXI4 Write Response
    input           inport_bready_i,

    // AXI4 Read Address
    input           inport_arvalid_i,
    input  [31:0]   inport_araddr_i,
    input  [ 3:0]   inport_arid_i,
    input  [ 7:0]   inport_arlen_i,
    input  [ 1:0]   inport_arburst_i,

    // AXI4 Read Data
    input           inport_rready_i,

    // Clock/reset outputs
    output          clk_out_o,
    output          rst_out_o,

    output          inport_awready_o,
    output          inport_wready_o,
    output          inport_bvalid_o,
    output [ 1:0]   inport_bresp_o,
    output [ 3:0]   inport_bid_o,

    output          inport_arready_o,
    output          inport_rvalid_o,
    output [31:0]   inport_rdata_o,
    output [ 1:0]   inport_rresp_o,
    output [ 3:0]   inport_rid_o,
    output          inport_rlast_o
);

//-------------------------------------------------------------
// Parameters: 128KB = 32768 x 32-bit words
// Each byte lane: 32768 x 8 bits = 8 x RAMB36 = 32 total RAMB36
//-------------------------------------------------------------
localparam MEM_DEPTH = 32768;
localparam ADDR_BITS = 15;   // log2(MEM_DEPTH)

//-------------------------------------------------------------
// 4 separate byte-lane Block RAMs
// Vivado infers BRAM when:
//   1. Write enable controls entire array write (not a slice)
//   2. Read is synchronous (registered output)
//   3. (* ram_style = "block" *) attribute forces BRAM mapping
//-------------------------------------------------------------
(* ram_style = "block" *) reg [7:0] mem0 [0:MEM_DEPTH-1]; // bits  7: 0
(* ram_style = "block" *) reg [7:0] mem1 [0:MEM_DEPTH-1]; // bits 15: 8
(* ram_style = "block" *) reg [7:0] mem2 [0:MEM_DEPTH-1]; // bits 23:16
(* ram_style = "block" *) reg [7:0] mem3 [0:MEM_DEPTH-1]; // bits 31:24

reg [31:0] bram_rdata;

//-------------------------------------------------------------
// Reset generator
//-------------------------------------------------------------
reg [7:0] rst_cnt = 8'h00;
always @(posedge clk100_i)
    if (rst_cnt != 8'hFF)
        rst_cnt <= rst_cnt + 8'd1;

wire sys_ready = &rst_cnt;

assign clk_out_o = clk100_i;
assign rst_out_o = ~sys_ready;

//-------------------------------------------------------------
// BRAM write and read ports (both synchronous)
//-------------------------------------------------------------
reg [ADDR_BITS-1:0] bram_waddr;
reg [31:0]          bram_wdata;
reg [ 3:0]          bram_we;
reg [ADDR_BITS-1:0] bram_raddr;

// Write (4 separate enables = proper BRAM with byte enables)
always @(posedge clk100_i) begin
    if (bram_we[0]) mem0[bram_waddr] <= bram_wdata[ 7: 0];
    if (bram_we[1]) mem1[bram_waddr] <= bram_wdata[15: 8];
    if (bram_we[2]) mem2[bram_waddr] <= bram_wdata[23:16];
    if (bram_we[3]) mem3[bram_waddr] <= bram_wdata[31:24];
end

// Read (registered - 1 cycle latency)
always @(posedge clk100_i)
    bram_rdata <= { mem3[bram_raddr],
                    mem2[bram_raddr],
                    mem1[bram_raddr],
                    mem0[bram_raddr] };

//=============================================================
// Write FSM
//=============================================================
localparam WR_IDLE = 2'd0,
           WR_DATA = 2'd1,
           WR_RESP = 2'd2;

reg [1:0] wr_state;
reg [31:0] wr_addr;
reg [ 3:0] wr_id;

assign inport_awready_o = (wr_state == WR_IDLE) & sys_ready;
assign inport_wready_o  = (wr_state == WR_DATA) & sys_ready;
assign inport_bvalid_o  = (wr_state == WR_RESP);
assign inport_bresp_o   = 2'b00;
assign inport_bid_o     = wr_id;

always @(posedge clk100_i) begin
    bram_we <= 4'b0;

    if (!sys_ready) begin
        wr_state <= WR_IDLE;
    end else begin
        case (wr_state)
        WR_IDLE:
            if (inport_awvalid_i & inport_awready_o) begin
                wr_addr  <= inport_awaddr_i;
                wr_id    <= inport_awid_i;
                wr_state <= WR_DATA;
            end

        WR_DATA:
            if (inport_wvalid_i & inport_wready_o) begin
                bram_waddr <= wr_addr[ADDR_BITS+1:2];
                bram_wdata <= inport_wdata_i;
                bram_we    <= inport_wstrb_i;
                wr_addr    <= wr_addr + 32'd4;
                if (inport_wlast_i)
                    wr_state <= WR_RESP;
            end

        WR_RESP:
            if (inport_bvalid_o & inport_bready_i)
                wr_state <= WR_IDLE;

        default: wr_state <= WR_IDLE;
        endcase
    end
end

//=============================================================
// Read FSM
// BRAM has 1-cycle synchronous read latency.
// RD_WAIT absorbs the latency before asserting rvalid.
//=============================================================
localparam RD_IDLE  = 2'd0,
           RD_WAIT  = 2'd1,   // BRAM pipeline delay cycle
           RD_VALID = 2'd2;

reg [1:0] rd_state;
reg [31:0] rd_addr;
reg [ 7:0] rd_len;
reg [ 7:0] rd_cnt;
reg [ 3:0] rd_id;
reg        rd_valid;
reg        rd_last;

assign inport_arready_o = (rd_state == RD_IDLE) & sys_ready;
assign inport_rvalid_o  = rd_valid;
assign inport_rdata_o   = bram_rdata;
assign inport_rresp_o   = 2'b00;
assign inport_rid_o     = rd_id;
assign inport_rlast_o   = rd_last;

always @(posedge clk100_i) begin
    rd_valid <= 1'b0;

    if (!sys_ready) begin
        rd_state <= RD_IDLE;
    end else begin
        case (rd_state)

        RD_IDLE:
            if (inport_arvalid_i & inport_arready_o) begin
                rd_addr    <= inport_araddr_i;
                rd_len     <= inport_arlen_i;
                rd_cnt     <= 8'd0;
                rd_id      <= inport_arid_i;
                rd_last    <= (inport_arlen_i == 8'd0);
                bram_raddr <= inport_araddr_i[ADDR_BITS+1:2];
                rd_state   <= RD_WAIT;
            end

        RD_WAIT: begin
            // BRAM output is now valid
            rd_valid <= 1'b1;
            rd_state <= RD_VALID;
        end

        RD_VALID:
            if (inport_rvalid_o & inport_rready_i) begin
                if (rd_last) begin
                    rd_valid <= 1'b0;
                    rd_state <= RD_IDLE;
                end else begin
                    // Advance to next burst word
                    rd_addr    <= rd_addr + 32'd4;
                    rd_cnt     <= rd_cnt + 8'd1;
                    rd_last    <= (rd_cnt + 8'd1 == rd_len);
                    bram_raddr <= (rd_addr + 32'd4) >> 2;
                    rd_valid   <= 1'b0;
                    rd_state   <= RD_WAIT;
                end
            end

        default: rd_state <= RD_IDLE;
        endcase
    end
end

endmodule