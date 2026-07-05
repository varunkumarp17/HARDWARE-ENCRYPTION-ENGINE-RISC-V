//-----------------------------------------------------------------
// boolean_top.v
// Top-level module for Boolean Board (Spartan-7 XC7S50-CSGA324)
//
// Ported from top.v (originally Digilent Arty A7 with DDR3)
// Changes vs original top.v:
//   1. All ddr3_* I/O ports REMOVED (Boolean board has no DDR3)
//   2. arty_ddr instantiation REPLACED with boolean_bram
//   3. qspi_* ports REMOVED (not on Boolean)
//   4. Clock pin is now F14 (Boolean 100MHz MEMS oscillator)
//   5. LED/UART pins updated for Boolean board pinout
//-----------------------------------------------------------------

module top (
    input           clk100mhz,      // F14 on Boolean board

    // LEDs (active high on Boolean)
    output [3:0]    led,

    // UART via PROG/UART USB connector
    output          uart_rxd_out,   // FPGA TX -> PC RX
    input           uart_txd_in     // PC TX  -> FPGA RX
);

//-----------------------------------------------------------------
// PLL: 100MHz -> 100MHz (clk0), 200MHz (clk1), 25MHz (clk_w)
//-----------------------------------------------------------------
wire clk0;      // 100 MHz  - system / BRAM clock
wire clk1;      // 200 MHz  - unused (was MIG ref clock)
wire clk_w;     // 25  MHz  - peripheral / CPU clock

artix7_pll u_pll (
    .clkref_i  (clk100mhz),
    .clkout0_o (clk0),
    .clkout1_o (clk1),
    .clkout2_o (clk_w)
);

//-----------------------------------------------------------------
// AXI4 interconnect wires (between fpga_top and boolean_bram)
//-----------------------------------------------------------------
wire           axi_rvalid_w;
wire           axi_wlast_w;
wire           axi_rlast_w;
wire  [ 3:0]   axi_arid_w;
wire  [ 1:0]   axi_rresp_w;
wire           axi_wvalid_w;
wire  [ 7:0]   axi_awlen_w;
wire  [ 1:0]   axi_awburst_w;
wire  [ 1:0]   axi_bresp_w;
wire  [31:0]   axi_rdata_w;
wire           axi_arready_w;
wire           axi_awvalid_w;
wire  [31:0]   axi_araddr_w;
wire  [ 1:0]   axi_arburst_w;
wire           axi_wready_w;
wire  [ 7:0]   axi_arlen_w;
wire           axi_awready_w;
wire  [ 3:0]   axi_bid_w;
wire  [ 3:0]   axi_wstrb_w;
wire  [ 3:0]   axi_awid_w;
wire           axi_rready_w;
wire  [ 3:0]   axi_rid_w;
wire           axi_arvalid_w;
wire  [31:0]   axi_awaddr_w;
wire           axi_bvalid_w;
wire           axi_bready_w;
wire  [31:0]   axi_wdata_w;

//-----------------------------------------------------------------
// BRAM memory controller
// Replaces arty_ddr (MIG DDR3 wrapper) from the Arty design.
// Provides 256KB of AXI4-accessible Block RAM.
// clk_out_o  -> system clock for the SoC core
// rst_out_o  -> active-high reset for the SoC core
//-----------------------------------------------------------------
wire clk_sys_w;
wire rst_sys_w;

