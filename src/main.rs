mod uart;
mod framebuffer;

use std::env;
use std::fs::File;
use std::io;
use std::io::prelude::*;
use std::rc::Rc;
use unicorn_engine::{Unicorn, RegisterRISCV};
use unicorn_engine::unicorn_const::{Arch, Mode, Permission};
use minifb::{Key, Window, WindowOptions};

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        panic!("Usage: viisi -b <filename>");
    }
    let mut file = File::open(&args[1])?;
    let mut binary = Vec::new();
    file.read_to_end(&mut binary)?;
    let binary_slice: &[u8] = binary.as_slice();

    let uart = Rc::new(std::cell::RefCell::new(uart::Uart::new()));
    let uart_read_callback = {
        let uart = Rc::clone(&uart);
        move |_: &mut Unicorn<'_, ()>, address, _: usize| uart.borrow_mut().load(address + 0x10000000) as u64
    };
    let uart_write_callback = {
        let uart = Rc::clone(&uart);
        move |_: &mut Unicorn<'_, ()>, address, _: usize, value| uart.borrow_mut().store(address + 0x10000000, value as u8)
    };

    let framebuffer = Rc::new(std::cell::RefCell::new(framebuffer::Framebuffer::new(800, 600)));
    let framebuffer_read_callback = {
        let framebuffer = Rc::clone(&framebuffer);
        move |_: &mut Unicorn<'_, ()>, address, _: usize| framebuffer.borrow_mut().load(address + 0x10001000) as u64
    };
    let framebuffer_write_callback = {
        let framebuffer = Rc::clone(&framebuffer);
        move |_: &mut Unicorn<'_, ()>, address, _: usize, value| framebuffer.borrow_mut().store(address + 0x10001000, value as u8)
    };

    let mut window = Window::new(
        "Viisi",
        800,
        600,
        WindowOptions::default(),
    ).unwrap_or_else(|e| panic!("{}", e));

    let mut unicorn = Unicorn::new(Arch::RISCV, Mode::RISCV64).expect("failed to initialize Unicorn instance");
    let emu = &mut unicorn;
    emu.reg_write(RegisterRISCV::SP, 0x80000000 + (128 * (1024 * 1024))).expect("failed to set sp");
    emu.mmio_map(0x10000000, 0x1000, Some(uart_read_callback), Some(uart_write_callback)).expect("failed to map uart");
    emu.mmio_map(0x10001000, (640 * 480) * 8 /* FIXME: fuck you unicorn for forcing me to use sizes that are multiplied to 4KB */, Some(framebuffer_read_callback), Some(framebuffer_write_callback)).expect("failed to map framebuffer");
    emu.mem_map(0x80000000, 128 * (1024 * 1024), Permission::ALL).expect("failed to map code page");
    emu.mem_write(0x80000000, binary_slice).expect("failed to write instructions");

    let _ = emu.emu_start(0x80000000, (0x80000000 + binary.len()) as u64, 0, 0).expect("failed to start emulator");

    while window.is_open() && !window.is_key_down(Key::Escape) {
        let framebuffer = Rc::clone(&framebuffer);
        let framebuffer = &framebuffer.borrow_mut().framebuffer;
        let mut buffer: Vec<u32> = Vec::new();
        for chunk in framebuffer.chunks_exact(4) {
            let mut result = 0;
            for (i, &byte) in chunk.iter().enumerate() {
                result |= (byte as u32) << (8 * i);
            }
            buffer.push(result);
        }
    
        window.update_with_buffer(&buffer, 800, 600).unwrap();
    }

    Ok(())
}