const std = @import("std");
const Trap = @import("trap.zig");
const Dram = @import("dram.zig");
const Clint = @import("clint.zig");
const Plic = @import("plic.zig");
const Uart = @import("uart.zig").Uart;

pub const DRAM_BASE: u64 = 0x1000_0000;

pub const Mmio = struct {
    pub const Entry = struct {
        base: u64,
        size: usize,
    };

    Reserved: Entry,
    BootRom: Entry,
    Clint: Entry,
    Plic: Entry,
    Uart: Entry,
    Framebuffer: Entry,
    Disk: Entry,
    Keyboard: Entry,
}{
    .Reserved = .{
        .base = 0x0,
        .size = 0xfff,
    },

    .BootRom = .{
        .base = 0x1000,
        .size = 0x80000, // 512 KB
    },

    .Clint = .{
        .base = 0x80010,
        .size = 0x10000,
    },

    .Plic = .{
        .base = 0x90010,
        .size = 0x208000,
    },

    .Uart = .{
        .base = 0x300000,
        .size = 0x100,
    },

    .Framebuffer = .{
        .base = 0x300200,
        .size = 0xc0000, // 1024x768 (TODO: try to make a framebuffer with a redefinable resolution if possible)
    },

    .Disk = .{
        .base = 0x3c0400,
        .size = 0x100,
    },

    .Keyboard = .{
        .base = 0x3c0600,
        .size = 1,
    },
};

pub fn Bus(comptime reader: anytype, comptime writer: anytype) type {
    return struct {
        const Self = @This();

        clint: Clint = .{},
        plic: Plic = .{},
        uart: Uart(reader, writer),
        dram: Dram,

        pub fn load(self: *Self, comptime T: type, address: u64) Trap.Exception!u64 {
            if (Mmio.Clint.base <= address and address < Mmio.Clint.base + Mmio.Clint.size)
                return self.clint.load(T, address);

            if (Mmio.Plic.base <= address and address < Mmio.Plic.base + Mmio.Plic.size)
                return self.plic.load(T, address);

            if (Mmio.Uart.base <= address and address < Mmio.Uart.base + Mmio.Uart.size)
                return self.uart.load(T, address);

            if (DRAM_BASE <= address)
                return self.dram.load(T, address);

            return error.LoadAccessFault;
        }

        pub fn store(self: *Self, comptime T: type, address: u64, value: u64) Trap.Exception!void {
            if (Mmio.Clint.base <= address and address < Mmio.Clint.base + Mmio.Clint.size)
                return self.clint.store(T, address, value);

            if (Mmio.Plic.base <= address and address < Mmio.Plic.base + Mmio.Plic.size)
                return self.plic.store(T, address, value);

            if (Mmio.Uart.base <= address and address < Mmio.Uart.base + Mmio.Uart.size)
                return self.uart.store(T, address, value);

            if (DRAM_BASE <= address)
                return self.dram.store(T, address, value);

            return error.StoreAMOAccessFault;
        }
    };
}
