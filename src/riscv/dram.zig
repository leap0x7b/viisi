const std = @import("std");
const Trap = @import("trap.zig");
const Bus = @import("bus.zig");

const Self = @This();

dram: []u8,
size: usize,

pub fn load(self: *Self, comptime T: type, address: u64) Trap.Exception!u64 {
    const index = address - Bus.DRAM_BASE;
    // zig fmt: off
    return switch (T) {
        u8 => @as(u64, self.dram[index]),
        u16 => @as(u64, self.dram[index])
            | (@as(u64, self.dram[index + 1]) << 8),
        u32 => @as(u64, self.dram[index])
            | (@as(u64, self.dram[index + 1]) << 8)
            | (@as(u64, self.dram[index + 2]) << 16)
            | (@as(u64, self.dram[index + 3]) << 24),
        u64 => @as(u64, self.dram[index])
            | (@as(u64, self.dram[index + 1]) << 8)
            | (@as(u64, self.dram[index + 2]) << 16)
            | (@as(u64, self.dram[index + 3]) << 24)
            | (@as(u64, self.dram[index + 4]) << 32)
            | (@as(u64, self.dram[index + 5]) << 40)
            | (@as(u64, self.dram[index + 6]) << 48)
            | (@as(u64, self.dram[index + 7]) << 56),
        else => return error.LoadAddressFault,
    };
    // zig fmt: on
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) Trap.Exception!void {
    const index = address - Bus.DRAM_BASE;
    switch (T) {
        u8 => self.dram[index] = @as(u8, @intCast(value)),
        u16 => {
            self.dram[index] = @as(u8, @intCast(value & 0xff));
            self.dram[index + 1] = @as(u8, @intCast((value >> 8) & 0xff));
        },
        u32 => {
            self.dram[index] = @as(u8, @intCast(value & 0xff));
            self.dram[index + 1] = @as(u8, @intCast((value >> 8) & 0xff));
            self.dram[index + 2] = @as(u8, @intCast((value >> 16) & 0xff));
            self.dram[index + 3] = @as(u8, @intCast((value >> 24) & 0xff));
        },
        u64 => {
            self.dram[index] = @as(u8, @intCast(value & 0xff));
            self.dram[index + 1] = @as(u8, @intCast((value >> 8) & 0xff));
            self.dram[index + 2] = @as(u8, @intCast((value >> 16) & 0xff));
            self.dram[index + 3] = @as(u8, @intCast((value >> 24) & 0xff));
            self.dram[index + 4] = @as(u8, @intCast((value >> 32) & 0xff));
            self.dram[index + 5] = @as(u8, @intCast((value >> 40) & 0xff));
            self.dram[index + 6] = @as(u8, @intCast((value >> 48) & 0xff));
            self.dram[index + 7] = @as(u8, @intCast((value >> 56) & 0xff));
        },
        else => return error.LoadAddressFault,
    }
}
