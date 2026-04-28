; UART echo with XOR 32 (lowercase <-> uppercase toggle)
;
; MMIO layout (base 0x1001_0000):
;   +0x0  DATA    W: TX byte, R: RX byte
;   +0x4  STATUS  R: bit0 = TX busy, bit1 = RX data available
;   +0x8  CONTROL R/W
;   +0xC  BIT_LEN R/W

.def base = reg:x1
.def stat = reg:x2
.def ch   = reg:x3

lui  base, 10010h         ; base = 0x1001_0000

poll_rx:
lw   stat, 4(base)        ; read STATUS
andi stat, stat, 2        ; isolate RX-available (bit 1)
beq  stat, x0, poll_rx   ; spin until RX byte ready

lw   ch, 0(base)          ; read DATA (clears RX-available)
xori ch, ch, 32           ; toggle case (XOR 0x20)

poll_tx:
lw   stat, 4(base)        ; read STATUS
andi stat, stat, 1        ; isolate TX-busy (bit 0)
bne  stat, x0, poll_tx   ; spin until TX idle

sw   ch, 0(base)          ; write DATA (starts TX)
beq  x0, x0, poll_rx     ; loop forever
