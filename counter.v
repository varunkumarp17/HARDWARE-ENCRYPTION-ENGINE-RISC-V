//-----------------------------------------------------------------
// counter.v
// AES-128 Hardware Encryption + Decryption Engine
// Module name kept as 'counter' for SoC compatibility
// AXI4-Lite slave interface
// Base address: 0x95000000
//
// Encryption:
//   1. Write PT3..PT0   (plaintext,  0x00-0x0C)
//   2. Write KEY3..KEY0 (key,        0x10-0x1C)
//   3. Write AES_CTRL = 0x1          (0x34)
//   4. Poll  AES_STATUS bit[0] = 1   (0x30)
//   5. Read  CT3..CT0   (ciphertext, 0x20-0x2C)
//
// Decryption:
//   1. Key already written above
//   2. Write DCT3..DCT0 (ciphertext, 0x38-0x44)
//   3. Write DEC_CTRL = 0x1          (0x5C)
//   4. Poll  DEC_STATUS bit[0] = 1   (0x58)
//   5. Read  DPT3..DPT0 (plaintext,  0x48-0x54)
//-----------------------------------------------------------------

module counter
(
     input           clk_i
    ,input           rst_i

    // AXI4-Lite slave interface
    ,input  [ 31:0]  cfg_awaddr_i
    ,input           cfg_awvalid_i
    ,output          cfg_awready_o
    ,input  [ 31:0]  cfg_wdata_i
    ,input  [  3:0]  cfg_wstrb_i
    ,input           cfg_wvalid_i
    ,output          cfg_wready_o
    ,output [  1:0]  cfg_bresp_o
    ,output          cfg_bvalid_o
    ,input           cfg_bready_i
    ,input  [ 31:0]  cfg_araddr_i
    ,input           cfg_arvalid_i
    ,output          cfg_arready_o
    ,output [ 31:0]  cfg_rdata_o
    ,output [  1:0]  cfg_rresp_o
    ,output          cfg_rvalid_o
    ,input           cfg_rready_i

    // count_o kept for port compatibility with SoC top
    // tied to 0 — counter logic removed
    ,output [  3:0]  count_o
);

