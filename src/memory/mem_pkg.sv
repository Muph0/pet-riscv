package mem_pkg;

    // Memory operation width
    typedef enum logic [1:0] {
        WIDTH_8  = 0,
        WIDTH_16 = 1,
        WIDTH_32 = 2
    } width_t;

    // Memory access modes
    typedef enum logic [1:0] {
        MEM_IDLE = 2'b00,
        MEM_STORE = 2'b01,
        MEM_LOAD_SIG = 2'b10,  // load signed
        MEM_LOAD_USIG = 2'b11  // load unsigned
    } mem_mode_t;

endpackage
