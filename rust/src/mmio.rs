const BUSINFO_BASE: *const BusInfo = 0x1000_0000 as *const _;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct BusInfo {
    name: [u8; 4],
    start: usize,
    end: usize,
    status: u32,
}

const _: () = assert!(size_of::<usize>() == 4);

pub fn bus_info() -> impl Iterator<Item = BusInfo> {
    // SAFETY: bus info must be available on the system
    let first = unsafe { BUSINFO_BASE.read() };
    assert!(first.name == *b"Info");

    let count = (first.end - first.start + 1) / size_of::<BusInfo>();
    (0..count).map(|i| unsafe { BUSINFO_BASE.offset(i as isize).read() })
}

#[repr(C)]
pub struct Uart {
    address: *mut u32,
}
impl Uart {
    // SAFETY: make sure that noone else is using the same uart
    pub unsafe fn new(address: usize) -> Self {
        Self {
            address: address as _,
        }
    }

    // SAFETY: make sure that noone else is using the same uart
    pub unsafe fn discover() -> Option<Self> {
        for info in bus_info() {
            if info.name == *b"UART" {
                return Some(Self::new(info.start));
            }
        }
        None
    }

    pub fn tx_busy(&self) -> bool {
        unsafe { (self.address.offset(1).read_volatile() & 1) != 0 }
    }
    pub fn rx_available(&self) -> bool {
        unsafe { (self.address.offset(1).read_volatile() & 2) != 0 }
    }
    pub fn try_putc(&self, c: u8) -> bool {
        if !self.tx_busy() {
            unsafe { (self.address as *mut u8).write_volatile(c) };
            true
        } else {
            false
        }
    }
    pub fn try_getc(&self, c: &mut u8) -> bool {
        if self.rx_available() {
            unsafe { (self.address as *mut u8).read_volatile(c) };
            true
        } else {
            false
        }
    }
}

impl core::fmt::Write for Uart {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for c in s.bytes() {
            while !self.try_putc(c) {}
        }
        Ok(())
    }
}
