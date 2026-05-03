/// Minimal write trait for ROM-efficient output
pub trait Write {
    fn write_bytes(&mut self, bytes: &[u8]);

    fn write_str(&mut self, s: &str) {
        self.write_bytes(s.as_bytes());
    }
}

pub struct Ascii<'a>(pub &'a [u8]);

/// Convert u32 to decimal string and write
pub fn write_u32<W: Write>(w: &mut W, mut n: u32) {
    if n == 0 {
        w.write_str("0");
        return;
    }

    let mut buf = [0u8; 10];
    let mut pos = 10;

    while n > 0 {
        pos -= 1;
        buf[pos] = b'0' + (n % 10) as u8;
        n /= 10;
    }

    w.write_bytes(&buf[pos..]);
}

/// Convert i32 to decimal string and write (with sign)
pub fn write_i32<W: Write>(w: &mut W, n: i32) {
    if n < 0 {
        w.write_str("-");
        write_u32(w, (-n) as u32);
    } else {
        write_u32(w, n as u32);
    }
}

/// Convert u8 to hex string and write
pub fn write_hex_u8<W: Write>(w: &mut W, n: u8) {
    const HEX: &[u8] = b"0123456789abcdef";
    let buf = [HEX[(n >> 4) as usize], HEX[(n & 0xf) as usize]];
    w.write_bytes(&buf);
}

/// Convert pointer to hex string and write
pub fn write_ptr<W: Write>(w: &mut W, p: *const ()) {
    let adr = p as usize;
    for i in 1..=size_of::<usize>() {
        let shamt = 8 * (size_of::<usize>() - i);
        write_hex_u8(w, (adr >> shamt) as u8);
    }
}

pub trait Display {
    fn display<W: Write>(&self, w: &mut W);
}

impl Display for &str {
    fn display<W: Write>(&self, w: &mut W) {
        w.write_str(self);
    }
}

impl Display for u32 {
    fn display<W: Write>(&self, w: &mut W) {
        write_u32(w, *self);
    }
}

impl Display for i32 {
    fn display<W: Write>(&self, w: &mut W) {
        write_i32(w, *self);
    }
}

impl Display for u8 {
    fn display<W: Write>(&self, w: &mut W) {
        write_hex_u8(w, *self);
    }
}

impl<T> Display for *const T {
    fn display<W: Write>(&self, w: &mut W) {
        write_ptr(w, *self as *const ());
    }
}

impl<T> Display for *mut T {
    fn display<W: Write>(&self, w: &mut W) {
        write_ptr(w, *self as *const ());
    }
}

impl<'a> Display for Ascii<'a> {
    fn display<W: Write>(&self, w: &mut W) {
        w.write_bytes(self.0);
    }
}

/// Minimal print! macro
#[macro_export]
macro_rules! write {
    ($w:expr, $($arg:expr),*) => {{
        $(
            $crate::slimfmt::Display::display(&$arg, &mut $w);
        )*
    }};
}

/// Minimal println! macro
#[macro_export]
macro_rules! writeln {
    ($w:expr) => {{
        $crate::slimfmt::Write::write_str(&mut $w, "\n");
    }};
    ($w:expr, $($arg:expr),*) => {{
        $(
            $crate::slimfmt::Display::display(&$arg, &mut $w);
        )*
        $crate::slimfmt::Write::write_str(&mut $w, "\n");
    }};
}

impl crate::slimfmt::Write for crate::mmio::Uart {
    fn write_bytes(&mut self, s: &[u8]) {
        for c in s {
            while !self.try_putc(*c) {}
        }
    }
}
