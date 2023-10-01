const std = @import("std");
const Cpu = @import("../cpu.zig");
const bus = @import("../bus.zig");
const trap = @import("../trap.zig");

fn emuTest(_code: []const u8, expected_regs: []const []const u64, expected_pc: u64) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = [_]u8{0} ** 1024;
    var stream = std.io.fixedBufferStream(&buffer);

    var reader = std.io.bufferedReader(stream.reader());
    var writer = std.io.bufferedWriter(stream.writer());

    var code: [1024]u8 = undefined;
    std.mem.copy(u8, &code, _code);

    var cpu = try Cpu.init(reader, writer);
    try cpu.init(&code, 1024 * 1024 * 256, null, arena.allocator());

    while (cpu.pc - bus.DRAM_BASE < code.len) {
        const inst = cpu.fetch() catch |exception| blk: {
            try trap.handleTrap(exception, &cpu);
            if (trap.isFatal(exception)) break;
            break :blk 0;
        };
        cpu.pc += 4;
        cpu.execute(inst) catch |exception| {
            try trap.handleTrap(exception, &cpu);
            if (trap.isFatal(exception)) break;
        };

        if (try cpu.checkPendingInterrupt()) |interrupt|
            try trap.handleTrap(interrupt, &cpu);

        if (cpu.pc == 0) break;
    }

    for (expected_regs) |expected|
        try std.testing.expectEqual(cpu.regs[expected[0]], expected[1]);

    if (expected_pc != 0)
        try std.testing.expectEqual(cpu.pc, expected_pc);
}

test "addi" {
    try emuTest(&.{
        0x93, 0x0f, 0x40, 0x00, // addi x31, x0, 4
    }, &.{
        &.{ 31, 4 },
    }, 0);
}

test "slli" {
    try emuTest(&.{
        0x13, 0x08, 0x20, 0x00, // addi x16 x0, 2
        0x93, 0x18, 0x38, 0x00, // slli x17, x16, 3
    }, &.{
        &.{ 16, 2 },
        &.{ 17, 16 },
    }, 0);
}

test "slti" {
    try emuTest(&.{
        0x13, 0x08, 0xb0, 0xff, // addi x16 x0, -5
        0x93, 0x28, 0xe8, 0xff, // slti x17, x16, -2
    }, &.{
        &.{ 16, @as(u64, @bitCast(@as(i64, -5))) },
        &.{ 17, 1 },
    }, 0);
}

test "sltiu" {
    try emuTest(&.{
        0x13, 0x08, 0x20, 0x00, // addi x16, x0, 2
        0x93, 0x38, 0x58, 0x00, // sltiu x17, x16, 5
    }, &.{
        &.{ 16, 2 },
        &.{ 17, 1 },
    }, 0);
}

test "xori" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x48, 0x68, 0x00, // xori x17, x16, 6
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 5 },
    }, 0);
}

test "srai" {
    try emuTest(&.{
        0x13, 0x08, 0x80, 0xff, // addi x16, x0, -8
        0x93, 0x58, 0x28, 0x40, // srai x17, x16, 2
    }, &.{
        &.{ 16, @as(u64, @bitCast(@as(i64, -8))) },
        &.{ 17, @as(u64, @bitCast(@as(i64, -2))) },
    }, 0);
}

test "srli" {
    try emuTest(&.{
        0x13, 0x08, 0x80, 0x00, // addi x16, x0, 8
        0x93, 0x58, 0x28, 0x00, // srli x17, x16, 2
    }, &.{
        &.{ 16, 8 },
        &.{ 17, 2 },
    }, 0);
}

test "ori" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x68, 0x68, 0x00, // ori x17, x16, 6
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 7 },
    }, 0);
}

test "andi" {
    try emuTest(&.{
        0x13, 0x08, 0x40, 0x00, // addi x16, x0, 4
        0x93, 0x78, 0x78, 0x00, // andi, x17, x16, 7
    }, &.{
        &.{ 16, 4 },
        &.{ 17, 4 },
    }, 0);
}

test "auipc" {
    try emuTest(&.{
        0x17, 0x28, 0x00, 0x00, // auipc x16, 2
    }, &.{
        &.{ 16, 0x2000 + bus.DRAM_BASE },
    }, 0);
}

