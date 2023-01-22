const Bus = @import("bus.zig");
const Trap = @import("trap.zig");

const Self = @This();

pub const PENDING = Bus.Mmio.Plic.base + 0x1000;
pub const SENABLE = Bus.Mmio.Plic.base + 0x2080;
pub const SPRIORITY = Bus.Mmio.Plic.base + 0x201000;
pub const SCLAIM = Bus.Mmio.Plic.base + 0x201004;

pending: u64 = 0,
senable: u64 = 0,
spriority: u64 = 0,
sclaim: u64 = 0,

pub fn load(self: *Self, comptime T: type, address: u64) Trap.Exception!u64 {
    if (T != u32) return error.LoadAccessFault;
    return switch (address) {
        PENDING => self.pending,
        SENABLE => self.senable,
        SPRIORITY => self.spriority,
        SCLAIM => self.sclaim,
        else => 0,
    };
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) Trap.Exception!void {
    if (T != u32) return error.StoreAMOAccessFault;
    switch (address) {
        PENDING => self.pending = value,
        SENABLE => self.senable = value,
        SPRIORITY => self.spriority = value,
        SCLAIM => self.sclaim = value,
        else => {},
    }
}
