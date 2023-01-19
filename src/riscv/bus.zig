const Dram = @import("dram.zig");

const Self = @This();

pub const DRAM_BASE: u64 = 0x2000_0000;

dram: Dram,

pub const Mmio = struct {
    pub const Entry = struct {
        base: u64,
        size: usize,
    };

    pub const Entries = struct {
        Reserved: Entry,
        BootRom: Entry,
        Serial1: Entry,
        Framebuffer: Entry,
    }{
        .Reserved = .{
            .base = 0x0,
            .size = 0xfff,
        },

        .BootRom = .{
            .base = 0x1000,
            .size = 0x80000, // 512 KB
        },

        // FIXME: use a refined UART structure instead of a single byte IO
        .Serial1 = .{
            .base = 0x80010,
            .size = 1,
        },

        .Serial2 = .{
            .base = 0x80011,
            .size = 1,
        },

        .Serial3 = .{
            .base = 0x80012,
            .size = 1,
        },

        .Serial4 = .{
            .base = 0x80013,
            .size = 1,
        },

        .Framebuffer = .{
            .base = 0x80020,
            .size = 0xc0000, // 1024x768 (TODO: try to use a framebuffer with a redefinable resolution if possible)
        },
    };
};

pub fn load(self: *Self, comptime T: type, address: u64) u64 {
    if (DRAM_BASE <= address)
        return try self.dram.load(T, address);
    return 0;
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) void {
    if (DRAM_BASE <= address)
        try self.dram.store(T, address, value);
}
