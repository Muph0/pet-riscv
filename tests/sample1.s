# Linear RV32I Decoder Test (No Jumps/Branches)
# Register x1 is used as the primary accumulator/test target

# 1. Upper Immediates (Setting up base addresses/large constants)
lui   x1, 74565          # x1 = 0x12345000
auipc x2, 1              # x2 = PC + 0x1000

# 2. Immediate Arithmetic & Logic
addi  x1, x1, -1         # x1 = x1 + (-1)
slti  x3, x1, 100        # x3 = (x1 < 100) ? 1 : 0
sltiu x4, x1, 100        # x4 = (unsigned x1 < 100) ? 1 : 0
xori  x5, x1, 1023       # Bitwise XOR with immediate
ori   x6, x1, 240        # Bitwise OR with immediate
andi  x7, x1, 15         # Bitwise AND with immediate

# 3. Immediate Shifts
slli  x8, x1, 4          # Logical Shift Left by 4
srli  x9, x1, 4          # Logical Shift Right by 4
srai  x10, x1, 4         # Arithmetic Shift Right by 4 (sign-extend)

# 4. Register-Register Arithmetic
add   x11, x1, x2        # x11 = x1 + x2
sub   x12, x1, x2        # x12 = x1 - x2
sll   x13, x1, x8        # Shift Left (register amount)
slt   x14, x1, x2        # Set Less Than
sltu  x15, x1, x2        # Set Less Than (Unsigned)
xor   x16, x1, x2        # Bitwise XOR
srl   x17, x1, x8        # Logical Shift Right
sra   x18, x1, x8        # Arithmetic Shift Right
or    x19, x1, x2        # Bitwise OR
and   x20, x1, x2        # Bitwise AND

# 5. Memory Operations (Offsetting from x1)
sw    x2, 4(x1)          # Store Word
sh    x2, 8(x1)          # Store Half
sb    x2, 10(x1)         # Store Byte
lw    x21, 4(x1)         # Load Word
lh    x22, 8(x1)         # Load Half (Signed)
lhu   x23, 8(x1)         # Load Half (Unsigned)
lb    x24, 10(x1)        # Load Byte (Signed)
lbu   x25, 10(x1)        # Load Byte (Unsigned)

# 6. Final NOP
addi  x0, x0, 0          # nop