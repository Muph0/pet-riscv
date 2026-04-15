; Load-use hazard test
; Store a value, load it back, use immediately
li   x8, 42
sw   x8, 0(x0)
lw   x9, 0(x0)
addi x10, x9, 1
nop
