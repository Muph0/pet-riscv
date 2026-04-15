; Load-use hazard test
; Store a value, load it back, use immediately
addi x8, x0, 42
sw   x8, 0(x0)
lw   x9, 0(x0)
addi x10, x9, 1
addi x0, x0, 0
