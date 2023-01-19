const std = @import("std");
const build_options = @import("build_options");
const clap = @import("clap");
const riscv = @import("riscv.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

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

        var cpu = riscv.Cpu.init(try file.readToEndAlloc(arena.allocator(), 1024 * 1024 * 256), 1024 * 1024 * 256);

        const stat = try file.stat();
        while (cpu.pc - riscv.Bus.DRAM_BASE < stat.size) {
            const inst = cpu.fetch();
            cpu.pc += 4;
            try cpu.execute(inst);
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
