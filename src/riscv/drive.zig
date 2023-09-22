// Just a slightly modifed version of VulpineSystem's drive device.
// Would actually be more interesting if it uses SCSI though, but
// it's too hard for me to implement.

const std = @import("std");
const bus = @import("bus.zig");
const trap = @import("trap.zig");

const Self = @This();

pub const IRQ: u64 = 1;

pub const MAGIC = bus.Mmio.Drive.base;
pub const NOTIFY = bus.Mmio.Drive.base + 0x08;
pub const DIRECTION = bus.Mmio.Drive.base + 0x10;
pub const BUFFER_ADDRESS = bus.Mmio.Drive.base + 0x18;
pub const BUFFER_LENGTH = bus.Mmio.Drive.base + 0x20;
pub const SECTOR = bus.Mmio.Drive.base + 0x28;
pub const STATUS = bus.Mmio.Drive.base + 0x30;

pub const Status = enum(u64) {
    Success,
    Unseekable,
    NoSpaceLeft,
    ReadError,
    WriteError,
    SeekError,
    Unknown,
};

pub fn errorToStatus(err: anyerror) Status {
    return switch (@TypeOf(err)) {
        std.os.ReadError => .ReadError,
        std.os.WriteError => switch (err) {
            error.NoSpaceLeft => .NoSpaceLeft,
            else => .WriteError,
        },
        std.os.SeekError => switch (err) {
            error.Unseekable => .Unseekable,
            else => .SeekError,
        },
        else => .Unknown,
    };
}

notify: u64 = @as(u64, @bitCast(@as(i64, -1))),
direction: u64 = 0,
buffer_address: u64 = 0,
buffer_length: u64 = 0,
sector: u64 = 0,
status: Status = .Success,
disk: *std.fs.File,

pub fn load(self: *Self, comptime T: type, address: u64) trap.Exception!u64 {
    if (T != u64) return error.LoadAccessFault;
    return switch (address) {
        MAGIC => 0x7669697369,
        NOTIFY => self.notify,
        DIRECTION => self.direction,
        BUFFER_ADDRESS => self.buffer_address,
        BUFFER_LENGTH => self.buffer_length,
        SECTOR => self.sector,
        STATUS => @intFromEnum(self.status),
        else => 0,
    };
}

pub fn store(self: *Self, comptime T: type, address: u64, value: u64) trap.Exception!void {
    if (T != u64) return error.StoreAMOAccessFault;
    switch (address) {
        NOTIFY => self.notify = value,
        DIRECTION => self.direction = value,
        BUFFER_ADDRESS => self.buffer_address = value,
        BUFFER_LENGTH => self.buffer_length = value,
        SECTOR => self.sector = value,
        STATUS => self.status = @as(Status, @enumFromInt(value)),
        else => {},
    }
}

pub fn isInterrupting(self: *Self) bool {
    if (self.notify != @as(u64, @bitCast(@as(i64, -1)))) {
        self.notify = @as(u64, @bitCast(@as(i64, -1)));
        return true;
    }
    return false;
}

pub fn read(self: *Self, offset: u64) !u8 {
    var buffer: [1]u8 = undefined;
    try self.disk.seekTo(offset);
    _ = try self.disk.read(&buffer);
    return buffer[0];
}

pub fn write(self: *Self, offset: u64, value: u8) !void {
    var buffer: [1]u8 = .{value};
    try self.disk.seekTo(offset);
    _ = try self.disk.write(&buffer);
}
