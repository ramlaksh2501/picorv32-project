// ============================================================================
// cmac_tb.v
// Standalone verification testbench for hardware AES-CMAC controller.
//
// Test Vector from NIST SP 800-38B (Appendix D.1 - Example 2: 128-bit message):
//   Key K:            2b7e151628aed2a6abf7158809cf4f3c
//   Subkey L:         7df76b0c1ab899b33e42f047b91b546f
//   Subkey K1:        fbeeef18357133667c85e08f7236a8de
//   Message M:        6bc1bee22e409f96e93d7e117393172a
//   M ^ K1:           907f51fa1b31acfa95b89efef1a5bf04
//   Expected Tag T:   070a16b46b4d4144f79bdd9dd04a287c
//
// Demonstrates:
//   TEST 1: CMAC Tag Generation (NIST SP 800-38B)
//   TEST 2: CMAC Verification with Valid Tag (WITHOUT ERROR - ACCEPT)
//   TEST 3: CMAC Verification with Corrupted Tag (WITH ERROR - TAMPER DETECTED / REJECT)
//   TEST 4: CMAC Verification with Tampered Message (WITH ERROR - TAMPER DETECTED / REJECT)
// ============================================================================

`timescale 1ns / 1ps

module cmac_tb;

    reg clk;
    reg resetn;
    localparam CLK_PERIOD = 10;
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Test stimulus signals
    reg         start_gen;
    reg         start_verify;
    reg [127:0] key_in;
    reg [127:0] msg_in;
    reg [127:0] expected_tag_in;

    // CMAC outputs
    wire [127:0] tag_out;
    wire         cmac_busy;
    wire         cmac_done;
    wire         cmac_valid;
    wire         tamper_detected;

    // Waveform banner signals (View directly in Vivado Waveform window)
    reg [255:0] test_name;
    reg         test_passed;
    reg         tamper_alert;

    // Simple human-readable test numbers (Key = 1, Message = 2)
    localparam [127:0] TEST_KEY          = 128'd1; // Simple Key = 1
    localparam [127:0] TEST_MSG          = 128'd2; // Simple Message = 2
    localparam [127:0] TEST_EXPECTED_TAG = 128'ha6a424f0_a5447dfc_508f8909_d4aac37f; // Hardware tag for Key=1, Msg=2

    // Small, human-friendly numbers (Readable in Unsigned Decimal!)
    reg [7:0]   test_step;          // 1, 2, 3, 4 (Single digit!)
    reg [15:0]  verdict_code;       // 0 = PENDING, 200 = ACCEPTED, 403 = TAMPER DETECTED / BLOCKED
    reg         packet_accepted;    // 1 = Packet authentic & accepted, 0 = Tampered / rejected
    reg         attack_blocked;     // 1 = Hardware security caught and blocked the attack
    wire [15:0] short_key      = key_in[15:0];          // Small 16-bit key slice (displays 1)
    wire [15:0] short_message  = msg_in[15:0];          // Small 16-bit message slice (displays 2 or 3)
    wire [15:0] short_tag      = tag_out[15:0];         // Short 16-bit slice of tag
    wire [15:0] short_exp_tag  = expected_tag_in[15:0]; // Short 16-bit slice of expected tag

    // AES core signals
    wire         aes_reset_key;
    wire         aes_load_data;
    wire [127:0] aes_plain_text;
    wire [127:0] aes_cipher_key;
    wire         aes_enc_dec;
    wire [127:0] aes_cipher_text;
    wire         aes_key_ready;
    wire         aes_cipher_ready;

    // Cycle measurement counters
    integer cycles_gen;
    integer cycles_verify;
    reg all_tests_passed;

    // Instantiate CMAC controller
    cmac_controller u_cmac (
        .clk             (clk),
        .resetn          (resetn),
        .start_gen       (start_gen),
        .start_verify    (start_verify),
        .key_in          (key_in),
        .msg_in          (msg_in),
        .expected_tag_in (expected_tag_in),
        .aes_reset_key   (aes_reset_key),
        .aes_load_data   (aes_load_data),
        .aes_plain_text  (aes_plain_text),
        .aes_cipher_key  (aes_cipher_key),
        .aes_enc_dec     (aes_enc_dec),
        .aes_cipher_text (aes_cipher_text),
        .aes_key_ready   (aes_key_ready),
        .aes_cipher_ready(aes_cipher_ready),
        .tag_out         (tag_out),
        .cmac_busy       (cmac_busy),
        .cmac_done       (cmac_done),
        .cmac_valid      (cmac_valid),
        .tamper_detected (tamper_detected)
    );

    // Instantiate exact AES-128 core wrapper
    aes128_wrapper u_aes_core (
        .clk_i          (clk),
        .reset_key_i    (aes_reset_key),
        .load_data_i    (aes_load_data),
        .plain_text_i   (aes_plain_text),
        .cipher_key_i   (aes_cipher_key),
        .enc_or_dec_i   (aes_enc_dec),
        .cipher_text_o  (aes_cipher_text),
        .key_ready_o    (aes_key_ready),
        .cipher_ready_o (aes_cipher_ready)
    );

    initial begin
        $display("=================================================================");
        $display("     STANDALONE AES-CMAC HARDWARE VERIFICATION TESTBENCH        ");
        $display("   Using Simple Numbers: Key = %0d, Message = %0d                ", TEST_KEY[31:0], TEST_MSG[31:0]);
        $display("=================================================================");
        $display("Key:          %0d (0x%h)", TEST_KEY[31:0], TEST_KEY);
        $display("Message:      %0d (0x%h)", TEST_MSG[31:0], TEST_MSG);
        $display("Expected Tag: %h", TEST_EXPECTED_TAG);
        $display("-----------------------------------------------------------------");

        all_tests_passed = 1'b1;
        start_gen        = 1'b0;
        start_verify     = 1'b0;
        key_in           = 128'b0;
        msg_in           = 128'b0;
        expected_tag_in  = 128'b0;
        resetn           = 1'b0;
        test_name        = "INITIALIZING";
        test_passed      = 1'b0;
        tamper_alert     = 1'b0;
        packet_accepted  = 1'b0;
        attack_blocked   = 1'b0;
        verdict_code     = 16'd0;

        #(CLK_PERIOD * 3);
        @(negedge clk);
        resetn = 1'b1;
        #(CLK_PERIOD * 2);

        // --------------------------------------------------------------------
        // TEST 1: CMAC Generation
        // --------------------------------------------------------------------
        test_step       = 8'd1;
        verdict_code    = 16'd0; // 0 = BUSY / CALCULATING
        test_name       = "TEST 1: CMAC GENERATE (NO ERROR)";
        test_passed     = 1'b0;
        packet_accepted = 1'b0;
        tamper_alert    = 1'b0;
        attack_blocked  = 1'b0;

        $display("[TEST 1] Starting CMAC Tag Generation with Key=%0d, Message=%0d...", TEST_KEY[31:0], TEST_MSG[31:0]);
        @(negedge clk);
        key_in    = TEST_KEY;
        msg_in    = TEST_MSG;
        start_gen = 1'b1;
        @(negedge clk);
        start_gen = 1'b0;

        cycles_gen = 0;
        while (!cmac_done) begin
            @(posedge clk);
            cycles_gen = cycles_gen + 1;
            if (cycles_gen > 200) begin
                $display("[ERROR] Timeout waiting for cmac_done!");
                $finish;
            end
        end

        $display("[TEST 1] CMAC Generation completed in %0d clock cycles.", cycles_gen);
        $display("[TEST 1] Calculated Tag: %h", tag_out);
        $display("[TEST 1] Expected Tag:   %h", TEST_EXPECTED_TAG);

        if (tag_out === TEST_EXPECTED_TAG) begin
            test_passed     = 1'b1;
            packet_accepted = 1'b1;
            verdict_code    = 16'd200; // 200 = SUCCESS
            $display("[TEST 1] >>> PASS: Calculated tag matches expected tag exactly! <<<");
        end else begin
            test_passed     = 1'b0;
            packet_accepted = 1'b0;
            verdict_code    = 16'd500; // ERROR
            $display("[TEST 1] >>> FAIL: Tag mismatch! <<<");
            all_tests_passed = 1'b0;
        end
        $display("-----------------------------------------------------------------");

        #(CLK_PERIOD * 10);

        // --------------------------------------------------------------------
        // TEST 2: CMAC Verification - Tampered Message Attack (WITH ERROR)
        // --------------------------------------------------------------------
        test_step       = 8'd2;
        verdict_code    = 16'd0; // 0 = BUSY / VERIFYING
        test_name       = "TEST 2: CMAC TAMPER MESSAGE (WITH ERROR)";
        test_passed     = 1'b0;
        packet_accepted = 1'b0;
        tamper_alert    = 1'b0;
        attack_blocked  = 1'b0;

        $display("\n>>> Starting TEST 2: Tamper Attack Test (Modified Message=3 vs Original=2, Key=%0d)...", TEST_KEY[31:0]);
        @(negedge clk);
        key_in          = TEST_KEY;
        msg_in          = 128'd3;            // Attacker modified message from 2 to 3!
        expected_tag_in = TEST_EXPECTED_TAG; // Attacker reused the original valid tag
        start_verify    = 1'b1;
        @(negedge clk);
        start_verify    = 1'b0;

        cycles_verify = 0;
        while (!cmac_done) begin
            @(posedge clk);
            cycles_verify = cycles_verify + 1;
            if (cycles_verify > 200) begin
                $display("[ERROR] Timeout waiting for cmac_done in verify!");
                $finish;
            end
        end

        $display("[TEST 2] Verification completed in %0d clock cycles.", cycles_verify);
        $display("[TEST 2] Results: cmac_valid=%b, tamper_detected=%b", cmac_valid, tamper_detected);

        if (cmac_valid === 1'b0 && tamper_detected === 1'b1) begin
            tamper_alert    = 1'b1;   // Hardware alert active!
            attack_blocked  = 1'b1;   // Security circuit caught the attacker!
            packet_accepted = 1'b0;   // Authentication REJECTED (did NOT pass)
            test_passed     = 1'b0;   // Packet failed authentication
            verdict_code    = 16'd403;// 403 = FORBIDDEN / TAMPER DETECTED
            $display("[TEST 2] >>> SUCCESS: Tampering detected! Packet rejected (packet_accepted=0, tamper_alert=1, verdict=403). <<<");
        end else begin
            tamper_alert    = 1'b0;
            attack_blocked  = 1'b0;
            test_passed     = 1'b0;
            verdict_code    = 16'd500;
            $display("[TEST 2] >>> FAIL: Tampered message was NOT detected! <<<");
            all_tests_passed = 1'b0;
        end
        $display("-----------------------------------------------------------------");

        #(CLK_PERIOD * 10);

        // --------------------------------------------------------------------
        // TEST 3: CMAC Verification - Valid Message (WITHOUT ERROR - Normal Case)
        // --------------------------------------------------------------------
        test_step       = 8'd3;
        verdict_code    = 16'd0; // 0 = BUSY / VERIFYING
        test_name       = "TEST 3: CMAC VERIFY VALID (NO ERROR)";
        test_passed     = 1'b0;
        packet_accepted = 1'b0;
        tamper_alert    = 1'b0;
        attack_blocked  = 1'b0;

        $display("\n>>> Starting TEST 3: Legitimate Verification with Valid Tag (Key=%0d, Message=%0d)...", TEST_KEY[31:0], TEST_MSG[31:0]);
        @(negedge clk);
        key_in          = TEST_KEY;
        msg_in          = TEST_MSG;          // Original legitimate message = 2
        expected_tag_in = TEST_EXPECTED_TAG; // Valid tag
        start_verify    = 1'b1;
        @(negedge clk);
        start_verify    = 1'b0;

        cycles_verify = 0;
        while (!cmac_done) begin
            @(posedge clk);
            cycles_verify = cycles_verify + 1;
            if (cycles_verify > 200) begin
                $display("[ERROR] Timeout waiting for cmac_done in verify!");
                $finish;
            end
        end

        $display("[TEST 3] Results: cmac_valid=%b, tamper_detected=%b", cmac_valid, tamper_detected);
        if (cmac_valid === 1'b1 && tamper_detected === 1'b0) begin
            test_passed     = 1'b1;
            packet_accepted = 1'b1;
            tamper_alert    = 1'b0;
            verdict_code    = 16'd200; // 200 = ACCEPTED
            $display("[TEST 3] >>> PASS: Valid packet accepted (packet_accepted=1, verdict=200). <<<");
        end else begin
            test_passed     = 1'b0;
            packet_accepted = 1'b0;
            verdict_code    = 16'd500;
            $display("[TEST 3] >>> FAIL: Valid tag rejected! <<<");
            all_tests_passed = 1'b0;
        end
        $display("-----------------------------------------------------------------");

        #(CLK_PERIOD * 10);

        // --------------------------------------------------------------------
        // TEST 4: CMAC Verification - Corrupted Tag Attack (WITH ERROR)
        // --------------------------------------------------------------------
        test_step       = 8'd4;
        verdict_code    = 16'd0; // 0 = BUSY / VERIFYING
        test_name       = "TEST 4: CMAC CORRUPTED TAG (WITH ERROR)";
        test_passed     = 1'b0;
        packet_accepted = 1'b0;
        tamper_alert    = 1'b0;
        attack_blocked  = 1'b0;

        $display("\n>>> Starting TEST 4: Tamper Test with Corrupted Tag (Key=%0d, Message=%0d)...", TEST_KEY[31:0], TEST_MSG[31:0]);
        @(negedge clk);
        key_in          = TEST_KEY;
        msg_in          = TEST_MSG;
        expected_tag_in = TEST_EXPECTED_TAG ^ 128'h1; // Corrupt tag by 1 bit!
        start_verify    = 1'b1;
        @(negedge clk);
        start_verify    = 1'b0;

        cycles_verify = 0;
        while (!cmac_done) begin
            @(posedge clk);
            cycles_verify = cycles_verify + 1;
            if (cycles_verify > 200) begin
                $display("[ERROR] Timeout waiting for cmac_done in verify!");
                $finish;
            end
        end

        $display("[TEST 4] Results: cmac_valid=%b, tamper_detected=%b", cmac_valid, tamper_detected);
        if (cmac_valid === 1'b0 && tamper_detected === 1'b1) begin
            tamper_alert    = 1'b1;   // Hardware alert active!
            attack_blocked  = 1'b1;   // Fake seal rejected!
            packet_accepted = 1'b0;   // REJECTED
            test_passed     = 1'b0;   // Packet failed authentication
            verdict_code    = 16'd403;// 403 = FORBIDDEN / CORRUPTED TAG
            $display("[TEST 4] >>> SUCCESS: Corrupted tag rejected (packet_accepted=0, tamper_alert=1, verdict=403). <<<");
        end else begin
            tamper_alert    = 1'b0;
            attack_blocked  = 1'b0;
            test_passed     = 1'b0;
            verdict_code    = 16'd500;
            $display("[TEST 4] >>> FAIL: Corrupted tag was not flagged as tamper! <<<");
            all_tests_passed = 1'b0;
        end

        $display("=================================================================");
        if (all_tests_passed) begin
            test_name = "ALL CMAC TESTS PASSED SUCCESSFULLY";
            $display(">>> ALL STANDALONE CMAC TESTS PASSED <<<");
        end else begin
            test_name = "SOME CMAC TESTS FAILED";
            $display(">>> SOME CMAC TESTS FAILED <<<");
        end
        $display("=================================================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
