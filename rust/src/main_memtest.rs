#![no_std]
#![no_main]

use core::arch::global_asm;

use crate::{
    mmio::{bus_info, BusInfo, Uart},
    slimfmt::Ascii,
};

mod mmio;
mod slimfmt;

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
    let mut uart = unsafe { Uart::discover() }.unwrap();
    let result = run_test(&mut uart);
    let msg = match result {
        Ok(()) => "DONE",
        Err(s) => s,
    };
    writeln!(uart, "Memtest: ", msg);
    loop {}
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    let mut uart = unsafe { Uart::discover().unwrap_or(Uart::new(0x1001_0000)) };
    writeln!(uart, "\nMemtest panic.");
    loop {}
}

fn run_test(uart: &mut Uart) -> Result<(), &'static str> {
    let mut ddr3_opt: Option<*const BusInfo> = None;
    writeln!(*uart, "Scanning bus...");
    for info_ptr in bus_info() {
        let info = unsafe { *info_ptr };
        writeln!(*uart, "- Found \"", Ascii(&info.name), "\"");
        if info.name == *b"DDR3" {
            ddr3_opt = Some(info_ptr);
        }
    }

    let Some(ddr3) = ddr3_opt else {
        return Err("No DDR3 found.");
    };

    while unsafe { ddr3.read_volatile() }.status & 1 == 0 {}
    writeln!(*uart, "DDR3 ready");

    let info = unsafe { *ddr3 };

    writeln!(*uart, "Pass 1 enc(adr)");
    check_pass(uart, 0, info)?;
    writeln!(*uart, "Pass 2 !enc(adr)");
    check_pass(uart, !0, info)?;

    Ok(())
}

fn check_pass(uart: &mut Uart, magic: u32, info: BusInfo) -> Result<(), &'static str> {
    //const ECHO_BY: usize = 0x1_0000;
    let clz = (info.end - info.start).leading_zeros();
    let echo_by = (!0 >> (clz + 3)) + 1;

    // Write pass: fill entire range with (magic ^ adr)
    let mut adr = info.start;
    let mut echo_marker = adr + echo_by;
    writeln!(*uart, "  Writing...");
    while adr <= info.end {
        if adr >= echo_marker {
            writeln!(*uart, "  0x", adr as *const u8);
            echo_marker += echo_by;
        }
        unsafe { (adr as *mut u32).write_volatile(magic ^ encode(adr as u32)) };
        adr += 4;
    }

    // Read pass: verify entire range
    let mut adr = info.start;
    let mut echo_marker = adr + echo_by;
    let mut errors = 0;
    writeln!(*uart, "  Verifying...");
    while adr <= info.end && errors < 100 {
        if adr >= echo_marker {
            writeln!(*uart, "  0x", adr as *const u8);
            echo_marker += echo_by;
        }
        let expected = magic ^ encode(adr as u32);
        let actual = unsafe { (adr as *mut u32).read_volatile() };
        if actual != expected {
            write!(*uart, "  FAIL at 0x", adr as *const u8);
            writeln!(
                *uart,
                ": expected=",
                expected as *const (),
                ", got=",
                actual as *const (),
                " @",
                decode(magic ^ actual) as *const ()
            );
            errors += 1;
        }
        adr += 4;
    }

    match errors {
        0 => Ok(()),
        _ => Err("check failed"),
    }
}

fn encode(mut x: u32) -> u32 {
    x = ((x >> 16) ^ x).wrapping_mul(0x45d9f3b);
    x = ((x >> 16) ^ x).wrapping_mul(0x45d9f3b);
    x = (x >> 16) ^ x;
    x
}

fn decode(mut x: u32) -> u32 {
    x = (x >> 16) ^ x;
    x = x.wrapping_mul(0x119de1f3);
    x = (x >> 16) ^ x;
    x = x.wrapping_mul(0x119de1f3);
    x = (x >> 16) ^ x;
    x
}
