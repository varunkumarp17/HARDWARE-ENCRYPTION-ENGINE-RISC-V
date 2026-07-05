//-----------------------------------------------------------------
// axi4_cdc.v  (passthrough version for Boolean board)
//
// Replaces the original axi4_cdc.v which instantiated the
// Xilinx axi_cdc_buffer IP (deleted since no DDR3 is present).
//
// WHY THIS IS SAFE:
//   On the Arty, the SoC ran at 25MHz and DDR3 at 100MHz, so a
//   proper CDC FIFO was needed.
//   On the Boolean board, boolean_bram.clk_out_o = 100MHz and
//   boolean_top drives both clk_i and clk_sys_i from the same
//   100MHz source. wr_clk_i and rd_clk_i are therefore identical,
//   so this passthrough is functionally correct.
//
// Port list is 100% identical to original axi4_cdc.v so fpga_top.v
// requires zero changes.
//-----------------------------------------------------------------

module axi4_cdc
(
    // Write-side clock/reset (now same as read-side)
     input           wr_clk_i
    ,input           wr_rst_i

    // AXI4 slave (from SoC)
    ,input           inport_awvalid_i
    ,input  [ 31:0]  inport_awaddr_i
    ,input  [  3:0]  inport_awid_i
    ,input  [  7:0]  inport_awlen_i
    ,input  [  1:0]  inport_awburst_i
    ,input           inport_wvalid_i
    ,input  [ 31:0]  inport_wdata_i
    ,input  [  3:0]  inport_wstrb_i
    ,input           inport_wlast_i
    ,input           inport_bready_i
    ,input           inport_arvalid_i
    ,input  [ 31:0]  inport_araddr_i
    ,input  [  3:0]  inport_arid_i
    ,input  [  7:0]  inport_arlen_i
    ,input  [  1:0]  inport_arburst_i
    ,input           inport_rready_i

    // Read-side clock/reset (same signal as wr_clk_i on Boolean)
    ,input           rd_clk_i
    ,input           rd_rst_i

    // AXI4 master responses (from BRAM)
    ,input           outport_awready_i
    ,input           outport_wready_i
    ,input           outport_bvalid_i
    ,input  [  1:0]  outport_bresp_i
    ,input  [  3:0]  outport_bid_i
    ,input           outport_arready_i
    ,input           outport_rvalid_i
    ,input  [ 31:0]  outport_rdata_i
    ,input  [  1:0]  outport_rresp_i
    ,input  [  3:0]  outport_rid_i
    ,input           outport_rlast_i

    // Slave responses back to SoC
    ,output          inport_awready_o
    ,output          inport_wready_o
    ,output          inport_bvalid_o
    ,output [  1:0]  inport_bresp_o
    ,output [  3:0]  inport_bid_o
    ,output          inport_arready_o
    ,output          inport_rvalid_o
    ,output [ 31:0]  inport_rdata_o
    ,output [  1:0]  inport_rresp_o
    ,output [  3:0]  inport_rid_o
    ,output          inport_rlast_o

    // Master requests to BRAM
    ,output          outport_awvalid_o
    ,output [ 31:0]  outport_awaddr_o
    ,output [  3:0]  outport_awid_o
    ,output [  7:0]  outport_awlen_o
    ,output [  1:0]  outport_awburst_o
    ,output          outport_wvalid_o
    ,output [ 31:0]  outport_wdata_o
    ,output [  3:0]  outport_wstrb_o
    ,output          outport_wlast_o
    ,output          outport_bready_o
    ,output          outport_arvalid_o
    ,output [ 31:0]  outport_araddr_o
    ,output [  3:0]  outport_arid_o
    ,output [  7:0]  outport_arlen_o
    ,output [  1:0]  outport_arburst_o
    ,output          outport_rready_o
);

//-------------------------------------------------------------
// Direct wire-through: inport -> outport (request path)
//-------------------------------------------------------------
assign outport_awvalid_o = inport_awvalid_i;
assign outport_awaddr_o  = inport_awaddr_i;
assign outport_awid_o    = inport_awid_i;
assign outport_awlen_o   = inport_awlen_i;
assign outport_awburst_o = inport_awburst_i;

assign outport_wvalid_o  = inport_wvalid_i;
assign outport_wdata_o   = inport_wdata_i;
assign outport_wstrb_o   = inport_wstrb_i;
assign outport_wlast_o   = inport_wlast_i;

assign outport_bready_o  = inport_bready_i;

assign outport_arvalid_o = inport_arvalid_i;
assign outport_araddr_o  = inport_araddr_i;
assign outport_arid_o    = inport_arid_i;
assign outport_arlen_o   = inport_arlen_i;
assign outport_arburst_o = inport_arburst_i;

assign outport_rready_o  = inport_rready_i;

//-------------------------------------------------------------
// Direct wire-through: outport -> inport (response path)
//-------------------------------------------------------------
assign inport_awready_o  = outport_awready_i;
assign inport_wready_o   = outport_wready_i;

assign inport_bvalid_o   = outport_bvalid_i;
assign inport_bresp_o    = outport_bresp_i;
assign inport_bid_o      = outport_bid_i;

assign inport_arready_o  = outport_arready_i;

assign inport_rvalid_o   = outport_rvalid_i;
assign inport_rdata_o    = outport_rdata_i;
assign inport_rresp_o    = outport_rresp_i;
assign inport_rid_o      = outport_rid_i;
assign inport_rlast_o    = outport_rlast_i;

endmodule