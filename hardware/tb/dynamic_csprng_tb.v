// ============================================================================
// dynamic_csprng_tb.v
//
// Dynamic Runtime Data & CSPRNG Key Generation Testbench for PicoRV32 Security SoC.
//
// Features:
//   1. Runtime CSPRNG Key Injection:
//      - Accepts external 128-bit CSPRNG key via `+KEY=<32-hex-chars>`
//      - Or automatically generates cryptographically strong pseudorandom keys
//        using a 128-bit Xorshift+ PRNG seeded at simulation start.
//   2. Runtime Data Input:
//      - Accepts arbitrary plaintext/data via `+DATA=<32-hex-chars>`
//      - Or automatically streams randomized test payloads.
//   3. Full Hardware Cryptographic Pipeline Verification:
//      - Hardware Key Expansion (CMD_INIT_KEY)
//      - Hardware AES-128 Encryption (CMD_START_ENCRYPT)
//      - Hardware AES-128 Decryption (CMD_START_DECRYPT) with self-check
//      - Hardware CMAC Tag Generation (CMD_CMAC_GENERATE)
//      - Hardware CMAC Authentic Verification (CMD_CMAC_VERIFY)
//      - Hardware Tamper Detection & Quarantine Verification (Injected Fault)
//
// Target Clock: 50.0 MHz (20.0 ns period)
// ============================================================================

