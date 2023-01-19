const std = @import("std");
const Bus = @import("bus.zig");

const Self = @This();

dram: []u8,
size: usize,

pub fn load(self: *Self, comptime T: type, address: u64) !u64 {
    const index = address - Bus.DRAM_BASE;
    // zig fmt: off
    return switch (T) {
        u8 => @intCast(u64, self.dram[index]),
        u16 => @intCast(u64, self.dram[index])
            | (@intCast(u64, self.dram[index + 1]) << 8),
        u32 => @intCast(u64, self.dram[index])
            | (@intCast(u64, self.dram[index + 1]) << 8)
            | (@intCast(u64, self.dram[index + 2]) << 16)
            | (@intCast(u64, self.dram[index + 3]) << 24),
        u64 => @intCast(u64, self.dram[index])
            | (@intCast(u64, self.dram[index + 1]) << 8)
            | (@intCast(u64, self.dram[index + 2]) << 16)
            | (@intCast(u64, self.dram[index + 3]) << 24)
            | (@intCast(u64, self.dram[index + 4]) << 32)
            | (@intCast(u64, self.dram[index + 5]) << 40)
            | (@intCast(u64, self.dram[index + 6]) << 48)
            | (@intCast(u64, self.dram[index + 7]) << 56),
        else => return error.UnsupportedType,
    };
    // zig fmt: on
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) !void {
    const index = address - Bus.DRAM_BASE;
    // zig fmt: off
    switch (T) {
        u8 => self.dram[index] = @intCast(u8, value),
        u16 => {
            self.dram[index] = @intCast(u8, value & 0xff);
            self.dram[index + 1] = @intCast(u8, (value >> 8) & 0xff);
        },
        u32 => {
            self.dram[index] = @intCast(u8, value & 0xff);
            self.dram[index + 1] = @intCast(u8, (value >> 8) & 0xff);
            self.dram[index + 2] = @intCast(u8, (value >> 16) & 0xff);
            self.dram[index + 3] = @intCast(u8, (value >> 24) & 0xff);
        },
        u64 => {
            self.dram[index] = @intCast(u8, value & 0xff);
            self.dram[index + 1] = @intCast(u8, (value >> 8) & 0xff);
            self.dram[index + 2] = @intCast(u8, (value >> 16) & 0xff);
            self.dram[index + 3] = @intCast(u8, (value >> 24) & 0xff);
            self.dram[index + 4] = @intCast(u8, (value >> 32) & 0xff);
            self.dram[index + 5] = @intCast(u8, (value >> 40) & 0xff);
            self.dram[index + 6] = @intCast(u8, (value >> 48) & 0xff);
            self.dram[index + 7] = @intCast(u8, (value >> 56) & 0xff);
        },
        else => return error.UnsupportedType,
    }
    // zig fmt: on
}
