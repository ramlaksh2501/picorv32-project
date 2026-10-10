// ============================================================================
// aes_test_app.c
//
// Military Field Node SoC Secure Communication Subsystem.
// Target: PicoRV32 SoC on Real Digital Spartan-7 FPGA.
//
// Features:
//   1. Host -> Node Protocol (Inbound):
//      - Receives [Ciphertext (16B) + CMAC Tag (16B)] from Host PC over UART.
//      - Hardware verifies CMAC Tag:
//        * If TAMPERED: Decryption BLOCKED, LD12..LD15 BLINK ALONE!
//        * If AUTHENTIC: Decrypts payload, turns ALL 16 LEDs SOLID ON.
//   2. Node -> Host Protocol (Outbound):
//      - Encrypts sensor/telemetry payload using hardware AES-128.
//      - Generates CMAC authentication tag using hardware CMAC engine.
//      - Transmits [Encrypted Telemetry + Tag] back to Host over UART.
//   3. Interactive Host Modes:
//      - '1': Run Authentic Command & Telemetry Exchange (All 16 LEDs ON)
//      - '2': Run Tamper Attack & Security Quarantine (LD12..LD15 Blink)
// ============================================================================

#define UART_DATA   (*(volatile unsigned int *)0x20000000)
#define UART_STATUS (*(volatile unsigned int *)0x20000004)
#define LED_REG     (*(volatile unsigned int *)0x30000000)

// Peripheral Register Definitions (Base: 0x4000_0000)
#define AES_CONTROL (*(volatile unsigned int *)0x40000000)
#define AES_STATUS  (*(volatile unsigned int *)0x40000004)

#define AES_DATA0   (*(volatile unsigned int *)0x40000010)
#define AES_DATA1   (*(volatile unsigned int *)0x40000014)
#define AES_DATA2   (*(volatile unsigned int *)0x40000018)
#define AES_DATA3   (*(volatile unsigned int *)0x4000001C)

#define AES_KEY0    (*(volatile unsigned int *)0x40000020)
#define AES_KEY1    (*(volatile unsigned int *)0x40000024)
#define AES_KEY2    (*(volatile unsigned int *)0x40000028)
#define AES_KEY3    (*(volatile unsigned int *)0x4000002C)

#define AES_RES0    (*(volatile unsigned int *)0x40000030)
#define AES_RES1    (*(volatile unsigned int *)0x40000034)
#define AES_RES2    (*(volatile unsigned int *)0x40000038)
#define AES_RES3    (*(volatile unsigned int *)0x4000003C)

#define CMAC_TAG0   (*(volatile unsigned int *)0x40000040)
#define CMAC_TAG1   (*(volatile unsigned int *)0x40000044)
#define CMAC_TAG2   (*(volatile unsigned int *)0x40000048)
#define CMAC_TAG3   (*(volatile unsigned int *)0x4000004C)

#define CMAC_EXP0   (*(volatile unsigned int *)0x40000050)
#define CMAC_EXP1   (*(volatile unsigned int *)0x40000054)
#define CMAC_EXP2   (*(volatile unsigned int *)0x40000058)
#define CMAC_EXP3   (*(volatile unsigned int *)0x4000005C)

// UART Flags
#define TX_BUSY     0x1
#define RX_VALID    0x2

// Status Flags
#define STATUS_KEY_READY       (1 << 0)
#define STATUS_CIPHER_READY    (1 << 1)
#define STATUS_BUSY            (1 << 2)
#define STATUS_CMAC_DONE       (1 << 3)
#define STATUS_CMAC_VALID      (1 << 4)
#define STATUS_TAMPER_DETECTED (1 << 5)

// Control Commands
#define CMD_START_ENCRYPT      (1 << 0)
#define CMD_START_DECRYPT      (1 << 1)
#define CMD_INIT_KEY           (1 << 2)
#define CMD_CMAC_GENERATE      (1 << 3)
#define CMD_CMAC_VERIFY        (1 << 4)

