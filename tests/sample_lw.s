; Load-use hazard test
; Store a value, load it back, use immediately
li   x8, 42
lui  x1, 8h
sw   x8, 0(x1)
lw   x9, 0(x1)
addi x10, x9, 1
nop
