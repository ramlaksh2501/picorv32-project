// ============================================================================
// soc_aes_tb.v
// Simulation testbench for PicoRV32 SoC with integrated AES-128 peripheral.
// Runs the compiled RISC-V application from App RAM and captures UART output.
// ============================================================================

`timescale 1ns / 1ps

module soc_aes_tb;

    reg clk;
    reg btn_rst;
    wire [15:0] led;
    reg UART_rxd;
    wire UART_txd;

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Instantiate integrated SoC top module
    top uut (
        .clk      (clk),
        .btn_rst  (btn_rst),
        .led      (led),
        .UART_rxd (UART_rxd),
        .UART_txd (UART_txd)
    );

    // Direct UART write monitor for instant simulation feedback
    always @(posedge uut.clk_sys) begin
        if (uut.mem_valid && uut.mem_ready && uut.uart_sel && (uut.mem_addr[3:2] == 2'b00) && (|uut.mem_wstrb)) begin
            $write("%c", uut.mem_wdata[7:0]);
            $fflush();
        end
    end

    // AES transaction monitor
    always @(posedge uut.clk_sys) begin
        if (uut.mem_valid && uut.mem_ready && uut.aes_sel && (|uut.mem_wstrb)) begin
            $display("[TB BUS WRITE] AES Addr=0x%02x, WData=0x%08x", uut.mem_addr[7:0], uut.mem_wdata);
        end
    end

    initial begin
        UART_rxd = 1'b1;
        btn_rst = 1'b1; // active-high reset

        // Wait past time 0 so all internal module initial blocks have settled
        #50;

        // Preload App RAM with compiled aes_test_app.hex
        $readmemh("app/aes_test_app.hex", uut.appram);

        // Simulation jump: redirect reset vector in Boot ROM to App RAM (0x10000000)
        // 0: lui t0, 0x10000  -> 0x100002b7
        // 1: jr  t0           -> 0x00028067
        uut.bootrom[0] = 32'h100002b7;
        uut.bootrom[1] = 32'h00028067;

        #150;
        btn_rst = 1'b0; // release reset
        $display("[TB] Reset released, CPU booting...");

        // Monitor LEDs and timeout
        wait (led == 16'hFFFF || led == 16'hDEAD);
        #500;

        if (led == 16'hFFFF) begin
            $display("\n[TB] SUCCESS: LED pattern 0xFFFF (All LEDs ON -> PASS)");
        end else begin
            $display("\n[TB] FAILURE: LED pattern 0x%04x -> FAIL", led);
        end

        $finish;
    end

    // Safety timeout: 150 ms to allow all UART characters at 115200 baud
    initial begin
        #150_000_000;
        $display("\n[TB] Timeout reached! Current LED=0x%04x, PC=%h", led, uut.cpu.reg_pc);
        $finish;
    end

endmodule