`include "counter_defs.v"

// count_o tied to 0 (counter removed)
assign count_o = 4'b0;

//-----------------------------------------------------------------
// AXI handshake
//-----------------------------------------------------------------
wire read_en_w  = cfg_arvalid_i & cfg_arready_o;
wire write_en_w = cfg_awvalid_i & cfg_awready_o;

assign cfg_arready_o = ~cfg_rvalid_o;
assign cfg_awready_o = ~cfg_bvalid_o && ~cfg_arvalid_i;
assign cfg_wready_o  = cfg_awready_o;

//-----------------------------------------------------------------
// Shared KEY register
//-----------------------------------------------------------------
reg [127:0] aes_key_q;

always @(posedge clk_i or posedge rst_i)
if (rst_i)
    aes_key_q <= 128'b0;
else if (write_en_w) begin
    case (cfg_awaddr_i[7:0])
        `AES_KEY3 : aes_key_q[127:96] <= cfg_wdata_i;
        `AES_KEY2 : aes_key_q[95:64]  <= cfg_wdata_i;
        `AES_KEY1 : aes_key_q[63:32]  <= cfg_wdata_i;
        `AES_KEY0 : aes_key_q[31:0]   <= cfg_wdata_i;
        default   : ;
    endcase
end

//-----------------------------------------------------------------
// ENCRYPTION registers
//-----------------------------------------------------------------
reg [127:0] aes_pt_q;
reg [127:0] aes_ct_q;
reg         aes_done_q;
reg         aes_start_q;

// Plaintext input
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    aes_pt_q <= 128'b0;
else if (write_en_w && cfg_awaddr_i[7:0] == `AES_CTRL
         && cfg_wdata_i[`AES_CTRL_RESET_B])
    aes_pt_q <= 128'b0;
else if (write_en_w) begin
    case (cfg_awaddr_i[7:0])
        `AES_PT3 : aes_pt_q[127:96] <= cfg_wdata_i;
        `AES_PT2 : aes_pt_q[95:64]  <= cfg_wdata_i;
        `AES_PT1 : aes_pt_q[63:32]  <= cfg_wdata_i;
        `AES_PT0 : aes_pt_q[31:0]   <= cfg_wdata_i;
        default  : ;
    endcase
end

// Encryption start pulse (self-clearing)
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    aes_start_q <= 1'b0;
else begin
    aes_start_q <= 1'b0;
    if (write_en_w && cfg_awaddr_i[7:0] == `AES_CTRL
        && cfg_wdata_i[`AES_CTRL_START_B])
        aes_start_q <= 1'b1;
end

// Latch ciphertext result
always @(posedge clk_i or posedge rst_i)
if (rst_i) begin
    aes_ct_q   <= 128'b0;
    aes_done_q <= 1'b0;
end
else begin
    if (write_en_w && cfg_awaddr_i[7:0] == `AES_CTRL
        && cfg_wdata_i[`AES_CTRL_RESET_B]) begin
        aes_ct_q   <= 128'b0;
        aes_done_q <= 1'b0;
    end
    else if (aes_start_q) begin
        aes_ct_q   <= aes_ct_w;
        aes_done_q <= 1'b1;
    end
end

//-----------------------------------------------------------------
// AES-128 ENCRYPT core (combinational)
//-----------------------------------------------------------------
wire [127:0] aes_ct_w;

aes128_encrypt u_aes_enc (
    .plaintext  (aes_pt_q),
    .key        (aes_key_q),
    .ciphertext (aes_ct_w)
);

//-----------------------------------------------------------------
// DECRYPTION registers
//-----------------------------------------------------------------
reg [127:0] dec_ct_q;
reg [127:0] dec_pt_q;
reg         dec_done_q;
reg         dec_start_q;

// Ciphertext input for decryption
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    dec_ct_q <= 128'b0;
else if (write_en_w && cfg_awaddr_i[7:0] == `DEC_CTRL
         && cfg_wdata_i[`DEC_CTRL_RESET_B])
    dec_ct_q <= 128'b0;
else if (write_en_w) begin
    case (cfg_awaddr_i[7:0])
        `DEC_CT3 : dec_ct_q[127:96] <= cfg_wdata_i;
        `DEC_CT2 : dec_ct_q[95:64]  <= cfg_wdata_i;
        `DEC_CT1 : dec_ct_q[63:32]  <= cfg_wdata_i;
        `DEC_CT0 : dec_ct_q[31:0]   <= cfg_wdata_i;
        default  : ;
    endcase
end

// Decryption start pulse (self-clearing)
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    dec_start_q <= 1'b0;
else begin
    dec_start_q <= 1'b0;
    if (write_en_w && cfg_awaddr_i[7:0] == `DEC_CTRL
        && cfg_wdata_i[`DEC_CTRL_START_B])
        dec_start_q <= 1'b1;
end

// Latch plaintext result
always @(posedge clk_i or posedge rst_i)
if (rst_i) begin
    dec_pt_q   <= 128'b0;
    dec_done_q <= 1'b0;
end
else begin
    if (write_en_w && cfg_awaddr_i[7:0] == `DEC_CTRL
        && cfg_wdata_i[`DEC_CTRL_RESET_B]) begin
        dec_pt_q   <= 128'b0;
        dec_done_q <= 1'b0;
    end
    else if (dec_start_q) begin
        dec_pt_q   <= dec_pt_w;
        dec_done_q <= 1'b1;
    end
end

//-----------------------------------------------------------------
// AES-128 DECRYPT core (combinational)
//-----------------------------------------------------------------
wire [127:0] dec_pt_w;

aes128_decrypt u_aes_dec (
    .ciphertext (dec_ct_q),
    .key        (aes_key_q),
    .plaintext  (dec_pt_w)
);

//-----------------------------------------------------------------
// Read mux
//-----------------------------------------------------------------
reg [31:0] data_r;
always @ *
begin
    data_r = 32'b0;
    case (cfg_araddr_i[7:0])
        `AES_CT3    : data_r = aes_ct_q[127:96];
        `AES_CT2    : data_r = aes_ct_q[95:64];
        `AES_CT1    : data_r = aes_ct_q[63:32];
        `AES_CT0    : data_r = aes_ct_q[31:0];
        `AES_STATUS : data_r = {31'b0, aes_done_q};
        `DEC_PT3    : data_r = dec_pt_q[127:96];
        `DEC_PT2    : data_r = dec_pt_q[95:64];
        `DEC_PT1    : data_r = dec_pt_q[63:32];
        `DEC_PT0    : data_r = dec_pt_q[31:0];
        `DEC_STATUS : data_r = {31'b0, dec_done_q};
        default     : data_r = 32'b0;
    endcase
end

//-----------------------------------------------------------------
// RVALID
//-----------------------------------------------------------------
reg rvalid_q;
always @(posedge clk_i or posedge rst_i)
if (rst_i)              rvalid_q <= 1'b0;
else if (read_en_w)     rvalid_q <= 1'b1;
else if (cfg_rready_i)  rvalid_q <= 1'b0;
assign cfg_rvalid_o = rvalid_q;

reg [31:0] rd_data_q;
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    rd_data_q <= 32'b0;
else if (!cfg_rvalid_o || cfg_rready_i)
    rd_data_q <= data_r;
assign cfg_rdata_o = rd_data_q;
assign cfg_rresp_o = 2'b00;

//-----------------------------------------------------------------
// BVALID
//-----------------------------------------------------------------
reg bvalid_q;
always @(posedge clk_i or posedge rst_i)
if (rst_i)              bvalid_q <= 1'b0;
else if (write_en_w)    bvalid_q <= 1'b1;
else if (cfg_bready_i)  bvalid_q <= 1'b0;
assign cfg_bvalid_o = bvalid_q;
assign cfg_bresp_o  = 2'b00;

endmodule
