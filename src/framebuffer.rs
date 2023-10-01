/// The address which the framebuffer starts.
pub const FRAMEBUFFER_BASE: u64 = 0x10001000;

/// The dynamic random access framebuffer (FRAMEBUFFER).
#[derive(Debug)]
pub struct Framebuffer {
    pub framebuffer: Vec<u8>,
    pub width: usize,
    pub height: usize,
    pub pitch: usize,
}

impl Framebuffer {
    /// Create a new `Framebuffer` object with default framebuffer size.
    pub fn new(width: usize, height: usize) -> Framebuffer {
        let framebuffer = vec![0; width * height * 4 as usize];
        Self {
            framebuffer,
            width,
            height,
            pitch: width * 4,
        }
    }

    /// Load a byte from theframebuffer.
    pub fn load(&self, addr: u64) -> u8 {
        let index = (addr - FRAMEBUFFER_BASE) as usize;
        self.framebuffer[index]
    }

    /// Store a byte to the framebuffer.
    pub fn store(&mut self, addr: u64, value: u8) {
        let index = (addr - FRAMEBUFFER_BASE) as usize;
        self.framebuffer[index] = value
    }
}