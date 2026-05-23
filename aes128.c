/*
 * counter.c  —  AES-128 Hardware Encryption Engine
 * Self-contained: UART + AES register access, no external symbols.
 * Compile:
 *   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
 *     -nostdlib -nostartfiles -Wl,--build-id=none \
 *     start.S counter.c -T linker.ld -o counter.elf
 */

#include <stdint.h>

/*==================================================================
 * UART  (base 0x92000000)  — same as your counter test
 *==================================================================*/
#define UART_BASE    0x92000000
#define UART_RX      (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_TX      (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_STAT    (*(volatile uint32_t*)(UART_BASE + 0x08))

#define UART_TX_FULL  0x08   /* bit 3: TX FIFO full  */
#define UART_RX_VALID 0x01   /* bit 0: RX data valid */

/* Send one character — spin until TX FIFO has room */
static void uart_putchar(char c)
{
    while (UART_STAT & UART_TX_FULL);
    UART_TX = (uint32_t)c;
}

/* Receive one character — spin until RX data arrives */
static char uart_getchar(void)
{
    while (!(UART_STAT & UART_RX_VALID));
    return (char)(UART_RX & 0xFF);
}

/* Print a null-terminated string */
static void print(const char *s)
{
    while (*s) uart_putchar(*s++);
}

/* Print one hex nibble */
static void print_nibble(uint8_t v)
{
    v &= 0xF;
    uart_putchar(v < 10 ? '0' + v : 'A' + v - 10);
}

/* Print 32-bit value as 8 hex digits */
static void print_hex(uint32_t v)
{
    int i;
    for (i = 28; i >= 0; i -= 4)
        print_nibble((v >> i) & 0xF);
}

/*==================================================================
 * AES peripheral  (base 0x95000000)
 * Register map matches counter_defs.v
 *==================================================================*/
#define AES_BASE    0x95000000

/* Encrypt inputs */
#define AES_PT3     (*(volatile uint32_t*)(AES_BASE + 0x00))
#define AES_PT2     (*(volatile uint32_t*)(AES_BASE + 0x04))
#define AES_PT1     (*(volatile uint32_t*)(AES_BASE + 0x08))
#define AES_PT0     (*(volatile uint32_t*)(AES_BASE + 0x0C))

/* Key (shared by encrypt + decrypt) */
#define AES_KEY3    (*(volatile uint32_t*)(AES_BASE + 0x10))
#define AES_KEY2    (*(volatile uint32_t*)(AES_BASE + 0x14))
#define AES_KEY1    (*(volatile uint32_t*)(AES_BASE + 0x18))
#define AES_KEY0    (*(volatile uint32_t*)(AES_BASE + 0x1C))

/* Encrypt outputs */
#define AES_CT3     (*(volatile uint32_t*)(AES_BASE + 0x20))
#define AES_CT2     (*(volatile uint32_t*)(AES_BASE + 0x24))
#define AES_CT1     (*(volatile uint32_t*)(AES_BASE + 0x28))
#define AES_CT0     (*(volatile uint32_t*)(AES_BASE + 0x2C))

/* Encrypt status/ctrl */
#define AES_STATUS  (*(volatile uint32_t*)(AES_BASE + 0x30))
#define AES_CTRL    (*(volatile uint32_t*)(AES_BASE + 0x34))

/* Decrypt ciphertext inputs */
#define DEC_CT3     (*(volatile uint32_t*)(AES_BASE + 0x38))
#define DEC_CT2     (*(volatile uint32_t*)(AES_BASE + 0x3C))
#define DEC_CT1     (*(volatile uint32_t*)(AES_BASE + 0x40))
#define DEC_CT0     (*(volatile uint32_t*)(AES_BASE + 0x44))

/* Decrypt plaintext outputs */
#define DEC_PT3     (*(volatile uint32_t*)(AES_BASE + 0x48))
#define DEC_PT2     (*(volatile uint32_t*)(AES_BASE + 0x4C))
#define DEC_PT1     (*(volatile uint32_t*)(AES_BASE + 0x50))
#define DEC_PT0     (*(volatile uint32_t*)(AES_BASE + 0x54))

/* Decrypt status/ctrl */
#define DEC_STATUS  (*(volatile uint32_t*)(AES_BASE + 0x58))
#define DEC_CTRL    (*(volatile uint32_t*)(AES_BASE + 0x5C))

/* CTRL bit positions */
#define CTRL_START  (1 << 0)
#define CTRL_RESET  (1 << 1)

/* STATUS bit positions */
#define STATUS_DONE (1 << 0)

/*==================================================================
 * Helper: small busy-wait delay
 *==================================================================*/
static void delay(uint32_t n)
{
    volatile uint32_t i;
    for (i = 0; i < n; i++);
}

/*==================================================================
 * Read exactly 16 chars from UART, echo each one back
 *==================================================================*/
static void read_16chars(char *buf)
{
    int i;
    for (i = 0; i < 16; i++) {
        buf[i] = uart_getchar();
        uart_putchar(buf[i]);   /* echo */
    }
    buf[16] = '\0';
}

/*==================================================================
 * Pack 16-byte buffer into four 32-bit big-endian words
 *==================================================================*/
