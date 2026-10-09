// ============================================================================
// cmac_controller.v
//
// Dedicated hardware AES-CMAC controller (NIST SP 800-38B).
// Implements single-block (128-bit message) CMAC generation and verification
// by sequencing operations through the existing AES-128 hardware core.
//
// Sequence:
//   1. Expand Key K (if needed / on start)
//   2. Compute L = AES_K(128'b0)
//   3. Derive K1:
//        If MSB(L) == 0: K1 = L << 1
//        If MSB(L) == 1: K1 = (L << 1) ^ 128'h87
//   4. Compute Tag = AES_K(Message ^ K1)
//   5. If generate: output Tag, set cmac_done = 1
//      If verify: compare Tag == expected_tag
//        If match: cmac_valid = 1, tamper_detected = 0
//        If mismatch: cmac_valid = 0, tamper_detected = 1
// ============================================================================

`timescale 1ns / 1ps

module cmac_controller (
    input  wire         clk,
    input  wire         resetn,

    // Control triggers
    input  wire         start_gen,
    input  wire         start_verify,

    // Inputs
    input  wire [127:0] key_in,
    input  wire [127:0] msg_in,
    input  wire [127:0] expected_tag_in,

    // Interface to aes128_wrapper / AES core
    output reg          aes_reset_key,
    output reg          aes_load_data,
    output reg  [127:0] aes_plain_text,
    output reg  [127:0] aes_cipher_key,
    output reg          aes_enc_dec,
    input  wire [127:0] aes_cipher_text,
    input  wire         aes_key_ready,
    input  wire         aes_cipher_ready,

    // Status and outputs
    output reg  [127:0] tag_out,
    output reg          cmac_busy,
    output reg          cmac_done,
    output reg          cmac_valid,
    output reg          tamper_detected
);

    // Constant R_128 for AES-128 CMAC (NIST SP 800-38B)
    localparam [127:0] R_128 = 128'h00000000000000000000000000000087;

    // FSM State Encoding
    localparam [3:0]
        ST_IDLE           = 4'd0,
        ST_INIT_KEY       = 4'd1,
        ST_WAIT_KEY_BUSY  = 4'd2,
        ST_WAIT_KEY_READY = 4'd3,
        ST_START_L        = 4'd4,
        ST_WAIT_L_BUSY    = 4'd5,
        ST_WAIT_L         = 4'd6,
        ST_CALC_K1        = 4'd7,
        ST_START_TAG      = 4'd8,
        ST_WAIT_TAG_BUSY  = 4'd9,
        ST_WAIT_TAG       = 4'd10,
        ST_FINISH         = 4'd11,
        ST_DONE           = 4'd12;

    reg [3:0]   state;
    reg         is_verify_reg;
    reg [127:0] key_reg;
    reg [127:0] msg_reg;
    reg [127:0] exp_tag_reg;
    reg [127:0] k1_reg;

    always @(posedge clk) begin
        if (!resetn) begin
            state           <= ST_IDLE;
            aes_reset_key   <= 1'b0;
            aes_load_data   <= 1'b0;
            aes_plain_text  <= 128'h0;
            aes_cipher_key  <= 128'h0;
            aes_enc_dec     <= 1'b1;
            tag_out         <= 128'h0;
            cmac_busy       <= 1'b0;
            cmac_done       <= 1'b0;
            cmac_valid      <= 1'b0;
            tamper_detected <= 1'b0;
            is_verify_reg   <= 1'b0;
            key_reg         <= 128'h0;
            msg_reg         <= 128'h0;
            exp_tag_reg     <= 128'h0;
            k1_reg          <= 128'h0;
        end else begin
            // Default 1-cycle pulses
            aes_reset_key <= 1'b0;
            aes_load_data <= 1'b0;

            case (state)
                ST_IDLE: begin
                    cmac_busy <= 1'b0;
                    if (start_gen || start_verify) begin
                        cmac_busy       <= 1'b1;
                        cmac_done       <= 1'b0;
                        cmac_valid      <= 1'b0;
                        tamper_detected <= 1'b0;
                        is_verify_reg   <= start_verify;
                        key_reg         <= key_in;
                        msg_reg         <= msg_in;
                        exp_tag_reg     <= expected_tag_in;
                        state           <= ST_INIT_KEY;
                    end
                end

                // Step 1: Initialize Key in AES engine
                ST_INIT_KEY: begin
                    aes_cipher_key <= key_reg;
                    aes_reset_key  <= 1'b1;
                    state          <= ST_WAIT_KEY_BUSY;
                end

                ST_WAIT_KEY_BUSY: begin
                    aes_reset_key  <= 1'b0;
                    state          <= ST_WAIT_KEY_READY;
                end

                ST_WAIT_KEY_READY: begin
                    if (aes_key_ready) begin
                        state <= ST_START_L;
                    end
                end

                // Step 2: Compute L = AES_K(0^128)
                ST_START_L: begin
                    aes_plain_text <= 128'h0;
                    aes_enc_dec    <= 1'b1;
                    aes_load_data  <= 1'b1;
                    state          <= ST_WAIT_L_BUSY;
                end

                ST_WAIT_L_BUSY: begin
                    aes_load_data <= 1'b0;
                    state         <= ST_WAIT_L;
                end

                ST_WAIT_L: begin
                    if (aes_cipher_ready) begin
                        state <= ST_CALC_K1;
                    end
                end

                // Step 3: Derive K1 from L (NIST SP 800-38B Section 5.3)
                ST_CALC_K1: begin
                    // L is in aes_cipher_text
                    if (aes_cipher_text[127] == 1'b0)
                        k1_reg <= {aes_cipher_text[126:0], 1'b0};
                    else
                        k1_reg <= {aes_cipher_text[126:0], 1'b0} ^ R_128;

                    state <= ST_START_TAG;
                end

                // Step 4: Compute Tag = AES_K(Message ^ K1)
                ST_START_TAG: begin
                    aes_plain_text <= msg_reg ^ k1_reg;
                    aes_enc_dec    <= 1'b1;
                    aes_load_data  <= 1'b1;
                    state          <= ST_WAIT_TAG_BUSY;
                end

                ST_WAIT_TAG_BUSY: begin
                    aes_load_data <= 1'b0;
                    state         <= ST_WAIT_TAG;
                end

                ST_WAIT_TAG: begin
                    if (aes_cipher_ready) begin
                        tag_out <= aes_cipher_text;
                        state   <= ST_FINISH;
                    end
                end

                // Step 5: Finalize results & verification
                ST_FINISH: begin
                    cmac_busy <= 1'b0;
                    cmac_done <= 1'b1;

                    if (is_verify_reg) begin
                        if (tag_out == exp_tag_reg) begin
                            cmac_valid      <= 1'b1;
                            tamper_detected <= 1'b0;
                        end else begin
                            cmac_valid      <= 1'b0;
                            tamper_detected <= 1'b1;
                        end
                    end else begin
                        cmac_valid      <= 1'b1;
                        tamper_detected <= 1'b0;
                    end

                    state <= ST_DONE;
                end

                ST_DONE: begin
                    cmac_busy <= 1'b0;
                    if (start_gen || start_verify) begin
                        // Acknowledge new request immediately
                        cmac_busy       <= 1'b1;
                        cmac_done       <= 1'b0;
                        cmac_valid      <= 1'b0;
                        tamper_detected <= 1'b0;
                        is_verify_reg   <= start_verify;
                        key_reg         <= key_in;
                        msg_reg         <= msg_in;
                        exp_tag_reg     <= expected_tag_in;
                        state           <= ST_INIT_KEY;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
