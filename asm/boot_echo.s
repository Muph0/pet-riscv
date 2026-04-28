; boot_echo - Print a welcome message, then echo
;
; UART MMIO layout @ 0x1001_0000:
;   +0x0  DATA    W: TX byte, R: RX byte
;   +0x4  STATUS  R: bit0 = TX busy, bit1 = RX data available
;   +0x8  CONTROL R/W (bit0 = TX en, bit1 = RX en)
;   +0xC  BIT_LEN R/W (clock ticks per bit)

.def ptr  = reg:x1
.def base = reg:x3
.def stat = reg:x4
.def ch   = reg:x5

lui  base, 10010h         ; base = 0x1001_0000
la   ptr, label:MSG

; ---- Print welcome message ----
print_loop:
    lbu  ch, 0(ptr)         ; ch = *ptr
    beq  ch, x0, echo_loop  ; NUL terminator -> done printing
    addi ptr, ptr, 1        ; ptr++

tx_wait1:
    lw   stat, 4(base)    ; read STATUS
    andi stat, stat, 1    ; bit0 = TX busy
    bne  stat, x0, tx_wait1

    sw   ch, 0(base)      ; write DATA -> start TX
    beq  x0, x0, print_loop

echo_loop:
    rx_wait:
        lw   stat, 4(base)    ; read STATUS
        andi stat, stat, 2    ; bit1 = RX data available
        beq  stat, x0, rx_wait

    lw   ch, 0(base)      ; read DATA (clears RX flag)
    xori ch, ch, 20h      ; flip case (XOR 0x20: a<->A, b<->B, etc.)

    tx_wait2:
        lw   stat, 4(base)    ; read STATUS
        andi stat, stat, 1    ; bit0 = TX busy
        bne  stat, x0, tx_wait2

    sw   ch, 0(base)        ; write DATA -> start TX
    beq  x0, x0, echo_loop  ; loop forever

MSG: .db "Hello from RISC-V! Type something:", 13, 10, 0

nop
nop
