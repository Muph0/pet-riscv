#![no_std]
#![no_main]

use core::arch::global_asm;
use core::panic::PanicInfo;

use crate::mmio::Uart;

mod mmio;
mod slimfmt;

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    let mut uart = unsafe { Uart::discover().unwrap_or(Uart::new(0x1001_0000)) };

    write!(uart, "Kernel panic");
    if let Some(loc) = info.location() {
        write!(uart, " at ", loc.file(), ":", loc.line());
    }

    //_ = core::fmt::write(&mut uart, format_args!("\n{}\n", info.message()));

    loop {}
}

global_asm!(
    ".section .text._start",
    ".global _start",
    "_start:",
    // initialize stack pointer to top of 16K BRAM (BRAM starts at 0x4000, +16K = 0x8000)
    "lui sp, 0x8",
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
