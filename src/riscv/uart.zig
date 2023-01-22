const std = @import("std");
const Bus = @import("bus.zig");
const Trap = @import("trap.zig");

/// Recieve holding register (for input bytes).
pub const RHR = Bus.Mmio.Uart.base;
/// Transmit holding register (for output bytes).
pub const THR = Bus.Mmio.Uart.base;
/// Line control register.
pub const LCR = Bus.Mmio.Uart.base + 3;
/// Line status register.
pub const LSR = Bus.Mmio.Uart.base + 5;

/// The reciever (RX) bit.
pub const LSR_RX: u8 = 1;
/// The transmitter (TX) bit.
pub const LSR_TX: u8 = 1 << 5;

pub fn Uart(comptime reader_type: anytype, comptime writer_type: anytype) type {
    return struct {
        const Self = @This();

        uart: [Bus.Mmio.Uart.size]u8 = undefined,
        interrupting: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),

        reader: reader_type,
        writer: writer_type,

        thread: std.Thread = undefined,
        mutex: std.Thread.Mutex = .{},
        cond: std.Thread.Condition = .{},

        pub fn init(reader: anytype, writer: anytype) !Self {
            var ret = Self{
                .reader = reader,
                .writer = writer,
            };
            ret.uart[LSR - Bus.Mmio.Uart.base] |= LSR_TX;

            ret.thread = try std.Thread.spawn(.{}, threadFn, .{&ret});

            return ret;
        }

        fn threadFn(self: *Self) void {
            const byte = self.reader.readByte() catch unreachable;

            self.mutex.lock();
            defer self.mutex.unlock();

            while ((self.uart[LSR - Bus.Mmio.Uart.base] & LSR_RX) == 1)
                self.cond.wait(&self.mutex);

            self.uart[0] = byte;
            self.interrupting.store(true, .Release);

            self.uart[LSR - Bus.Mmio.Uart.base] |= LSR_RX;
        }

        pub fn load(self: *Self, comptime T: type, address: u64) Trap.Exception!u64 {
            if (T != u8) return error.LoadAccessFault;

            self.mutex.lock();
            defer self.mutex.unlock();

            return switch (address) {
                RHR => blk: {
                    self.cond.broadcast();
                    self.uart[LSR - Bus.Mmio.Uart.base] &= ~LSR_RX;
                    break :blk @intCast(u64, self.uart[RHR - Bus.Mmio.Uart.base]);
                },
                else => 0,
            };
        }

        pub fn store(self: *Self, comptime T: type, address: u64, value: u64) Trap.Exception!void {
            if (T != u8) return error.StoreAMOAccessFault;

            switch (address) {
                THR => self.writer.print("{c}", .{@truncate(u8, value)}) catch return error.StoreAMOAccessFault,
                else => self.uart[(address - Bus.Mmio.Uart.base)] = @truncate(u8, value),
            }
        }

        pub fn isInterrupting(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            const interrupting = self.interrupting;
            self.interrupting = false;

            return interrupting;
        }
    };
}
