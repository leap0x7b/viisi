const std = @import("std");
const trap = @import("trap.zig");
const Dram = @import("dram.zig");
const Clint = @import("clint.zig");
const Plic = @import("plic.zig");
const Uart = @import("uart.zig").Uart;
const Drive = @import("drive.zig");

pub const DRAM_BASE: u64 = 0x80000000;

pub const Mmio = struct {
    pub const Entry = struct {
        base: u64,
        size: usize,
    };

    Reserved: Entry,
    Fdt: Entry,
    Nvram: Entry,
    Clint: Entry,
    Plic: Entry,
    Uart: Entry,
    Framebuffer: Entry,
    Drive: Entry,
    Keyboard: Entry,
}{
    .Reserved = .{
        .base = 0x0,
        .size = 0xfff,
    },

    .Fdt = .{
        .base = 0x1000,
        .size = 0xf0000,
    },

    .Nvram = .{
        .base = 0x1000000,
        .size = 0xfffff, // 1 MiB
    },

    .Clint = .{
        .base = 0x2000000,
        .size = 0x10000,
    },

    .Plic = .{
        .base = 0xc000000,
        .size = 0x208000,
    },

    .Uart = .{
        .base = 0x10000000,
        .size = 0x100,
    },

    .Framebuffer = .{
        .base = 0x10001000,
        .size = 0xc0000, // 1024x768 (TODO: try to make a framebuffer with a redefinable resolution if possible)
    },

    .Drive = .{
        .base = 0x20000000,
        .size = 0x100,
    },

    .Keyboard = .{
        .base = 0x20001000,
        .size = 1,
    },
};

pub fn Bus(comptime reader: anytype, comptime writer: anytype) type {
    return struct {
        const Self = @This();

        clint: Clint = .{},
        plic: Plic = .{},
        uart: Uart(reader, writer),
        drive: ?Drive,
        dram: Dram,

        pub fn load(self: *Self, comptime T: type, address: u64) trap.Exception!u64 {
            if (Mmio.Clint.base <= address and address < Mmio.Clint.base + Mmio.Clint.size)
                return self.clint.load(T, address);

            if (Mmio.Plic.base <= address and address < Mmio.Plic.base + Mmio.Plic.size)
                return self.plic.load(T, address);

            if (Mmio.Uart.base <= address and address < Mmio.Uart.base + Mmio.Uart.size)
                return self.uart.load(T, address);

            if (self.drive != null) {
                if (Mmio.Drive.base <= address and address < Mmio.Drive.base + Mmio.Drive.size)
                    return self.drive.?.load(T, address);
            }

            if (DRAM_BASE <= address)
                return self.dram.load(T, address);

            return error.LoadAccessFault;
        }

        pub fn store(self: *Self, comptime T: type, address: u64, value: u64) trap.Exception!void {
            if (Mmio.Clint.base <= address and address < Mmio.Clint.base + Mmio.Clint.size)
                return self.clint.store(T, address, value);

            if (Mmio.Plic.base <= address and address < Mmio.Plic.base + Mmio.Plic.size)
                return self.plic.store(T, address, value);

            if (Mmio.Uart.base <= address and address < Mmio.Uart.base + Mmio.Uart.size)
                return self.uart.store(T, address, value);

            if (self.drive != null) {
                if (Mmio.Drive.base <= address and address < Mmio.Drive.base + Mmio.Drive.size)
                    return self.drive.?.store(T, address, value);
            }

            if (DRAM_BASE <= address)
                return self.dram.store(T, address, value);

            return error.StoreAMOAccessFault;
        }

        pub fn accessDrive(self: *Self) trap.Exception!void {
            if (self.drive != null) {
                const direction = try self.load(u64, Drive.DIRECTION);
                const address = try self.load(u64, Drive.BUFFER_ADDRESS);
                const length = try self.load(u64, Drive.BUFFER_LENGTH);
                const sector = try self.load(u64, Drive.SECTOR);

                if (direction == 1) {
                    var i: u64 = 0;
                    while (i < length) : (i += 1) {
                        const data = try self.load(u8, address + i);
                        self.drive.?.write(sector * 512 + i, @truncate(u8, data)) catch |err| {
                            try self.store(u64, Drive.STATUS, @enumToInt(Drive.errorToStatus(err)));
                            break;
                        };
                    }
                } else {
                    var i: u64 = 0;
                    while (i < length) : (i += 1) {
                        const data = self.drive.?.read(sector * 512 + i) catch |err| {
                            try self.store(u64, Drive.STATUS, @enumToInt(Drive.errorToStatus(err)));
                            break;
                        };
                        try self.store(u8, address + i, data);
                    }
                }
                try self.store(u64, Drive.STATUS, @enumToInt(Drive.Status.Success));
            }
        }
    };
}
