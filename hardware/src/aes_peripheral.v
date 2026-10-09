// ============================================================================
// aes_peripheral.v
//
// Memory-mapped Security Peripheral for PicoRV32 SoC.
// Integrates:
//   1. Direct AES-128 Encryption / Decryption engine (Phase 2 preserved)
//   2. Hardware AES-CMAC Generator and Verifier (NIST SP 800-38B)
// Reuses the single underlying aes128_wrapper hardware core for all operations.
//
// Register Map (Base: 0x4000_0000):
//   0x4000_0000 : CONTROL (W)
//                   bit 0: START_ENCRYPT (1-cycle pulse)
//                   bit 1: START_DECRYPT (1-cycle pulse)
//                   bit 2: INIT_KEY      (1-cycle pulse)
//                   bit 3: CMAC_GENERATE (1-cycle pulse)
//                   bit 4: CMAC_VERIFY   (1-cycle pulse)
//   0x4000_0004 : STATUS  (R)
//                   bit 0: key_ready
//                   bit 1: cipher_ready
//                   bit 2: busy (AES or CMAC busy)
//                   bit 3: cmac_done
//                   bit 4: cmac_valid
//                   bit 5: tamper_detected
//   0x4000_0010 : DATA0   (R/W)  plain_text / message[127:96]
//   0x4000_0014 : DATA1   (R/W)  plain_text / message[95:64]
//   0x4000_0018 : DATA2   (R/W)  plain_text / message[63:32]
//   0x4000_001C : DATA3   (R/W)  plain_text / message[31:0]
//   0x4000_0020 : KEY0    (R/W)  cipher_key[127:96]
//   0x4000_0024 : KEY1    (R/W)  cipher_key[95:64]
//   0x4000_0028 : KEY2    (R/W)  cipher_key[63:32]
//   0x4000_002C : KEY3    (R/W)  cipher_key[31:0]
//   0x4000_0030 : RESULT0 (R)    direct AES cipher_text[127:96]
//   0x4000_0034 : RESULT1 (R)    direct AES cipher_text[95:64]
//   0x4000_0038 : RESULT2 (R)    direct AES cipher_text[63:32]
//   0x4000_003C : RESULT3 (R)    direct AES cipher_text[31:0]
//   0x4000_0040 : CMAC_TAG0 (R)  calculated CMAC tag[127:96]
//   0x4000_0044 : CMAC_TAG1 (R)  calculated CMAC tag[95:64]
//   0x4000_0048 : CMAC_TAG2 (R)  calculated CMAC tag[63:32]
//   0x4000_004C : CMAC_TAG3 (R)  calculated CMAC tag[31:0]
//   0x4000_0050 : CMAC_EXP0 (R/W) expected/received tag[127:96] for verification
//   0x4000_0054 : CMAC_EXP1 (R/W) expected/received tag[95:64]
//   0x4000_0058 : CMAC_EXP2 (R/W) expected/received tag[63:32]
//   0x4000_005C : CMAC_EXP3 (R/W) expected/received tag[31:0]
// ============================================================================