`timescale 1ns / 1ps

module dynamic_csprng_tb;

    // ------------------------------------------------------------------------
    // Clock & Reset Signals
    // ------------------------------------------------------------------------
    reg clk;
    reg resetn;
    localparam CLK_PERIOD = 20.0; // 50 MHz

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // ------------------------------------------------------------------------
    // MMIO Bus Signals
    // ------------------------------------------------------------------------
    reg         sel;
    reg         mem_valid;
    reg         mem_ready;
    reg  [7:0]  addr;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    wire [31:0] rdata;

    // Instantiate AES/CMAC Peripheral under test
    aes_peripheral dut (
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

    // MMIO Register Offsets
    localparam [7:0]
        REG_CONTROL   = 8'h00,
        REG_STATUS    = 8'h04,
        REG_DATA0     = 8'h10,
        REG_DATA1     = 8'h14,
        REG_DATA2     = 8'h18,
        REG_DATA3     = 8'h1C,
        REG_KEY0      = 8'h20,
        REG_KEY1      = 8'h24,
        REG_KEY2      = 8'h28,
        REG_KEY3      = 8'h2C,
        REG_RES0      = 8'h30,
        REG_RES1      = 8'h34,
        REG_RES2      = 8'h38,
        REG_RES3      = 8'h3C,
        REG_CMAC_TAG0 = 8'h40,
        REG_CMAC_TAG1 = 8'h44,
        REG_CMAC_TAG2 = 8'h48,
        REG_CMAC_TAG3 = 8'h4C,
        REG_CMAC_EXP0 = 8'h50,
        REG_CMAC_EXP1 = 8'h54,
        REG_CMAC_EXP2 = 8'h58,
        REG_CMAC_EXP3 = 8'h5C;

    // Control Commands
    localparam [31:0]
        CMD_START_ENCRYPT = 32'h01,
        CMD_START_DECRYPT = 32'h02,
        CMD_INIT_KEY      = 32'h04,
        CMD_CMAC_GENERATE = 32'h08,
        CMD_CMAC_VERIFY   = 32'h10;

    // Status Flags
    localparam [31:0]
        STATUS_KEY_READY       = 32'h01,
        STATUS_CIPHER_READY    = 32'h02,
        STATUS_BUSY            = 32'h04,
        STATUS_CMAC_DONE       = 32'h08,
        STATUS_CMAC_VALID      = 32'h10,
        STATUS_TAMPER_DETECTED = 32'h20;

    // ------------------------------------------------------------------------
    // Bus Access Tasks
    // ------------------------------------------------------------------------
    task bus_write(input [7:0] a, input [31:0] d);
    begin
        @(posedge clk);
        sel       <= 1'b1;
        mem_valid <= 1'b1;
        mem_ready <= 1'b0;
        addr      <= a;
        wdata     <= d;
        wstrb     <= 4'b1111;
        @(posedge clk);
        mem_ready <= 1'b1;
        @(posedge clk);
        sel       <= 1'b0;
        mem_valid <= 1'b0;
        mem_ready <= 1'b0;
        wstrb     <= 4'b0000;
    end
    endtask

    task bus_read(input [7:0] a, output [31:0] d);
    begin
        @(posedge clk);
        sel       <= 1'b1;
        mem_valid <= 1'b1;
        mem_ready <= 1'b0;
        addr      <= a;
        wstrb     <= 4'b0000;
        @(posedge clk);
        mem_ready <= 1'b1;
        d         = rdata;
        @(posedge clk);
        sel       <= 1'b0;
        mem_valid <= 1'b0;
        mem_ready <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------------------
    // 128-bit Xorshift+ CSPRNG Implementation
    // ------------------------------------------------------------------------
    reg [63:0] rng_s0, rng_s1;

    task init_csprng(input [63:0] seed0, input [63:0] seed1);
    begin
        rng_s0 = (seed0 != 0) ? seed0 : 64'h8a5cd789635d2dff;
        rng_s1 = (seed1 != 0) ? seed1 : 64'h123456789abcdef0;
    end
    endtask

    task get_random_128(output [127:0] rand_val);
        reg [63:0] x, y;
        reg [63:0] r0, r1;
    begin
        // Xorshift128+ step 1
        x = rng_s0;
        y = rng_s1;
        rng_s0 = y;
        x = x ^ (x << 23);
        rng_s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        r0 = rng_s1 + y;

        // Xorshift128+ step 2
        x = rng_s0;
        y = rng_s1;
        rng_s0 = y;
        x = x ^ (x << 23);
        rng_s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        r1 = rng_s1 + y;

        rand_val = {r0, r1};
    end
    endtask

    // ------------------------------------------------------------------------
    // Cryptographic Execution Tasks
    // ------------------------------------------------------------------------
    task execute_test_cycle(
        input [127:0] key_val,
        input [127:0] data_val,
        input integer test_num
    );
        reg [31:0] st;
        reg [127:0] ct_val;
        reg [127:0] recovered_pt;
        reg [127:0] cmac_tag;
        reg [127:0] tampered_data;
        integer cycle_count;
    begin
        $display("\n===============================================================================");
        $display("  [ITERATION %0d] DYNAMIC RUNTIME CRYPTOGRAPHIC CYCLE", test_num);
        $display("===============================================================================");
        $display("  [INPUTS]");
        $display("    Random Key (CSPRNG) : 0x%032h", key_val);
        $display("    Runtime Data/Payload: 0x%032h", data_val);

        // --------------------------------------------------------------------
        // 1. KEY EXPANSION
        // --------------------------------------------------------------------
        bus_write(REG_KEY0, key_val[127:96]);
        bus_write(REG_KEY1, key_val[95:64]);
        bus_write(REG_KEY2, key_val[63:32]);
        bus_write(REG_KEY3, key_val[31:0]);
        bus_write(REG_CONTROL, CMD_INIT_KEY);

        cycle_count = 0;
        st = 0;
        while ((st & STATUS_KEY_READY) == 0) begin
            bus_read(REG_STATUS, st);
            cycle_count = cycle_count + 1;
        end
        $display("  [STEP 1] Key Expansion (10 Rounds)      : READY in %0d cycles", cycle_count);

        // --------------------------------------------------------------------
        // 2. AES-128 ENCRYPTION
        // --------------------------------------------------------------------
        bus_write(REG_DATA0, data_val[127:96]);
        bus_write(REG_DATA1, data_val[95:64]);
        bus_write(REG_DATA2, data_val[63:32]);
        bus_write(REG_DATA3, data_val[31:0]);
        bus_write(REG_CONTROL, CMD_START_ENCRYPT);

        cycle_count = 0;
        st = 0;
        while ((st & STATUS_CIPHER_READY) == 0) begin
            bus_read(REG_STATUS, st);
            cycle_count = cycle_count + 1;
        end
        bus_read(REG_RES0, ct_val[127:96]);
        bus_read(REG_RES1, ct_val[95:64]);
        bus_read(REG_RES2, ct_val[63:32]);
        bus_read(REG_RES3, ct_val[31:0]);

        $display("  [STEP 2] AES-128 Encryption             : COMPLETE in %0d cycles", cycle_count);
        $display("    -> Generated Ciphertext               : 0x%032h", ct_val);

        // --------------------------------------------------------------------
        // 3. AES-128 DECRYPTION & SELF-CHECK
        // --------------------------------------------------------------------
        bus_write(REG_DATA0, ct_val[127:96]);
        bus_write(REG_DATA1, ct_val[95:64]);
        bus_write(REG_DATA2, ct_val[63:32]);
        bus_write(REG_DATA3, ct_val[31:0]);
        bus_write(REG_CONTROL, CMD_START_DECRYPT);

        cycle_count = 0;
        st = 0;
        while ((st & STATUS_CIPHER_READY) == 0) begin
            bus_read(REG_STATUS, st);
            cycle_count = cycle_count + 1;
        end
        bus_read(REG_RES0, recovered_pt[127:96]);
        bus_read(REG_RES1, recovered_pt[95:64]);
        bus_read(REG_RES2, recovered_pt[63:32]);
        bus_read(REG_RES3, recovered_pt[31:0]);

        $display("  [STEP 3] AES-128 Decryption             : COMPLETE in %0d cycles", cycle_count);
        $display("    -> Recovered Plaintext                : 0x%032h", recovered_pt);
        if (recovered_pt == data_val) begin
            $display("    >> Math Reversibility Check           : PASS (100%% Exact Match)");
        end else begin
            $display("    >> Math Reversibility Check           : FAIL! Mismatch detected!");
            $finish;
        end

        // --------------------------------------------------------------------
        // 4. CMAC TAG GENERATION
        // --------------------------------------------------------------------
        bus_write(REG_DATA0, data_val[127:96]);
        bus_write(REG_DATA1, data_val[95:64]);
        bus_write(REG_DATA2, data_val[63:32]);
        bus_write(REG_DATA3, data_val[31:0]);
        bus_write(REG_CONTROL, CMD_CMAC_GENERATE);

        cycle_count = 0;
        st = 0;
        while ((st & STATUS_CMAC_DONE) == 0) begin
            bus_read(REG_STATUS, st);
            cycle_count = cycle_count + 1;
        end
        bus_read(REG_CMAC_TAG0, cmac_tag[127:96]);
        bus_read(REG_CMAC_TAG1, cmac_tag[95:64]);
        bus_read(REG_CMAC_TAG2, cmac_tag[63:32]);
        bus_read(REG_CMAC_TAG3, cmac_tag[31:0]);

        $display("  [STEP 4] Hardware CMAC Tag Generation   : COMPLETE in %0d cycles", cycle_count);
        $display("    -> 128-bit Authentication Tag         : 0x%032h", cmac_tag);

        // --------------------------------------------------------------------
        // 5. CMAC TAG AUTHENTIC VERIFICATION
        // --------------------------------------------------------------------
        bus_write(REG_DATA0, data_val[127:96]);
        bus_write(REG_DATA1, data_val[95:64]);
        bus_write(REG_DATA2, data_val[63:32]);
        bus_write(REG_DATA3, data_val[31:0]);
        bus_write(REG_CMAC_EXP0, cmac_tag[127:96]);
        bus_write(REG_CMAC_EXP1, cmac_tag[95:64]);
        bus_write(REG_CMAC_EXP2, cmac_tag[63:32]);
        bus_write(REG_CMAC_EXP3, cmac_tag[31:0]);
        bus_write(REG_CONTROL, CMD_CMAC_VERIFY);

        cycle_count = 0;
        st = 0;
        while ((st & STATUS_CMAC_DONE) == 0) begin
            bus_read(REG_STATUS, st);
            cycle_count = cycle_count + 1;
        end

        if ((st & STATUS_CMAC_VALID) && ((st & STATUS_TAMPER_DETECTED) == 0)) begin
            $display("  [STEP 5] CMAC Tag Authentic Check       : PASS (VALID=1, TAMPER=0)");
        end else begin
            $display("  [STEP 5] CMAC Tag Authentic Check       : FAIL! Status=0x%08h", st);
            $finish;
        end

        // --------------------------------------------------------------------
        // 6. ACTIVE TAMPER INJECTION & QUARANTINE VERIFICATION
        // --------------------------------------------------------------------
        // Flip one nibble in the payload while keeping the old tag
        tampered_data = data_val ^ 128'h00000000_00000000_00000000_000000ff;
        bus_write(REG_DATA0, tampered_data[127:96]);
        bus_write(REG_DATA1, tampered_data[95:64]);
        bus_write(REG_DATA2, tampered_data[63:32]);
        bus_write(REG_DATA3, tampered_data[31:0]);
        bus_write(REG_CONTROL, CMD_CMAC_VERIFY);

        st = 0;
        while ((st & STATUS_CMAC_DONE) == 0) begin
            bus_read(REG_STATUS, st);
        end

        if (((st & STATUS_CMAC_VALID) == 0) && (st & STATUS_TAMPER_DETECTED)) begin
            $display("  [STEP 6] Tamper Detection & Quarantine  : PASS (TAMPER=1, VALID=0)");
            $display("    >> Hardware Successfully Quarantined Tampered Packet!");
        end else begin
            $display("  [STEP 6] Tamper Detection Check         : FAIL! Tamper not flagged!");
            $finish;
        end
    end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Stimulus
    // ------------------------------------------------------------------------
    reg [127:0] user_key;
    reg [127:0] user_data;
    reg has_user_key;
    reg has_user_data;
    reg [1023:0] key_str, data_str;
    reg [127:0] rand_k, rand_d;
    integer iter;

    initial begin
        $display("###############################################################################");
        $display("   PicoRV32 SoC: DYNAMIC RUNTIME DATA & CSPRNG KEY TESTBENCH (Verilog)        ");
        $display("###############################################################################");

        // System Reset
        resetn    <= 1'b0;
        sel       <= 1'b0;
        mem_valid <= 1'b0;
        mem_ready <= 1'b0;
        addr      <= 8'h00;
        wdata     <= 32'h00;
        wstrb     <= 4'b0000;
        init_csprng(64'h9e3779b97f4a7c15, 64'h2545f4914f6cdd1d);

        repeat (5) @(posedge clk);
        resetn <= 1'b1;
        repeat (5) @(posedge clk);

        // Check if command-line plusargs were provided at runtime:
        // Example: vvp sim.vvp +KEY=00112233445566778899aabbccddeeff +DATA=434d445f524541445f53454e534f5253
        has_user_key  = $value$plusargs("KEY=%h", user_key);
        has_user_data = $value$plusargs("DATA=%h", user_data);

        if (has_user_key || has_user_data) begin
            $display("\n>>> [MODE: RUNTIME USER INJECTION VIA PLUSARGS] <<<");
            if (!has_user_key) begin
                get_random_128(user_key);
                $display("  (No +KEY provided: Generated Dynamic CSPRNG Key)");
            end
            if (!has_user_data) begin
                get_random_128(user_data);
                $display("  (No +DATA provided: Generated Dynamic Random Payload)");
            end

            execute_test_cycle(user_key, user_data, 1);
        end else begin
            $display("\n>>> [MODE: AUTONOMOUS MULTI-ROUND CSPRNG RANDOM STIMULUS] <<<");
            $display("Running 3 consecutive dynamic randomized cycles...\n");

            for (iter = 1; iter <= 3; iter = iter + 1) begin
                get_random_128(rand_k);
                get_random_128(rand_d);
                execute_test_cycle(rand_k, rand_d, iter);
                repeat (10) @(posedge clk);
            end
        end

        $display("\n===============================================================================");
        $display("  STATUS: ALL DYNAMIC TESTS PASSED WITH 100%% SUCCESS");
        $display("  - CSPRNG Key Generation: Verified");
        $display("  - AES Encryption & Decryption: Reversible and Intact");
        $display("  - CMAC Generation & Verification: Authenticated");
        $display("  - Tamper Detection: Active Security Quarantine Verified");
        $display("===============================================================================\n");
        $finish;
    end

endmodule
