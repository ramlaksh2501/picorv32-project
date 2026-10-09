// ============================================================================
// aes_peripheral_tb.v
// Comprehensive Waveform Testbench for AES-128 & AES-CMAC Peripheral.
//
// Features for Waveform Inspection:
//   - Full visibility of 128-bit Keys, Plaintext, Ciphertext, and CMAC Tags
//   - Formatted ASCII 'test_name' string directly readable in Vivado Waveform
//   - Explicit Status Flags: key_ready, cipher_ready, busy, cmac_done,
//                            cmac_valid, and tamper_detected
//   - Waveform Alerts: 'tamper_alert' and 'test_passed'
//
// Test Sequence:
//   TEST 1: AES-128 Hardware Encryption (WITHOUT ERROR - NIST Vector)
//   TEST 2: AES-128 Hardware Decryption (WITHOUT ERROR - Recover Plaintext)
//   TEST 3: AES-CMAC Tag Generation & Verification (WITHOUT ERROR - Valid Packet)
//   TEST 4: AES-CMAC Verification (WITH ERROR - Tampered Message Rejected)
//   TEST 5: AES-CMAC Verification (WITH ERROR - Corrupted Tag Rejected)
// ============================================================================

`timescale 1ns / 1ps

module aes_peripheral_tb;

    // ------------------------------------------------------------------------
    // Clock and Reset (50 MHz clock: 20 ns period)
    // ------------------------------------------------------------------------
    reg clk;
    reg resetn;
    localparam CLK_PERIOD = 20;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // ------------------------------------------------------------------------
    // Bus Interface to DUT
    // ------------------------------------------------------------------------
    reg         sel;
    reg         mem_valid;
    reg         mem_ready;
    reg  [7:0]  addr;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    wire [31:0] rdata;

    // ------------------------------------------------------------------------
    // Waveform-friendly Monitored Signals (Easily added to Vivado Waveform)
    // ------------------------------------------------------------------------
    reg [255:0] test_name;              // Readable ASCII string in waveform!
    reg         test_passed;            // 1 = Current test passed
    reg         tamper_alert;           // 1 = Hardware flagged TAMPER / ERROR

    reg [127:0] waveform_key;           // 128-bit key being tested
    reg [127:0] waveform_plaintext;     // 128-bit input data / message
    reg [127:0] waveform_ciphertext;    // 128-bit direct AES result
    reg [127:0] waveform_cmac_tag;      // 128-bit generated CMAC tag
    reg [127:0] waveform_expected_tag;  // 128-bit expected CMAC tag

    // Simple human-readable probes (Readable in Unsigned Decimal)
    reg [7:0]   test_step;              // 1, 2, 3, 4, 5
    reg [15:0]  verdict_code;           // 0 = PENDING, 200 = ACCEPTED, 403 = TAMPER DETECTED
    reg         packet_accepted;        // 1 = Packet authentic & accepted, 0 = Tampered / rejected
    reg         attack_blocked;         // 1 = Hardware security caught and blocked the attack
    wire [15:0] short_key      = waveform_key[15:0];
    wire [15:0] short_message  = waveform_plaintext[15:0];
    wire [15:0] short_tag      = waveform_cmac_tag[15:0];
    wire [15:0] short_exp_tag  = waveform_expected_tag[15:0];

    // Status Register Bit Decodes (Directly observable in Waveform)
    reg [31:0] status_reg;
    wire       status_key_ready       = status_reg[0];
    wire       status_cipher_ready    = status_reg[1];
    wire       status_busy            = status_reg[2];
    wire       status_cmac_done       = status_reg[3];
    wire       status_cmac_valid      = status_reg[4];
    wire       status_tamper_detected = status_reg[5];

    // ------------------------------------------------------------------------
    // Instantiate DUT (Security Peripheral with AES-128 & CMAC)
    // ------------------------------------------------------------------------
    aes_peripheral uut (
        .clk       (clk),
        .resetn    (resetn),
        .sel       (sel),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready),
        .addr      (addr),
        .wdata     (wdata),
        .wstrb     (wstrb),
        .rdata     (rdata)
    );

    // ------------------------------------------------------------------------
    // Bus Helper Tasks
    // ------------------------------------------------------------------------
    task bus_write(input [7:0] a, input [31:0] d);
    begin
        @(posedge clk);
        sel       = 1'b1;
        mem_valid = 1'b1;
        mem_ready = 1'b0;
        addr      = a;
        wdata     = d;
        wstrb     = 4'b1111;
        @(posedge clk);
        mem_ready = 1'b1;
        @(posedge clk);
        sel       = 1'b0;
        mem_valid = 1'b0;
        mem_ready = 1'b0;
        wstrb     = 4'b0000;
    end
    endtask

    task bus_read(input [7:0] a, output [31:0] d);
    begin
        @(posedge clk);
        sel       = 1'b1;
        mem_valid = 1'b1;
        mem_ready = 1'b0;
        addr      = a;
        wstrb     = 4'b0000;
        @(posedge clk);
        mem_ready = 1'b1;
        #1;
        d         = rdata;
        @(posedge clk);
        sel       = 1'b0;
        mem_valid = 1'b0;
        mem_ready = 1'b0;
    end
    endtask

    task update_status;
    begin
        bus_read(8'h04, status_reg);
    end
    endtask

    // ------------------------------------------------------------------------
    // Test Vectors (Simple human-readable numbers: Key=1, PT=2, Msg=2)
    // ------------------------------------------------------------------------
    // AES-128
    localparam [127:0] AES_KEY = 128'd1;
    localparam [127:0] AES_PT  = 128'd2;
    localparam [127:0] AES_CT  = 128'h9592d775_7c44182c_33a42ee9_5147a2df;

    // AES-CMAC
    localparam [127:0] CMAC_KEY = 128'd1;
    localparam [127:0] CMAC_MSG = 128'd2;
    localparam [127:0] CMAC_TAG = 128'ha6a424f0_a5447dfc_508f8909_d4aac37f;

    reg [31:0] r0, r1, r2, r3;
    integer all_tests_passed;

    // ------------------------------------------------------------------------
    // Main Stimulus Process
    // ------------------------------------------------------------------------
    initial begin
        // 0. Initialize bus and flags
        sel                   = 1'b0;
        mem_valid             = 1'b0;
        mem_ready             = 1'b0;
        addr                  = 8'h00;
        wdata                 = 32'h0;
        wstrb                 = 4'h0;
        resetn                = 1'b0;
        test_name             = "INITIALIZING";
        test_passed           = 1'b0;
        tamper_alert          = 1'b0;
        status_reg            = 32'h0;
        waveform_key          = 128'h0;
        waveform_plaintext    = 128'h0;
        waveform_ciphertext   = 128'h0;
        waveform_cmac_tag     = 128'h0;
        waveform_expected_tag = 128'h0;
        all_tests_passed      = 1;

        $display("===============================================================");
        $display("      AES-128 & CMAC HARDWARE PERIPHERAL WAVEFORM TESTBENCH    ");
        $display("===============================================================");

        #(CLK_PERIOD * 3);
        resetn = 1'b1;
        #(CLK_PERIOD * 2);

        // ====================================================================
        // TEST 1: Direct AES-128 Encryption (WITHOUT ERROR - Simple Numbers)
        // ====================================================================
        test_step          = 8'd1;
        verdict_code       = 16'd200;
        test_name          = "TEST 1: AES ENCRYPT (NO ERROR)";
        waveform_key       = AES_KEY;
        waveform_plaintext = AES_PT;
        test_passed        = 1'b0;
        tamper_alert       = 1'b0;

        $display("\n>>> Starting TEST 1: Direct AES-128 Encryption with Key=%0d, PT=%0d...", AES_KEY[31:0], AES_PT[31:0]);
        // Load Key
        bus_write(8'h20, waveform_key[127:96]);
        bus_write(8'h24, waveform_key[95:64]);
        bus_write(8'h28, waveform_key[63:32]);
        bus_write(8'h2C, waveform_key[31:0]);

        // Trigger Key Expansion (CMD_INIT_KEY = bit 2)
        bus_write(8'h00, 32'h04);
        #(CLK_PERIOD * 3);
        update_status();
        while (!status_key_ready) begin
            #(CLK_PERIOD);
            update_status();
        end

        // Load Plaintext
        bus_write(8'h10, waveform_plaintext[127:96]);
        bus_write(8'h14, waveform_plaintext[95:64]);
        bus_write(8'h18, waveform_plaintext[63:32]);
        bus_write(8'h1C, waveform_plaintext[31:0]);

        // Start Encryption (CMD_START_ENCRYPT = bit 0)
        bus_write(8'h00, 32'h01);
        #(CLK_PERIOD * 3);
        update_status();
        while (!status_cipher_ready) begin
            #(CLK_PERIOD);
            update_status();
        end

        // Read Ciphertext Result
        bus_read(8'h30, r0);
        bus_read(8'h34, r1);
        bus_read(8'h38, r2);
        bus_read(8'h3C, r3);
        waveform_ciphertext = {r0, r1, r2, r3};

        $display("  Actual Ciphertext:   %h", waveform_ciphertext);
        $display("  Expected Ciphertext: %h", AES_CT);

        if (waveform_ciphertext === AES_CT) begin
            test_passed = 1'b1;
            $display("  [STATUS] >>> TEST 1 PASS: Ciphertext matches expected value! <<<");
        end else begin
            test_passed = 1'b0;
            all_tests_passed = 0;
            $display("  [STATUS] >>> TEST 1 FAIL: Ciphertext mismatch! <<<");
        end

        #(CLK_PERIOD * 4);

        // ====================================================================
        // TEST 2: Direct AES-128 Decryption (WITHOUT ERROR - Roundtrip)
        // ====================================================================
        test_step   = 8'd2;
        verdict_code= 16'd200;
        test_name   = "TEST 2: AES DECRYPT (NO ERROR)";
        test_passed = 1'b0;

        $display("\n>>> Starting TEST 2: Direct AES-128 Decryption (Recover Plaintext %0d)...", AES_PT[31:0]);
        // Load Ciphertext into DATA registers
        bus_write(8'h10, waveform_ciphertext[127:96]);
        bus_write(8'h14, waveform_ciphertext[95:64]);
        bus_write(8'h18, waveform_ciphertext[63:32]);
        bus_write(8'h1C, waveform_ciphertext[31:0]);

        // Start Decryption (CMD_START_DECRYPT = bit 1)
        bus_write(8'h00, 32'h02);
        update_status();
        while (status_cipher_ready) begin
            #(CLK_PERIOD);
            update_status();
        end
        while (!status_cipher_ready) begin
            #(CLK_PERIOD);
            update_status();
        end

        // Read Recovered Plaintext Result
        bus_read(8'h30, r0);
        bus_read(8'h34, r1);
        bus_read(8'h38, r2);
        bus_read(8'h3C, r3);
        waveform_plaintext = {r0, r1, r2, r3};

        $display("  Recovered Plaintext: %0d (0x%h)", waveform_plaintext[31:0], waveform_plaintext);
        $display("  Original Plaintext:  %0d (0x%h)", AES_PT[31:0], AES_PT);

        if (waveform_plaintext === AES_PT) begin
            test_passed = 1'b1;
            $display("  [STATUS] >>> TEST 2 PASS: Decrypted data matches original! <<<");
        end else begin
            test_passed = 1'b0;
            all_tests_passed = 0;
            $display("  [STATUS] >>> TEST 2 FAIL: Decrypted data mismatch! <<<");
        end

        #(CLK_PERIOD * 4);

        // ====================================================================
        // TEST 3: Hardware CMAC Tag Gen & Verify (WITHOUT ERROR - Valid Packet)
        // ====================================================================
        test_step             = 8'd3;
        verdict_code          = 16'd200;
        test_name             = "TEST 3: CMAC VERIFY (NO ERROR - VALID)";
        waveform_key          = CMAC_KEY;
        waveform_plaintext    = CMAC_MSG;
        waveform_expected_tag = CMAC_TAG;
        test_passed           = 1'b0;
        tamper_alert          = 1'b0;

        $display("\n>>> Starting TEST 3: CMAC Generation & Valid Verification (Key=%0d, Msg=%0d)...", CMAC_KEY[31:0], CMAC_MSG[31:0]);
        // Load CMAC Key
        bus_write(8'h20, waveform_key[127:96]);
        bus_write(8'h24, waveform_key[95:64]);
        bus_write(8'h28, waveform_key[63:32]);
        bus_write(8'h2C, waveform_key[31:0]);

        // Load Message
        bus_write(8'h10, waveform_plaintext[127:96]);
        bus_write(8'h14, waveform_plaintext[95:64]);
        bus_write(8'h18, waveform_plaintext[63:32]);
        bus_write(8'h1C, waveform_plaintext[31:0]);

        // Generate Tag (CMD_CMAC_GENERATE = bit 3)
        bus_write(8'h00, 32'h08);
        update_status();
        while (status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end
        while (!status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end

        // Read Calculated Tag
        bus_read(8'h40, r0);
        bus_read(8'h44, r1);
        bus_read(8'h48, r2);
        bus_read(8'h4C, r3);
        waveform_cmac_tag = {r0, r1, r2, r3};
        $display("  Calculated CMAC Tag: %h", waveform_cmac_tag);
        $display("  Expected CMAC Tag:   %h", CMAC_TAG);

        // Now Verify with Expected Tag loaded into CMAC_EXP registers
        bus_write(8'h50, waveform_expected_tag[127:96]);
        bus_write(8'h54, waveform_expected_tag[95:64]);
        bus_write(8'h58, waveform_expected_tag[63:32]);
        bus_write(8'h5C, waveform_expected_tag[31:0]);

        // Start Verification (CMD_CMAC_VERIFY = bit 4)
        bus_write(8'h00, 32'h10);
        update_status();
        while (status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end
        while (!status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end

        $display("  Status Flags: cmac_valid=%b, tamper_detected=%b", status_cmac_valid, status_tamper_detected);
        if (status_cmac_valid === 1'b1 && status_tamper_detected === 1'b0) begin
            test_passed = 1'b1;
            $display("  [STATUS] >>> TEST 3 PASS: Packet Accepted (CMAC_VALID=1, NO TAMPER) <<<");
        end else begin
            test_passed = 1'b0;
            all_tests_passed = 0;
            $display("  [STATUS] >>> TEST 3 FAIL: Valid packet was rejected! <<<");
        end

        #(CLK_PERIOD * 4);

        // ====================================================================
        // TEST 4: Hardware CMAC Verification (WITH ERROR - Tampered Message)
        // ====================================================================
        test_step          = 8'd4;
        verdict_code       = 16'd0; // 0 = BUSY / VERIFYING
        test_name          = "TEST 4: CMAC TAMPER MESSAGE (WITH ERROR)";
        waveform_plaintext = 128'd3; // Modified message = 3 (original was 2!)
        test_passed        = 1'b0;
        packet_accepted    = 1'b0;
        tamper_alert       = 1'b0;
        attack_blocked     = 1'b0;

        $display("\n>>> Starting TEST 4: Verification with Tampered Message (Modified Message=3 vs Original=2)...");
        // Load tampered message (last word modified)
        bus_write(8'h10, waveform_plaintext[127:96]);
        bus_write(8'h14, waveform_plaintext[95:64]);
        bus_write(8'h18, waveform_plaintext[63:32]);
        bus_write(8'h1C, waveform_plaintext[31:0]);

        // Keep original valid tag in CMAC_EXP0..3 and start verification
        bus_write(8'h00, 32'h10);
        update_status();
        while (status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end
        while (!status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end

        $display("  Status Flags: cmac_valid=%b, tamper_detected=%b", status_cmac_valid, status_tamper_detected);
        if (status_cmac_valid === 1'b0 && status_tamper_detected === 1'b1) begin
            tamper_alert    = 1'b1;   // Waveform shows active tamper alert!
            attack_blocked  = 1'b1;   // Attack caught!
            packet_accepted = 1'b0;   // REJECTED
            test_passed     = 1'b0;   // Packet failed authentication
            verdict_code    = 16'd403;// 403 = FORBIDDEN / TAMPER
            $display("  [STATUS] >>> SUCCESS: Tampering Detected! Packet rejected (packet_accepted=0, verdict=403). <<<");
        end else begin
            tamper_alert    = 1'b0;
            attack_blocked  = 1'b0;
            test_passed     = 1'b0;
            verdict_code    = 16'd500;
            all_tests_passed = 0;
            $display("  [STATUS] >>> TEST 4 FAIL: Tampered message was NOT flagged! <<<");
        end

        #(CLK_PERIOD * 10);

        // ====================================================================
        // TEST 5: Hardware CMAC Verification (WITH ERROR - Corrupted Tag)
        // ====================================================================
        test_step             = 8'd5;
        verdict_code          = 16'd0; // 0 = BUSY / VERIFYING
        test_name             = "TEST 5: CMAC CORRUPTED TAG (WITH ERROR)";
        waveform_plaintext    = CMAC_MSG;            // Restore valid message (2)
        waveform_expected_tag = CMAC_TAG ^ 128'h1;   // Corrupt tag by 1 bit
        test_passed           = 1'b0;
        packet_accepted       = 1'b0;
        tamper_alert          = 1'b0;
        attack_blocked        = 1'b0;

        $display("\n>>> Starting TEST 5: Verification with Corrupted Expected Tag (Expected Error)...");
        // Load clean message
        bus_write(8'h10, waveform_plaintext[127:96]);
        bus_write(8'h14, waveform_plaintext[95:64]);
        bus_write(8'h18, waveform_plaintext[63:32]);
        bus_write(8'h1C, waveform_plaintext[31:0]);

        // Load corrupted tag into expected tag registers
        bus_write(8'h50, waveform_expected_tag[127:96]);
        bus_write(8'h54, waveform_expected_tag[95:64]);
        bus_write(8'h58, waveform_expected_tag[63:32]);
        bus_write(8'h5C, waveform_expected_tag[31:0]);

        // Start Verification
        bus_write(8'h00, 32'h10);
        update_status();
        while (status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end
        while (!status_cmac_done) begin
            #(CLK_PERIOD);
            update_status();
        end

        $display("  Status Flags: cmac_valid=%b, tamper_detected=%b", status_cmac_valid, status_tamper_detected);
        if (status_cmac_valid === 1'b0 && status_tamper_detected === 1'b1) begin
            tamper_alert    = 1'b1;
            attack_blocked  = 1'b1;
            packet_accepted = 1'b0;   // REJECTED
            test_passed     = 1'b0;   // Packet failed authentication
            verdict_code    = 16'd403;// 403 = FORBIDDEN / CORRUPTED TAG
            $display("  [STATUS] >>> SUCCESS: Corrupted tag correctly flagged as TAMPER! Packet rejected (packet_accepted=0, verdict=403). <<<");
        end else begin
            tamper_alert    = 1'b0;
            attack_blocked  = 1'b0;
            test_passed     = 1'b0;
            verdict_code    = 16'd500;
            all_tests_passed = 0;
            $display("  [STATUS] >>> TEST 5 FAIL: Corrupted tag was not flagged! <<<");
        end

        #(CLK_PERIOD * 10);

        // ====================================================================
        // Final Summary
        // ====================================================================
        test_name = (all_tests_passed) ? "ALL TESTS COMPLETED SUCCESSFULLY" : "TESTS COMPLETED WITH FAILURES";
        $display("===============================================================");
        if (all_tests_passed) begin
            $display(">>> ALL 5 TESTS (WITHOUT ERROR & WITH ERROR) PASSED! <<<");
        end else begin
            $display(">>> SOME TESTS FAILED! <<<");
        end
        $display("===============================================================");

        #(CLK_PERIOD * 10);
        $finish;
    end

endmodule
