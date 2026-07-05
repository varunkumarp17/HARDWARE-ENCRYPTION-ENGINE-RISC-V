//-----------------------------------------------------------------
// counter_defs.v
// Register map for AES-128 Hardware Encryption Engine
// Base address: 0x95000000
//-----------------------------------------------------------------

// PLAINTEXT input registers (write-only)
`define AES_PT3           8'h00   // plaintext[127:96]
`define AES_PT2           8'h04   // plaintext[95:64]
`define AES_PT1           8'h08   // plaintext[63:32]
`define AES_PT0           8'h0C   // plaintext[31:0]

// KEY registers (write-only, shared by encrypt and decrypt)
`define AES_KEY3          8'h10   // key[127:96]
`define AES_KEY2          8'h14   // key[95:64]
`define AES_KEY1          8'h18   // key[63:32]
`define AES_KEY0          8'h1C   // key[31:0]

// CIPHERTEXT output registers (read-only)
`define AES_CT3           8'h20   // ciphertext[127:96]
`define AES_CT2           8'h24   // ciphertext[95:64]
`define AES_CT1           8'h28   // ciphertext[63:32]
`define AES_CT0           8'h2C   // ciphertext[31:0]

// ENCRYPTION STATUS register (read-only)
`define AES_STATUS        8'h30
    `define AES_STATUS_DONE_B    0   // bit 0: 1 = ciphertext valid

// ENCRYPTION CTRL register (write-only)
`define AES_CTRL          8'h34
    `define AES_CTRL_START_B     0   // bit 0: write 1 to start (self-clearing)
    `define AES_CTRL_RESET_B     1   // bit 1: write 1 to clear all registers

// CIPHERTEXT input registers for decryption (write-only)
`define DEC_CT3           8'h38   // dec_ciphertext[127:96]
`define DEC_CT2           8'h3C   // dec_ciphertext[95:64]
`define DEC_CT1           8'h40   // dec_ciphertext[63:32]
`define DEC_CT0           8'h44   // dec_ciphertext[31:0]

// PLAINTEXT output registers from decryption (read-only)
`define DEC_PT3           8'h48   // dec_plaintext[127:96]
`define DEC_PT2           8'h4C   // dec_plaintext[95:64]
`define DEC_PT1           8'h50   // dec_plaintext[63:32]
`define DEC_PT0           8'h54   // dec_plaintext[31:0]

// DECRYPTION STATUS register (read-only)
`define DEC_STATUS        8'h58
    `define DEC_STATUS_DONE_B    0   // bit 0: 1 = plaintext valid

// DECRYPTION CTRL register (write-only)
`define DEC_CTRL          8'h5C
    `define DEC_CTRL_START_B     0   // bit 0: write 1 to start (self-clearing)
    `define DEC_CTRL_RESET_B     1   // bit 1: write 1 to clear decrypt registers
