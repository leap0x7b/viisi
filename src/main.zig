const std = @import("std");
const build_options = @import("build_options");
const clap = @import("clap");
const riscv = @import("riscv.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help     Display this help and exit.
        \\-V, --version  Output version information and exit.
        \\<FILE>...
        \\
    );

    const parsers = comptime .{
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        std.debug.print("viisi: ", .{});
        diag.report(stderr, err) catch {};
        std.debug.print("\n", .{});
        try usage(&params, stderr);
        return std.debug.print("Try `viisi --help` for more information.\n", .{});
    };
    defer res.deinit();

    if (res.args.help)
        return help(&params, stderr);

    if (res.args.version)
        return stdout.print(
            \\Viisi {s}
            \\Copyright © 2023 leap123.
            \\
            \\Viisi is licensed under the MIT license.
            \\
        , .{build_options.version});

    if (res.positionals.len != 0) {
        const file = try std.fs.cwd().openFile(res.positionals[0], .{ .mode = .read_only });
        defer file.close();

        const buffered_stdin = std.io.bufferedReader(stdin);
        const buffered_stdout = std.io.bufferedWriter(stdout);

        var cpu = try riscv.Cpu.init(buffered_stdin, buffered_stdout);
        try cpu.init(try file.readToEndAlloc(arena.allocator(), 1024 * 1024 * 256), 1024 * 1024 * 256, arena.allocator());

        const stat = try file.stat();
        while (cpu.pc - riscv.Bus.DRAM_BASE < stat.size) {
            const inst = cpu.fetch() catch |exception| blk: {
                riscv.Trap.handleTrap(exception, &cpu);
                if (riscv.Trap.isFatal(exception)) break;
                break :blk 0;
            };
            cpu.pc += 4;
            cpu.execute(inst) catch |exception| {
                riscv.Trap.handleTrap(exception, &cpu);
                if (riscv.Trap.isFatal(exception)) break;
            };
            if (cpu.pc == 0) break;
        }

        cpu.dumpRegisters();
        std.debug.print("\n", .{});
        cpu.dumpCsrs();
    }
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