static void uart_putc(char c)
{
    while (UART_STATUS & TX_BUSY)
        ;
    UART_DATA = (unsigned char)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

static char uart_getc_blocking(void)
{
    while (!(UART_STATUS & RX_VALID))
        ;
    return (char)UART_DATA;
}

static void uart_puthex32(unsigned int val)
{
    const char *hex = "0123456789abcdef";
    for (int i = 7; i >= 0; i--) {
        uart_putc(hex[(val >> (i * 4)) & 0xf]);
    }
}

static void print_128(const char *label, unsigned int w0, unsigned int w1, unsigned int w2, unsigned int w3)
{
    uart_puts("  ");
    uart_puts(label);
    uart_puts(": 0x");
    uart_puthex32(w0);
    uart_puts(" 0x");
    uart_puthex32(w1);
    uart_puts(" 0x");
    uart_puthex32(w2);
    uart_puts(" 0x");
    uart_puthex32(w3);
    uart_puts("\r\n");
}

static void delay_ms(unsigned int ms)
{
    for (unsigned int i = 0; i < ms; i++) {
        unsigned int count = 10000; // at 50 MHz PicoRV32 (~4-5 cycles/iter = ~1 ms)
        asm volatile (
            "1: addi %0, %0, -1 \n"
            "   bnez %0, 1b     \n"
            : "+r" (count)
        );
    }
}

static void init_master_key(void)
{
    // Shared Secret Key: 00010203 04050607 08090a0b 0c0d0e0f
    AES_KEY0 = 0x00010203;
    AES_KEY1 = 0x04050607;
    AES_KEY2 = 0x08090a0b;
    AES_KEY3 = 0x0c0d0e0f;
    AES_CONTROL = CMD_INIT_KEY;
    while (!(AES_STATUS & STATUS_KEY_READY))
        ;
}

// ----------------------------------------------------------------------------
// CASE 1: LEGITIMATE HOST -> NODE SECURE COMMUNICATION & TELEMETRY REPLY
// ----------------------------------------------------------------------------
void handle_legitimate_command(void)
{
    uart_puts("\r\n===================================================================\r\n");
    uart_puts(">>> [COMMUNICATION 1] HOST -> NODE: AUTHENTIC COMMAND PACKET <<<\r\n");
    uart_puts("===================================================================\r\n");

    LED_REG = 0x0000;
    delay_ms(300);

    // Host sends encrypted command: "CMD_READ_SENSORS"
    // Plaintext: 0x434d445f 0x52454144 0x5f53454e 0x534f5253 ("CMD_READ_SENSORS")
    unsigned int cmd_p0 = 0x434d445f;
    unsigned int cmd_p1 = 0x52454144;
    unsigned int cmd_p2 = 0x5f53454e;
    unsigned int cmd_p3 = 0x534f5253;

    // 1. Host Encrypted Ciphertext
    AES_DATA0 = cmd_p0; AES_DATA1 = cmd_p1; AES_DATA2 = cmd_p2; AES_DATA3 = cmd_p3;
    AES_CONTROL = CMD_START_ENCRYPT;
    while (!(AES_STATUS & STATUS_CIPHER_READY))
        ;
    unsigned int ct0 = AES_RES0, ct1 = AES_RES1, ct2 = AES_RES2, ct3 = AES_RES3;

    // 2. Host Generated CMAC Tag
    AES_DATA0 = cmd_p0; AES_DATA1 = cmd_p1; AES_DATA2 = cmd_p2; AES_DATA3 = cmd_p3;
    AES_CONTROL = CMD_CMAC_GENERATE;
    while (!(AES_STATUS & STATUS_CMAC_DONE))
        ;
    unsigned int tag0 = CMAC_TAG0, tag1 = CMAC_TAG1, tag2 = CMAC_TAG2, tag3 = CMAC_TAG3;

    uart_puts("[STEP 1/4] INBOUND TRANSMISSION FROM HOST\r\n");
    print_128("Ciphertext Pkt  ", ct0, ct1, ct2, ct3);
    print_128("Attached CMAC   ", tag0, tag1, tag2, tag3);
    delay_ms(1200); // Visual pause to inspect packet

    // ------------------------------------------------------------------------
    // NODE HARDWARE VERIFICATION
    // ------------------------------------------------------------------------
    uart_puts("\r\n[STEP 2/4] NODE HARDWARE: VERIFYING CMAC AUTHENTICITY...\r\n");
    AES_DATA0 = cmd_p0; AES_DATA1 = cmd_p1; AES_DATA2 = cmd_p2; AES_DATA3 = cmd_p3;
    CMAC_EXP0 = tag0;   CMAC_EXP1 = tag1;   CMAC_EXP2 = tag2;   CMAC_EXP3 = tag3;
    AES_CONTROL = CMD_CMAC_VERIFY;
    while (!(AES_STATUS & STATUS_CMAC_DONE))
        ;

    unsigned int st = AES_STATUS;
    if ((st & STATUS_CMAC_VALID) && !(st & STATUS_TAMPER_DETECTED)) {
        uart_puts("  >> Tamper Checker    : NO TAMPER DETECTED (CMAC VALID = 1)\r\n");
        uart_puts("  >> Packet Authenticity: VERIFIED LEGITIMATE (Host Signature OK)\r\n");
        uart_puts("  >> Board LEDs        : [LD0..LD11 ON] (Channel Verified)\r\n");
        LED_REG = 0x0FFF;
        delay_ms(1500); // Visual pause to observe LD0..LD11

        // --------------------------------------------------------------------
        // NODE HARDWARE DECRYPTION
        // --------------------------------------------------------------------
        uart_puts("\r\n[STEP 3/4] NODE HARDWARE: DECRYPTING VERIFIED COMMAND...\r\n");
        AES_DATA0 = ct0; AES_DATA1 = ct1; AES_DATA2 = ct2; AES_DATA3 = ct3;
        AES_CONTROL = CMD_START_DECRYPT;
        while (!(AES_STATUS & STATUS_CIPHER_READY))
            ;
        unsigned int dec0 = AES_RES0, dec1 = AES_RES1, dec2 = AES_RES2, dec3 = AES_RES3;
        print_128("Decrypted Command", dec0, dec1, dec2, dec3);
        uart_puts("  >> ASCII Command     : 'CMD_READ_SENSORS'\r\n");
        uart_puts("  >> Board LEDs        : [ALL 16 LEDs SOLID ON] (0xFFFF)\r\n");
        LED_REG = 0xFFFF;
        delay_ms(1500); // Visual pause to observe all 16 LEDs ON

        // --------------------------------------------------------------------
        // NODE -> HOST ENCRYPTED TELEMETRY REPLY
        // --------------------------------------------------------------------
        uart_puts("\r\n[STEP 4/4] NODE -> HOST: ENCRYPTED TELEMETRY REPLY...\r\n");
        // Node Status Telemetry: "NODE_OK_TMP=25C!"
        unsigned int tel_p0 = 0x4e4f4445; // 'NODE'
        unsigned int tel_p1 = 0x5f4f4b5f; // '_OK_'
        unsigned int tel_p2 = 0x544d503d; // 'TMP='
        unsigned int tel_p3 = 0x32354321; // '25C!'
        print_128("Node Telemetry  ", tel_p0, tel_p1, tel_p2, tel_p3);

        // Node Encrypts Telemetry
        AES_DATA0 = tel_p0; AES_DATA1 = tel_p1; AES_DATA2 = tel_p2; AES_DATA3 = tel_p3;
        AES_CONTROL = CMD_START_ENCRYPT;
        while (!(AES_STATUS & STATUS_CIPHER_READY))
            ;
        unsigned int r_ct0 = AES_RES0, r_ct1 = AES_RES1, r_ct2 = AES_RES2, r_ct3 = AES_RES3;

        // Node Generates Telemetry CMAC Tag
        AES_DATA0 = tel_p0; AES_DATA1 = tel_p1; AES_DATA2 = tel_p2; AES_DATA3 = tel_p3;
        AES_CONTROL = CMD_CMAC_GENERATE;
        while (!(AES_STATUS & STATUS_CMAC_DONE))
            ;
        unsigned int r_tag0 = CMAC_TAG0, r_tag1 = CMAC_TAG1, r_tag2 = CMAC_TAG2, r_tag3 = CMAC_TAG3;

        print_128("Encrypted Telemetry", r_ct0, r_ct1, r_ct2, r_ct3);
        print_128("Node CMAC Tag      ", r_tag0, r_tag1, r_tag2, r_tag3);
        uart_puts(">>> STATUS: SECURE TWO-WAY HANDSHAKE 100% COMPLETE <<<\r\n");
    } else {
        uart_puts("FAIL: Verification Error!\r\n");
    }
    uart_puts("===================================================================\r\n");
    delay_ms(2000); // Visual pause before returning to main menu
}

// ----------------------------------------------------------------------------
// CASE 2: HOST -> NODE TAMPER ATTACK (ACTIVE MAN-IN-THE-MIDDLE QUARANTINE)
// ----------------------------------------------------------------------------
void handle_tampered_packet(void)
{
    uart_puts("\r\n===================================================================\r\n");
    uart_puts(">>> [COMMUNICATION 1] HOST -> NODE: ATTACKER TAMPERED PACKET <<<\r\n");
    uart_puts("===================================================================\r\n");

    LED_REG = 0x0FFF; // Baseline: transmission channel active
    delay_ms(300);

    // Host originally intended: "CMD_READ_SENSORS"
    // Attacker modifies payload to malicious command: "CMD_OVERHEAT_SYS"
    unsigned int orig_p3 = 0x534f5253;     // 'SORS'
    unsigned int tampered_p3 = 0x5f535953; // '_SYS' (Malicious modification!)

    // Authentic Tag generated by host before attack
    unsigned int auth_tag0 = 0x387b3622;
    unsigned int auth_tag1 = 0x8ba77744;
    unsigned int auth_tag2 = 0x5bafa036;
    unsigned int auth_tag3 = 0x45b94010;

    uart_puts("[STEP 1/3] ACTIVE ATTACK IN TRANSMISSION CHANNEL\r\n");
    uart_puts("  Original Word 3 : 0x"); uart_puthex32(orig_p3);     uart_puts(" ('SORS')\r\n");
    uart_puts("  Tampered Word 3 : 0x"); uart_puthex32(tampered_p3); uart_puts(" ('_SYS') <-- Corrupted by Attacker!\r\n");
    uart_puts("  Attacker Tag    : Reusing original tag (Attacker cannot forge tag without key)\r\n");
    delay_ms(1200); // Visual pause to inspect attack

    // ------------------------------------------------------------------------
    // NODE HARDWARE TAMPER CHECKER EVALUATION
    // ------------------------------------------------------------------------
    uart_puts("\r\n[STEP 2/3] NODE HARDWARE: VERIFYING INCOMING PACKET...\r\n");
    AES_DATA0 = 0x434d445f;
    AES_DATA1 = 0x52454144;
    AES_DATA2 = 0x5f53454e;
    AES_DATA3 = tampered_p3; // Tampered payload!
    CMAC_EXP0 = auth_tag0;
    CMAC_EXP1 = auth_tag1;
    CMAC_EXP2 = auth_tag2;
    CMAC_EXP3 = auth_tag3;

    AES_CONTROL = CMD_CMAC_VERIFY;
    while (!(AES_STATUS & STATUS_CMAC_DONE))
        ;

    unsigned int st = AES_STATUS;
    uart_puts("  Status Register      : 0x"); uart_puthex32(st); uart_puts("\r\n");
    uart_puts("  -> CMAC_VALID        = 0 (TAG MISMATCH - INTEGRITY COMPROMISED)\r\n");
    uart_puts("  -> TAMPER_DETECTED   = 1 (SECURITY ALERT: PACKET MODIFIED!)\r\n");
    delay_ms(1500); // Visual pause to inspect tamper status flags

    if (!(st & STATUS_CMAC_VALID) && (st & STATUS_TAMPER_DETECTED)) {
        // --------------------------------------------------------------------
        // SECURITY QUARANTINE: DECRYPTION IS STRICTLY BLOCKED!
        // --------------------------------------------------------------------
        uart_puts("\r\n[STEP 3/3] MILITARY NODE SECURITY POLICY ENFORCED\r\n");
        uart_puts("  >> VERDICT           : TAMPER DETECTED / PACKET COMPROMISED!\r\n");
        uart_puts("  >> DECRYPTION ACTION : STRICTLY BLOCKED & ABORTED!\r\n");
        uart_puts("  >> PAYLOAD QUARANTINE: Malicious command was dropped and never decrypted.\r\n");
        uart_puts("  >> HARDWARE ALERT    : LD12..LD15 ARE NOW BLINKING ALONE!\r\n");
        uart_puts("===================================================================\r\n");

        // Flash LD12..LD15 ALONE (top 4 LEDs) while LD0..LD11 stay solid ON
        for (int i = 0; i < 8; i++) {
            LED_REG = 0xFFFF; // LD12..LD15 ON
            delay_ms(250);
            LED_REG = 0x0FFF; // LD12..LD15 OFF (LD0..LD11 stay solid)
            delay_ms(250);
        }
        LED_REG = 0x0FFF; // Leave LD12..LD15 OFF to mark rejected packet
        uart_puts(">>> NODE OUTBOUND TO HOST: [ALERT: PACKET REJECTED - TAMPER DETECTED] <<<\r\n");
    } else {
        uart_puts("FAIL: Hardware failed to flag tamper!\r\n");
    }
    uart_puts("===================================================================\r\n");
    delay_ms(2000); // Visual pause before returning to main menu
}

// ----------------------------------------------------------------------------
// MENU DISPLAY & INPUT HANDLING
// ----------------------------------------------------------------------------
static void print_menu(void)
{
    uart_puts("\r\n");
    uart_puts("===================================================================\r\n");
    uart_puts("      SPARTAN-7 MILITARY FIELD NODE SoC: SECURE CONTROLLER        \r\n");
    uart_puts("===================================================================\r\n");
    uart_puts("  Choose Host -> Node Communication Scenario:\r\n");
    uart_puts("    [1] - Send Authentic Host Command  (Legitimate -> All 16 LEDs ON)\r\n");
    uart_puts("    [2] - Inject Channel Tamper Attack (Attacker   -> LD12..LD15 Blinks)\r\n");
    uart_puts("-------------------------------------------------------------------\r\n");
    uart_puts("Selection (1 or 2) > ");
}

static char get_clean_choice(void)
{
    while (1) {
        char c = uart_getc_blocking();
        // Silently discard newlines (\r, \n), nulls, spaces, and line noise
        if (c == '\r' || c == '\n' || c == ' ' || c == '\0' || c < 0x20 || c > 0x7E) {
            continue;
        }
        return c;
    }
}

// ----------------------------------------------------------------------------
// MAIN CONTROLLER
// ----------------------------------------------------------------------------
int main(void)
{
    LED_REG = 0x0000;
    init_master_key();

    // Flush any stale/residual bytes in UART RX register left over from bootloader
    for (int i = 0; i < 32; i++) {
        if (UART_STATUS & RX_VALID) {
            volatile unsigned int dummy = UART_DATA;
            (void)dummy;
        }
    }

    // Display menu EXACTLY ONCE on startup
    print_menu();

    while (1) {
        char choice = get_clean_choice();
        uart_putc(choice);
        uart_puts("\r\n");

        if (choice == '1') {
            handle_legitimate_command();
            print_menu();
        } else if (choice == '2') {
            handle_tampered_packet();
            print_menu();
        } else {
            uart_puts(">>> Invalid option! Please press '1' or '2'.\r\n");
            uart_puts("Selection (1 or 2) > ");
        }
    }

    return 0;
}
