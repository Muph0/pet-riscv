#![no_std]
#![no_main]

use core::arch::global_asm;
use core::fmt::Write;
use core::panic::PanicInfo;

use crate::mmio::Uart;

mod mmio;

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    let mut uart = unsafe { Uart::discover().unwrap_or(Uart::new(0x1001_0000)) };

    _ = write!(uart, "Kernel panic");
    _ = match info.location() {
        None => writeln!(uart, ""),
        Some(loc) => writeln!(uart, " at {loc}"),
    };

    _ = write!(uart, "Message: {}", info.message());
    loop {}
}

global_asm!(
    ".section .text._start",
    ".global _start",
    "_start:",
    // initialize stack pointer to top of 8K SRAM (SRAM starts at 0x8000, +8K = 0xA000)
    "lui sp, 0xA",
    // jump to rust main function
    "j rust_main",
);

#[no_mangle]
pub extern "C" fn rust_main() -> ! {
    let mut uart = unsafe { Uart::discover() }.expect("No UART found.");

    writeln!(uart, "Hello from RISC-V Rust! Type something:");

    loop {
        let mut c = b' ';
        while !uart.try_getc(&mut c) {}

        if c.is_ascii_alphabetic() {
            c ^= 32;
        }

        while !uart.try_putc(c) {}
    }
}
