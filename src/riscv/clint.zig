const Bus = @import("bus.zig");
const Trap = @import("trap.zig");

const Self = @This();

pub const MTIMECMP = Bus.Mmio.Clint.base + 0x4000;
pub const MTIME = Bus.Mmio.Clint.base + 0xbff8;

mtimecmp: u64 = 0,
mtime: u64 = 0,

pub fn load(self: *Self, comptime T: type, address: u64) Trap.Exception!u64 {
    if (T != u64) return error.LoadAccessFault;
    return switch (address) {
        MTIMECMP => self.mtimecmp,
        MTIME => self.mtime,
        else => 0,
    };
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) Trap.Exception!void {
    if (T != u64) return error.StoreAMOAccessFault;
    switch (address) {
        MTIMECMP => self.mtimecmp = value,
        MTIME => self.mtime = value,
        else => {},
    }
}
