const std = @import("std");
const build_options = @import("build_options");
const clap = @import("clap");
const term = @import("term.zig");
const riscv = @import("riscv.zig");

pub const std_options = struct {
    pub const logFn = log;
};

// From https://github.com/leap0x7b/faruos/blob/rewrite-again/src/lara/arch/x86_64/main.zig
pub fn log(comptime level: std.log.Level, comptime scope: @Type(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_prefix = if (scope == .default) "main" else @tagName(scope);
    const prefix = "\x1b[32m[viisi:" ++ scope_prefix ++ "] " ++ switch (level) {
        .err => "\x1b[31merror",
        .warn => "\x1b[33mwarning",
        .info => "\x1b[36minfo",
        .debug => "\x1b[90mdebug",
    } ++ ": \x1b[0m";
    std.io.getStdOut().writer().print(prefix ++ format ++ "\n", args) catch unreachable;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help           Display this help and exit.
        \\-V, --version        Output version information and exit.
        \\-d, --drive <FILE>   Insert a disk drive.
        \\-k, --kernel <FILE>  Boot with the specified kernel.
    );

    const parsers = comptime .{
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        std.debug.print("viisi: ", .{});
        diag.report(stderr.writer(), err) catch {};
        try usage(&params, stderr.writer());
        return std.debug.print("Try `viisi --help` for more information.\n", .{});
    };
    defer res.deinit();

    if (res.args.help)
        return help(&params, stderr.writer());

    if (res.args.version)
        return stdout.writer().print(
            \\Viisi {s}
            \\Copyright © 2023 leap123.
            \\
            \\Viisi is licensed under the MIT license.
            \\
        , .{build_options.version});

    if (res.args.kernel) |kernel|
        if (res.args.drive) |drive| {
            const file = try std.fs.cwd().openFile(kernel, .{ .mode = .read_only });
            defer file.close();

            var disk = try std.fs.cwd().openFile(drive, .{ .mode = .read_write });
            defer disk.close();

            const buffered_stdin = std.io.bufferedReader(stdin.reader());
            const buffered_stdout = std.io.bufferedWriter(stdout.writer());

            //var raw_mode = try term.enableRawMode(stdin.handle, .Blocking);
            //defer raw_mode.disableRawMode() catch unreachable;

            var cpu = try riscv.cpu.init(buffered_stdin, buffered_stdout);
            try cpu.init(try file.readToEndAlloc(arena.allocator(), 1024 * 1024 * 256), 1024 * 1024 * 256, &disk, arena.allocator());

            //const stat = try file.stat();
            //while (cpu.pc - riscv.bus.DRAM_BASE < stat.size) {
            while (true) {
                const inst = cpu.fetch() catch |exception| blk: {
                    try riscv.trap.handleTrap(exception, &cpu);
                    if (riscv.trap.isFatal(exception)) break;
                    break :blk 0;
                };
                cpu.pc += 4;
                cpu.execute(inst) catch |exception| {
                    try riscv.trap.handleTrap(exception, &cpu);
                    if (riscv.trap.isFatal(exception)) break;
                };

                if (try cpu.checkPendingInterrupt()) |interrupt|
                    try riscv.trap.handleTrap(interrupt, &cpu);

                if (cpu.pc == 0) break;
            }

            cpu.dumpRegisters();
            cpu.dumpCsrs();
        };
}

fn usage(params: []const clap.Param(clap.Help), writer: anytype) !void {
    std.debug.print("Usage: viisi ", .{});
    try clap.usage(writer, clap.Help, params);
    std.debug.print("\n", .{});
}

fn help(params: []const clap.Param(clap.Help), writer: anytype) !void {
    std.debug.print("Viisi {s}\n\n", .{build_options.version});
    try usage(params, writer);
    std.debug.print("\nOptions:\n", .{});
    try clap.help(writer, clap.Help, params, .{
        .indent = 4,
        .description_on_new_line = false,
        .description_indent = 0,
        .spacing_between_parameters = 0,
    });
    return std.debug.print("\nThis project is open source. Feel free to contribute to it at https://github.com/leap0x7b/viisi.\n", .{});
}