`timescale 1ns / 1ps

module aes_peripheral (
    input  wire        clk,
    input  wire        resetn,
    input  wire        sel,
    input  wire        mem_valid,
    input  wire        mem_ready,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata
);

    // ------------------------------------------------------------------------
    // Registers for 128-bit Key, Data/Message, and Expected Tag
    // ------------------------------------------------------------------------
    reg [31:0] data0_reg;
    reg [31:0] data1_reg;
    reg [31:0] data2_reg;
    reg [31:0] data3_reg;

    reg [31:0] key0_reg;
    reg [31:0] key1_reg;
    reg [31:0] key2_reg;
    reg [31:0] key3_reg;

    reg [31:0] exp_tag0_reg;
    reg [31:0] exp_tag1_reg;
    reg [31:0] exp_tag2_reg;
    reg [31:0] exp_tag3_reg;

    // Direct AES control and status registers
    reg        reset_key_pulse;
    reg        load_data_pulse;
    reg        enc_dec_reg;
    reg        key_busy;
    reg        cipher_busy;

    // CMAC control triggers
    reg        cmac_start_gen_pulse;
    reg        cmac_start_verify_pulse;

    // AES Core wires
    wire [127:0] cipher_text;
    wire         key_ready;
    wire         cipher_ready;
    wire         direct_busy = key_busy || cipher_busy;

    // CMAC Controller wires
    wire [127:0] cmac_tag_out;
    wire         cmac_busy;
    wire         cmac_done;
    wire         cmac_valid;
    wire         cmac_tamper_detected;

    wire         cmac_aes_reset_key;
    wire         cmac_aes_load_data;
    wire [127:0] cmac_aes_plain_text;
    wire [127:0] cmac_aes_cipher_key;
    wire         cmac_aes_enc_dec;

    wire is_busy = direct_busy || cmac_busy;
    wire wr_en   = sel && mem_valid && !mem_ready && (|wstrb);

    // ------------------------------------------------------------------------
    // Bus Write Logic
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            data0_reg               <= 32'h0;
            data1_reg               <= 32'h0;
            data2_reg               <= 32'h0;
            data3_reg               <= 32'h0;
            key0_reg                <= 32'h0;
            key1_reg                <= 32'h0;
            key2_reg                <= 32'h0;
            key3_reg                <= 32'h0;
            exp_tag0_reg            <= 32'h0;
            exp_tag1_reg            <= 32'h0;
            exp_tag2_reg            <= 32'h0;
            exp_tag3_reg            <= 32'h0;
            reset_key_pulse         <= 1'b0;
            load_data_pulse         <= 1'b0;
            enc_dec_reg             <= 1'b1;
            key_busy                <= 1'b0;
            cipher_busy             <= 1'b0;
            cmac_start_gen_pulse    <= 1'b0;
            cmac_start_verify_pulse <= 1'b0;
        end else begin
            // Single-cycle self-clearing command pulses
            reset_key_pulse         <= 1'b0;
            load_data_pulse         <= 1'b0;
            cmac_start_gen_pulse    <= 1'b0;
            cmac_start_verify_pulse <= 1'b0;

            // Track direct AES busy status
            if (key_ready)
                key_busy <= 1'b0;
            if (cipher_ready)
                cipher_busy <= 1'b0;

            if (wr_en) begin
                case (addr[7:0])
                    8'h00: begin
                        // Mutual exclusion: ignore new starts if already running
                        if (!is_busy) begin
                            if (wdata[4]) begin
                                cmac_start_verify_pulse <= 1'b1;
                            end else if (wdata[3]) begin
                                cmac_start_gen_pulse    <= 1'b1;
                            end else if (wdata[2]) begin
                                reset_key_pulse         <= 1'b1;
                                key_busy                <= 1'b1;
                            end else if (wdata[0]) begin
                                enc_dec_reg             <= 1'b1; // Encrypt
                                load_data_pulse         <= 1'b1;
                                cipher_busy             <= 1'b1;
                            end else if (wdata[1]) begin
                                enc_dec_reg             <= 1'b0; // Decrypt
                                load_data_pulse         <= 1'b1;
                                cipher_busy             <= 1'b1;
                            end
                        end
                    end

                    8'h10: begin
                        if (wstrb[0]) data0_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) data0_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) data0_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) data0_reg[31:24] <= wdata[31:24];
                    end
                    8'h14: begin
                        if (wstrb[0]) data1_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) data1_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) data1_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) data1_reg[31:24] <= wdata[31:24];
                    end
                    8'h18: begin
                        if (wstrb[0]) data2_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) data2_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) data2_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) data2_reg[31:24] <= wdata[31:24];
                    end
                    8'h1C: begin
                        if (wstrb[0]) data3_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) data3_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) data3_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) data3_reg[31:24] <= wdata[31:24];
                    end

                    8'h20: begin
                        if (wstrb[0]) key0_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) key0_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) key0_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) key0_reg[31:24] <= wdata[31:24];
                    end
                    8'h24: begin
                        if (wstrb[0]) key1_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) key1_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) key1_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) key1_reg[31:24] <= wdata[31:24];
                    end
                    8'h28: begin
                        if (wstrb[0]) key2_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) key2_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) key2_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) key2_reg[31:24] <= wdata[31:24];
                    end
                    8'h2C: begin
                        if (wstrb[0]) key3_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) key3_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) key3_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) key3_reg[31:24] <= wdata[31:24];
                    end

                    8'h50: begin
                        if (wstrb[0]) exp_tag0_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) exp_tag0_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) exp_tag0_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) exp_tag0_reg[31:24] <= wdata[31:24];
                    end
                    8'h54: begin
                        if (wstrb[0]) exp_tag1_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) exp_tag1_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) exp_tag1_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) exp_tag1_reg[31:24] <= wdata[31:24];
                    end
                    8'h58: begin
                        if (wstrb[0]) exp_tag2_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) exp_tag2_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) exp_tag2_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) exp_tag2_reg[31:24] <= wdata[31:24];
                    end
                    8'h5C: begin
                        if (wstrb[0]) exp_tag3_reg[7:0]   <= wdata[7:0];
                        if (wstrb[1]) exp_tag3_reg[15:8]  <= wdata[15:8];
                        if (wstrb[2]) exp_tag3_reg[23:16] <= wdata[23:16];
                        if (wstrb[3]) exp_tag3_reg[31:24] <= wdata[31:24];
                    end
                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Bus Read Multiplexer
    // ------------------------------------------------------------------------
    always @(*) begin
        case (addr[7:0])
            8'h00:   rdata = {27'b0, cmac_start_verify_pulse, cmac_start_gen_pulse, reset_key_pulse, 1'b0, enc_dec_reg};
            8'h04:   rdata = {26'b0, cmac_tamper_detected, cmac_valid, cmac_done, is_busy, cipher_ready, key_ready};
            8'h10:   rdata = data0_reg;
            8'h14:   rdata = data1_reg;
            8'h18:   rdata = data2_reg;
            8'h1C:   rdata = data3_reg;
            8'h20:   rdata = key0_reg;
            8'h24:   rdata = key1_reg;
            8'h28:   rdata = key2_reg;
            8'h2C:   rdata = key3_reg;
            8'h30:   rdata = cipher_text[127:96];
            8'h34:   rdata = cipher_text[95:64];
            8'h38:   rdata = cipher_text[63:32];
            8'h3C:   rdata = cipher_text[31:0];
            8'h40:   rdata = cmac_tag_out[127:96];
            8'h44:   rdata = cmac_tag_out[95:64];
            8'h48:   rdata = cmac_tag_out[63:32];
            8'h4C:   rdata = cmac_tag_out[31:0];
            8'h50:   rdata = exp_tag0_reg;
            8'h54:   rdata = exp_tag1_reg;
            8'h58:   rdata = exp_tag2_reg;
            8'h5C:   rdata = exp_tag3_reg;
            default: rdata = 32'h0000_0000;
        endcase
    end

    // ------------------------------------------------------------------------
    // Concatenated signals for 128-bit interfaces
    // ------------------------------------------------------------------------
    wire [127:0] plain_text_comb = {data0_reg,    data1_reg,    data2_reg,    data3_reg};
    wire [127:0] cipher_key_comb = {key0_reg,     key1_reg,     key2_reg,     key3_reg};
    wire [127:0] exp_tag_comb    = {exp_tag0_reg, exp_tag1_reg, exp_tag2_reg, exp_tag3_reg};

    // ------------------------------------------------------------------------
    // Hardware AES Multiplexer: Arbitrates between Direct AES & CMAC
    // ------------------------------------------------------------------------
    wire         aes_reset_key_mux  = cmac_busy ? cmac_aes_reset_key  : reset_key_pulse;
    wire         aes_load_data_mux  = cmac_busy ? cmac_aes_load_data  : load_data_pulse;
    wire [127:0] aes_plain_text_mux = cmac_busy ? cmac_aes_plain_text : plain_text_comb;
    wire [127:0] aes_cipher_key_mux = cmac_busy ? cmac_aes_cipher_key : cipher_key_comb;
    wire         aes_enc_dec_mux    = cmac_busy ? cmac_aes_enc_dec     : enc_dec_reg;

    // ------------------------------------------------------------------------
    // Instantiate CMAC Controller
    // ------------------------------------------------------------------------
    cmac_controller u_cmac_ctrl (
        .clk             (clk),
        .resetn          (resetn),
        .start_gen       (cmac_start_gen_pulse),
        .start_verify    (cmac_start_verify_pulse),
        .key_in          (cipher_key_comb),
        .msg_in          (plain_text_comb),
        .expected_tag_in (exp_tag_comb),
        .aes_reset_key   (cmac_aes_reset_key),
        .aes_load_data   (cmac_aes_load_data),
        .aes_plain_text  (cmac_aes_plain_text),
        .aes_cipher_key  (cmac_aes_cipher_key),
        .aes_enc_dec     (cmac_aes_enc_dec),
        .aes_cipher_text (cipher_text),
        .aes_key_ready   (key_ready),
        .aes_cipher_ready(cipher_ready),
        .tag_out         (cmac_tag_out),
        .cmac_busy       (cmac_busy),
        .cmac_done       (cmac_done),
        .cmac_valid      (cmac_valid),
        .tamper_detected (cmac_tamper_detected)
    );

    // ------------------------------------------------------------------------
    // Instantiate Shared Single Hardware AES-128 Wrapper Core
    // ------------------------------------------------------------------------
    aes128_wrapper u_aes128_core (
        .clk_i          (clk),
        .reset_key_i    (aes_reset_key_mux),
        .load_data_i    (aes_load_data_mux),
        .plain_text_i   (aes_plain_text_mux),
        .cipher_key_i   (aes_cipher_key_mux),
        .enc_or_dec_i   (aes_enc_dec_mux),
        .cipher_text_o  (cipher_text),
        .key_ready_o    (key_ready),
        .cipher_ready_o (cipher_ready)
    );

endmodule