static void pack_words(const char *buf,
                       uint32_t *w3, uint32_t *w2,
                       uint32_t *w1, uint32_t *w0)
{
    *w3 = ((uint32_t)(uint8_t)buf[0]  << 24) |
          ((uint32_t)(uint8_t)buf[1]  << 16) |
          ((uint32_t)(uint8_t)buf[2]  <<  8) |
           (uint32_t)(uint8_t)buf[3];

    *w2 = ((uint32_t)(uint8_t)buf[4]  << 24) |
          ((uint32_t)(uint8_t)buf[5]  << 16) |
          ((uint32_t)(uint8_t)buf[6]  <<  8) |
           (uint32_t)(uint8_t)buf[7];

    *w1 = ((uint32_t)(uint8_t)buf[8]  << 24) |
          ((uint32_t)(uint8_t)buf[9]  << 16) |
          ((uint32_t)(uint8_t)buf[10] <<  8) |
           (uint32_t)(uint8_t)buf[11];

    *w0 = ((uint32_t)(uint8_t)buf[12] << 24) |
          ((uint32_t)(uint8_t)buf[13] << 16) |
          ((uint32_t)(uint8_t)buf[14] <<  8) |
           (uint32_t)(uint8_t)buf[15];
}

/*==================================================================
 * main
 *==================================================================*/
int main(void)
{
    char    pt_buf[17];
    char    key_buf[17];
    uint32_t pt3, pt2, pt1, pt0;
    uint32_t k3,  k2,  k1,  k0;

    delay(100000);   /* let UART settle after boot */

    print("================================\r\n");
    print("  AES-128 Hardware Engine\r\n");
    print("  Base: 0x95000000\r\n");
    print("================================\r\n");

    /*--------------------------------------------------------------
     * Get plaintext (16 chars)
     *------------------------------------------------------------*/
    print("\r\nEnter Plaintext (exactly 16 chars): ");
    read_16chars(pt_buf);
    print("\r\n");

    /*--------------------------------------------------------------
     * Get key (16 chars)
     *------------------------------------------------------------*/
    print("Enter Key       (exactly 16 chars): ");
    read_16chars(key_buf);
    print("\r\n");

    /*--------------------------------------------------------------
     * Pack into 32-bit words
     *------------------------------------------------------------*/
    pack_words(pt_buf,  &pt3, &pt2, &pt1, &pt0);
    pack_words(key_buf, &k3,  &k2,  &k1,  &k0);

    /*--------------------------------------------------------------
     * Echo what we received (hex)
     *------------------------------------------------------------*/
    print("\r\nPlaintext : ");
    print_hex(pt3); print_hex(pt2); print_hex(pt1); print_hex(pt0);
    print("\r\n");

    print("Key       : ");
    print_hex(k3); print_hex(k2); print_hex(k1); print_hex(k0);
    print("\r\n");

    /*--------------------------------------------------------------
     * ENCRYPT
     * 1. Reset peripheral
     * 2. Write plaintext + key
     * 3. Pulse START, poll DONE
     *------------------------------------------------------------*/
    AES_CTRL = CTRL_RESET;          /* clear any previous state   */

    AES_PT3  = pt3;                 /* write plaintext            */
    AES_PT2  = pt2;
    AES_PT1  = pt1;
    AES_PT0  = pt0;

    AES_KEY3 = k3;                  /* write key                  */
    AES_KEY2 = k2;
    AES_KEY1 = k1;
    AES_KEY0 = k0;

    AES_CTRL = CTRL_START;          /* start (self-clears)        */

    while (!(AES_STATUS & STATUS_DONE)); /* poll until done        */

    print("\r\nCiphertext: ");
    print_hex(AES_CT3);
    print_hex(AES_CT2);
    print_hex(AES_CT1);
    print_hex(AES_CT0);
    print("\r\n");

    /*--------------------------------------------------------------
     * DECRYPT
     * Feed ciphertext output straight into decrypt inputs.
     * Key is already loaded in hardware (shared registers).
     *------------------------------------------------------------*/
    DEC_CTRL = CTRL_RESET;          /* clear decrypt side         */

    DEC_CT3  = AES_CT3;             /* pass ciphertext across     */
    DEC_CT2  = AES_CT2;
    DEC_CT1  = AES_CT1;
    DEC_CT0  = AES_CT0;

    DEC_CTRL = CTRL_START;

    while (!(DEC_STATUS & STATUS_DONE));

    print("Decrypted : ");
    print_hex(DEC_PT3);
    print_hex(DEC_PT2);
    print_hex(DEC_PT1);
    print_hex(DEC_PT0);
    print("\r\n");

    /*--------------------------------------------------------------
     * Also show decrypted result as ASCII
     *------------------------------------------------------------*/
    uint32_t words[4];
    words[0] = DEC_PT3;
    words[1] = DEC_PT2;
    words[2] = DEC_PT1;
    words[3] = DEC_PT0;

    print("Decrypted ASCII: ");
    int w, b;
    for (w = 0; w < 4; w++) {
        for (b = 24; b >= 0; b -= 8) {
            char c = (char)((words[w] >> b) & 0xFF);
            uart_putchar((c >= 0x20 && c < 0x7F) ? c : '.');
        }
    }
    print("\r\n");

    print("================================\r\n");
    print("  Done.\r\n");
    print("================================\r\n");

    while (1);   /* halt */
    return 0;
}