boolean_bram u_mem (
    .clk100_i            (clk_w),        // 25 MHz - BRAM runs fine at this speed
    .clk200_i            (clk1),

    // Write address
    .inport_awvalid_i    (axi_awvalid_w),
    .inport_awaddr_i     (axi_awaddr_w),
    .inport_awid_i       (axi_awid_w),
    .inport_awlen_i      (axi_awlen_w),
    .inport_awburst_i    (axi_awburst_w),

    // Write data
    .inport_wvalid_i     (axi_wvalid_w),
    .inport_wdata_i      (axi_wdata_w),
    .inport_wstrb_i      (axi_wstrb_w),
    .inport_wlast_i      (axi_wlast_w),

    // Write response
    .inport_bready_i     (axi_bready_w),

    // Read address
    .inport_arvalid_i    (axi_arvalid_w),
    .inport_araddr_i     (axi_araddr_w),
    .inport_arid_i       (axi_arid_w),
    .inport_arlen_i      (axi_arlen_w),
    .inport_arburst_i    (axi_arburst_w),

    // Read data
    .inport_rready_i     (axi_rready_w),

    // Clock/reset output to SoC
    .clk_out_o           (clk_sys_w),
    .rst_out_o           (rst_sys_w),

    // Write address ready
    .inport_awready_o    (axi_awready_w),

    // Write data ready
    .inport_wready_o     (axi_wready_w),

    // Write response
    .inport_bvalid_o     (axi_bvalid_w),
    .inport_bresp_o      (axi_bresp_w),
    .inport_bid_o        (axi_bid_w),

    // Read address ready
    .inport_arready_o    (axi_arready_w),

    // Read data
    .inport_rvalid_o     (axi_rvalid_w),
    .inport_rdata_o      (axi_rdata_w),
    .inport_rresp_o      (axi_rresp_w),
    .inport_rid_o        (axi_rid_w),
    .inport_rlast_o      (axi_rlast_w)
);

//-----------------------------------------------------------------
// SoC Top
//-----------------------------------------------------------------
wire dbg_txd_w;
wire uart_txd_w;
wire [3:0] counter_count_w;

fpga_top u_top (
    .clk_i         (clk_w),        // 25 MHz - peripheral/CPU clock (baud rates compiled for this)
    .rst_i         (rst_sys_w),
    .clk_sys_i     (clk_sys_w),    // driven from boolean_bram clk_out (= clk_w)
    .rst_sys_i     (rst_sys_w),

    // AXI4 to BRAM
    .axi_awready_i (axi_awready_w),
    .axi_wready_i  (axi_wready_w),
    .axi_bvalid_i  (axi_bvalid_w),
    .axi_bresp_i   (axi_bresp_w),
    .axi_bid_i     (axi_bid_w),
    .axi_arready_i (axi_arready_w),
    .axi_rvalid_i  (axi_rvalid_w),
    .axi_rdata_i   (axi_rdata_w),
    .axi_rresp_i   (axi_rresp_w),
    .axi_rid_i     (axi_rid_w),
    .axi_rlast_i   (axi_rlast_w),
    .axi_awvalid_o (axi_awvalid_w),
    .axi_awaddr_o  (axi_awaddr_w),
    .axi_awid_o    (axi_awid_w),
    .axi_awlen_o   (axi_awlen_w),
    .axi_awburst_o (axi_awburst_w),
    .axi_wvalid_o  (axi_wvalid_w),
    .axi_wdata_o   (axi_wdata_w),
    .axi_wstrb_o   (axi_wstrb_w),
    .axi_wlast_o   (axi_wlast_w),
    .axi_bready_o  (axi_bready_w),
    .axi_arvalid_o (axi_arvalid_w),
    .axi_araddr_o  (axi_araddr_w),
    .axi_arid_o    (axi_arid_w),
    .axi_arlen_o   (axi_arlen_w),
    .axi_arburst_o (axi_arburst_w),
    .axi_rready_o  (axi_rready_w),

    // SPI (not connected on Boolean - tie off)
    .spi_clk_o     (),
    .spi_mosi_o    (),
    .spi_cs_o      (),
    .spi_miso_i    (1'b0),

    // GPIO (not connected - tie off)
    .gpio_output_o        (),
    .gpio_output_enable_o (),
    .gpio_input_i         (32'b0),

    // UART
    .dbg_rxd_o     (dbg_txd_w),
    .dbg_txd_i     (uart_txd_in),
    .uart_rxd_o    (uart_txd_w),
    .uart_txd_i    (uart_txd_in),
    .counter_count_o(counter_count_w)
);

//-----------------------------------------------------------------
// OR debug and app UART together onto single TX pin
//-----------------------------------------------------------------
reg txd_q;
always @(posedge clk_w or posedge rst_sys_w)
    if (rst_sys_w) txd_q <= 1'b1;
    else           txd_q <= dbg_txd_w & uart_txd_w;

assign uart_rxd_out = txd_q;

//-----------------------------------------------------------------
// Status LEDs
// led[0] = heartbeat (tied high = on = "FPGA configured")
//-----------------------------------------------------------------
// Counter output drives LEDs - shows 4-bit count in binary
assign led = counter_count_w;

endmodule