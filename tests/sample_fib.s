; Compute first 40 Fibonacci numbers and store to data memory

.def a   = reg:x8    ; fib n-2
.def b   = reg:x9    ; fib n-1
.def cnt = reg:x10   ; loop counter
.def ptr = reg:x11   ; memory pointer
.def c   = reg:x12   ; temp (a + b)

li   a, 0               ; a = fib(0) = 0
li   b, 1               ; b = fib(1) = 1
li   cnt, 38            ; counter = 38 (pre-store fib(0) and fib(1))
li   ptr, 0             ; ptr = 0

sw   a, 0(ptr)          ; store fib(0)
addi ptr, ptr, 4        ; ptr += 4
sw   b, 0(ptr)          ; store fib(1)
addi ptr, ptr, 4        ; ptr += 4

loop:
add  c, a, b            ; c = a + b
sw   c, 0(ptr)          ; store c
addi ptr, ptr, 4        ; ptr += 4
addi a, b, 0            ; a = b
addi b, c, 0            ; b = c
addi cnt, cnt, -1       ; counter--
bne  cnt, x0, loop      ; if counter != 0, continue

nop                      ; end