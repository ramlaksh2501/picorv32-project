// ============================================================================
// aes128_wrapper.v
//
// Lightweight wrapper around yeshvanth-m/AES-128 core (aes128).
// Preserves the original AES-128 core RTL completely unmodified while providing:
// 1. Standard 128-bit linear byte ordering (FIPS 197 / NIST SP 800-38A)
//    mapping to/from the core's internal 4x4 row-organized layout.
// 2. Direct pass-through of control signals (clk, reset_key, load_data, enc_dec,
//    key_ready, cipher_ready).
// ============================================================================

`timescale 1ns / 1ps

module aes128_wrapper (
    input  wire         clk_i,
    input  wire         reset_key_i,
    input  wire         load_data_i,
    input  wire [127:0] plain_text_i,
    input  wire [127:0] cipher_key_i,
    input  wire         enc_or_dec_i,
    output wire [127:0] cipher_text_o,
    output wire         key_ready_o,
    output wire         cipher_ready_o
);

    // ------------------------------------------------------------------------
    // Byte layout translation between standard FIPS 197 linear order
    // [Byte 0 .. Byte 15] and the core's internal row-major state matrix:
    // Row 0: Bytes 0, 4,  8, 12
    // Row 1: Bytes 1, 5,  9, 13
    // Row 2: Bytes 2, 6, 10, 14
    // Row 3: Bytes 3, 7, 11, 15
    // ------------------------------------------------------------------------
    wire [127:0] core_key_i;
    wire [127:0] core_pt_i;
    wire [127:0] core_ct_o;

    assign core_key_i = {
        cipher_key_i[127:120], cipher_key_i[95:88], cipher_key_i[63:56], cipher_key_i[31:24],
        cipher_key_i[119:112], cipher_key_i[87:80], cipher_key_i[55:48], cipher_key_i[23:16],
        cipher_key_i[111:104], cipher_key_i[79:72], cipher_key_i[47:40], cipher_key_i[15:8],
        cipher_key_i[103:96],  cipher_key_i[71:64], cipher_key_i[39:32], cipher_key_i[7:0]
    };

    assign core_pt_i = {
        plain_text_i[127:120], plain_text_i[95:88], plain_text_i[63:56], plain_text_i[31:24],
        plain_text_i[119:112], plain_text_i[87:80], plain_text_i[55:48], plain_text_i[23:16],
        plain_text_i[111:104], plain_text_i[79:72], plain_text_i[47:40], plain_text_i[15:8],
        plain_text_i[103:96],  plain_text_i[71:64], plain_text_i[39:32], plain_text_i[7:0]
    };

    assign cipher_text_o = {
        core_ct_o[127:120], core_ct_o[95:88], core_ct_o[63:56], core_ct_o[31:24],
        core_ct_o[119:112], core_ct_o[87:80], core_ct_o[55:48], core_ct_o[23:16],
        core_ct_o[111:104], core_ct_o[79:72], core_ct_o[47:40], core_ct_o[15:8],
        core_ct_o[103:96],  core_ct_o[71:64], core_ct_o[39:32], core_ct_o[7:0]
    };

    // ------------------------------------------------------------------------
    // Instantiate unmodified original AES-128 core
    // ------------------------------------------------------------------------
    aes128 u_aes128 (
        .clk_i          (clk_i),
        .reset_key_i    (reset_key_i),
        .load_data_i    (load_data_i),
        .plain_text_i   (core_pt_i),
        .cipher_key_i   (core_key_i),
        .enc_or_dec_i   (enc_or_dec_i),
        .cipher_text_o  (core_ct_o),
        .key_ready_o    (key_ready_o),
        .cipher_ready_o (cipher_ready_o)
    );

endmodule
