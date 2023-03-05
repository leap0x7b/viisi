const std = @import("std");
const bus = @import("bus.zig");
const trap = @import("trap.zig");

const Self = @This();

pub const IRQ = 11;
pub const TIME = bus.Mmio.Rtc.base;

tick_offset: u64 = 0,
time: u64 = 0,
interrupting: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),

pub fn load(self: *Self, comptime T: type, address: u64) trap.Exception!u64 {
    if (T != u64) return error.LoadAccessFault;
    return switch (address) {
        TIME => self.getCount(),
        else => 0,
    };
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) trap.Exception!void {
    if (T != u64) return error.StoreAMOAccessFault;
    switch (address) {
        TIME => {
            const current_tick = self.getCount();
            const new_tick = value;
            self.tick_offset += new_tick - current_tick;
        },
        else => {},
    }
}

fn getCount(self: *Self) u64 {
    return self.tick_offset + std.time.nanoTimestamp();
}

pub fn isInterrupting(self: *Self) bool {
    return self.interrupting.swap(false, .Acquire);
}
