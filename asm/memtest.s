; wait for DDR3 init
waitForDdr3:
    lui t0, 10000h         ; t0 = 0x10000000
    lw  t1, 44(t0)         ; 44 = 0x2C. BUSI DDR3 Status
    andi t1, t1, 1
    beq t1, zero, label:waitForDdr3

    ; Print I, N, I, T, \n
    addi a0, zero, 73      ; I
    jal ra, label:putc
    addi a0, zero, 78      ; N
    jal ra, label:putc
    addi a0, zero, 73      ; I
    jal ra, label:putc
    addi a0, zero, 84      ; T
    jal ra, label:putc
    addi a0, zero, 10      ; \n
    jal ra, label:putc

    ; Measure memory size by write-read check
    lui t0, 80000h         ; 0x80000000
    lui t1, 88000h         ; 0x88000000 max end
    lui t2, 100h           ; 0x00100000 1MB step

check_loop:
    beq t0, t1, label:check_done
    sw t0, 0(t0)
    lw t3, 0(t0)
    bne t3, t0, label:check_done

    addi a0, zero, 77      ; M
    jal ra, label:putc

    add t0, t0, t2
    beq zero, zero, label:check_loop

check_done:
    addi a0, zero, 10      ; \n
    jal ra, label:putc

    ; Compare measured (t0) with businfo
    lui t4, 10000h
    lw  t5, 40(t4)         ; 40 = 0x28. BUSI DDR3 End Address
    addi t5, t5, 1         ; max end (exclusive)

    beq t0, t5, label:mem_size_ok
    addi a0, zero, 69      ; E
    jal ra, label:putc
    beq zero, zero, label:end_size_check
mem_size_ok:
    addi a0, zero, 79      ; O
    jal ra, label:putc
    addi a0, zero, 75      ; K
    jal ra, label:putc
end_size_check:
    addi a0, zero, 10      ; \n
    jal ra, label:putc

    ; Write 1KB at the start of each MB
    addi t5, t0, 0         ; Save measured end to t5
    lui t0, 80000h         ; start
    lui t6, 100h           ; 1MB step

test_mb_loop:
    beq t0, t5, label:all_done

    addi t1, t0, 0
    addi t2, zero, 256     ; 1KB
write_1kb:
    sw t1, 0(t1)
    addi t1, t1, 4
    addi t2, t2, -1
    bne t2, zero, label:write_1kb

    addi t1, t0, 0
    addi t2, zero, 256
read_1kb:
    lw t3, 0(t1)
    bne t3, t1, label:test_fail
    addi t1, t1, 4
    addi t2, t2, -1
    bne t2, zero, label:read_1kb

    addi a0, zero, 46      ; .
    jal ra, label:putc

    add t0, t0, t6
    beq zero, zero, label:test_mb_loop

test_fail:
    addi a0, zero, 70      ; F
    jal ra, label:putc
    addi a0, zero, 65      ; A
    jal ra, label:putc
    addi a0, zero, 73      ; I
    jal ra, label:putc
    addi a0, zero, 76      ; L
    jal ra, label:putc
    addi a0, zero, 10      ; \n
    jal ra, label:putc
    beq zero, zero, label:end_loop

all_done:
    addi a0, zero, 68      ; D
    jal ra, label:putc
    addi a0, zero, 79      ; O
    jal ra, label:putc
    addi a0, zero, 78      ; N
    jal ra, label:putc
    addi a0, zero, 69      ; E
    jal ra, label:putc
    addi a0, zero, 10      ; \n
    jal ra, label:putc

end_loop:
    beq zero, zero, label:end_loop

putc:
    lui t6, 10010h         ; 0x10010000
    addi t6, t6, 0 
WaitTx:
    lw t4, 4(t6)
    andi t4, t4, 1
    bne t4, zero, label:WaitTx

    sw a0, 0(t6)
    jalr zero, 0(ra)