test "add" {
    try emuTest(&.{
        0x93, 0x01, 0x50, 0x00, // addi x3, x0, 5
        0x13, 0x02, 0x60, 0x00, // addi x4, x0, 6
        0x33, 0x81, 0x41, 0x00, // add x2, x3, x4
    }, &.{
        &.{ 2, 11 },
        &.{ 3, 5 },
        &.{ 4, 6 },
    }, 0);
}

test "sub" {
    try emuTest(&.{
        0x93, 0x01, 0x50, 0x00, // addi x3, x0, 5
        0x13, 0x02, 0x60, 0x00, // addi x4, x0, 6
        0x33, 0x81, 0x41, 0x40, // sub x2, x3, x4
    }, &.{
        &.{ 2, @as(u64, @bitCast(@as(i64, -1))) },
        &.{ 3, 5 },
        &.{ 4, 6 },
    }, 0);
}

test "sll" {
    try emuTest(&.{
        0x13, 0x08, 0x80, 0x00, // addi x16, x0, 8
        0x93, 0x08, 0x20, 0x00, // addi x17, x0, 2
        0x33, 0x19, 0x18, 0x01, // sll x18, x16, x17
    }, &.{
        &.{ 16, 8 },
        &.{ 17, 2 },
        &.{ 18, 32 },
    }, 0);
}

test "slt" {
    try emuTest(&.{
        0x13, 0x08, 0x80, 0xff, // addi x16, x0, -8
        0x93, 0x08, 0x20, 0x00, // addi x17, x0, 2
        0x33, 0x29, 0x18, 0x01, // slt x18, x16, x17
    }, &.{
        &.{ 16, @as(u64, @bitCast(@as(i64, -8))) },
        &.{ 17, 2 },
        &.{ 18, 1 },
    }, 0);
}

test "sltu" {
    try emuTest(&.{
        0x13, 0x08, 0x80, 0x00, // addi x16, x0, 8
        0x93, 0x08, 0x20, 0x00, // addi x17, x0, 2
        0x33, 0xb9, 0x08, 0x01, // sltu x18, x17, x16
    }, &.{
        &.{ 16, 8 },
        &.{ 17, 2 },
        &.{ 18, 1 },
    }, 0);
}

test "xor" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x08, 0x60, 0x00, // addi x17, x0, 6
        0x33, 0x49, 0x18, 0x01, // xor x18, x16, x17
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 6 },
        &.{ 18, 5 },
    }, 0);
}

test "srl" {
    try emuTest(&.{
        0x13, 0x08, 0x00, 0x01, // addi x16, x0, 16
        0x93, 0x08, 0x20, 0x00, // addi x17, x0, 2
        0x33, 0x59, 0x18, 0x01, // srl x18, x16, x17
    }, &.{
        &.{ 16, 16 },
        &.{ 17, 2 },
        &.{ 18, 4 },
    }, 0);
}

test "sra" {
    try emuTest(&.{
        0x13, 0x08, 0x00, 0xff, // addi x16, x0, -16
        0x93, 0x08, 0x20, 0x00, // addi x17, x0, 2
        0x33, 0x59, 0x18, 0x41, // sra x18, x16, x17
    }, &.{
        &.{ 16, @as(u64, @bitCast(@as(i64, -16))) },
        &.{ 17, 2 },
        &.{ 18, @as(u64, @bitCast(@as(i64, -4))) },
    }, 0);
}

test "or" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x08, 0x50, 0x00, // addi x17, x0, 5
        0x33, 0x69, 0x18, 0x01, // or x18, x16, x17
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 5 },
        &.{ 18, 7 },
    }, 0);
}

test "and" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x08, 0x50, 0x00, // addi x17, x0, 5
        0x33, 0x79, 0x18, 0x01, // and x18, x16, x17
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 5 },
        &.{ 18, 1 },
    }, 0);
}

test "lui" {
    try emuTest(&.{
        0x37, 0x28, 0x00, 0x00, // lui x16, 2
    }, &.{
        &.{ 16, 8192 },
    }, 0);
}

test "beq" {
    try emuTest(&.{
        0x13, 0x08, 0x30, 0x00, // addi x16, x0, 3
        0x93, 0x08, 0x30, 0x00, // addi x17, x0, 3
        0x63, 0x06, 0x18, 0x01, // beq x16, x17, 12
    }, &.{
        &.{ 16, 3 },
        &.{ 17, 3 },
    }, bus.DRAM_BASE - 20);
}
