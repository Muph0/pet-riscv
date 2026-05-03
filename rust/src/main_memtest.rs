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
    // initialize stack pointer to top of 16K SRAM (SRAM starts at 0x8000, +16K = 0xB000)
    "lui sp, 0xB",
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
        writeln!(*uart, "Found ", Ascii(&info.name));
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

    let mut head = info.start;
    const ECHO_BY: usize = 0x100000;
    let mut echo_marker = head + ECHO_BY;
    let mut step = 16;
    while head <= info.end {
        if head >= echo_marker {
            writeln!(*uart, "Checking 0x", head as *const u8);
            echo_marker += ECHO_BY;
        }

        if check_failed(head) {
            writeln!(*uart, "last=0x", head as *const u8);
            return Err("check failed");
        }

        if head + step > info.end {
            step = (info.end - head) >> 1;
        } else {
            //step += 4;
        }
        head += step.max(4);
    }

    Ok(())
}

fn check_failed(adr: usize) -> bool {
    let ptr = adr as *mut u32;
    const MAGIC: u32 = 0xDEADBEEF;

    unsafe {
        ptr.write_volatile(MAGIC);
        if ptr.read_volatile() != MAGIC {
            return true;
        }
        ptr.write_volatile(!MAGIC);
        if ptr.read_volatile() != !MAGIC {
            return true;
        }
    };

    false
}
