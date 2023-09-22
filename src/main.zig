const std = @import("std");
const build_options = @import("build_options");
const clap = @import("clap");
const term = @import("term.zig");
const riscv = @import("riscv.zig");
const sdl2 = @import("sdl2");

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
        \\-h, --help           Display this help message and exit.
        \\-V, --version        Output version information and exit.
        \\-d, --drive <FILE>   Insert and boot from a disk drive.
        \\-b, --bios <FILE>    Boot from the specified BIOS ROM.
        \\-H, --headless       Boot without a display output.
    );

    const parsers = comptime .{
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        std.debug.print("viisi: ", .{});
        diag.report(stderr.writer(), err) catch {};
        std.debug.print("\n", .{});
        try usage(&params, stderr.writer());
        return std.debug.print("Try `viisi --help` for more information.\n", .{});
    };
    defer res.deinit();

    if (res.args.help != 0)
        return help(&params, stderr.writer());

    if (res.args.version != 0)
        return stdout.writer().print(
            \\Viisi {s}
            \\Copyright © 2023 leap123.
            \\
            \\Viisi is licensed under the MIT license.
            \\
        , .{build_options.version});

    if (res.args.bios) |bios| {
        const file = try std.fs.cwd().openFile(bios, .{ .mode = .read_only });
        defer file.close();

        var disk: ?*std.fs.File = null;
        if (res.args.drive) |drive| {
            var _disk = try std.fs.cwd().openFile(drive, .{ .mode = .read_write });
            defer _disk.close();
            disk = &_disk;
        }

        const buffered_stdin = std.io.bufferedReader(stdin.reader());
        const buffered_stdout = std.io.bufferedWriter(stdout.writer());

        //var raw_mode = try term.enableRawMode(stdin.handle, .Blocking);
        //defer raw_mode.disableRawMode() catch unreachable;

        var window: ?sdl2.Window = null;
        var renderer: ?sdl2.Renderer = null;

        if (res.args.headless == 0) {
            try sdl2.init(.{
                .video = true,
                .events = true,
                .audio = true,
            });
            defer sdl2.quit();

            window = try sdl2.createWindow(
                "Viisi",
                .{ .centered = {} },
                .{ .centered = {} },
                640,
                480,
                .{ .vis = .shown },
            );
            defer window.?.destroy();

            renderer = try sdl2.createRenderer(window.?, null, .{ .accelerated = true });
            defer renderer.?.destroy();
        }

        var cpu = try riscv.cpu.init(buffered_stdin, buffered_stdout);
        try cpu.init(try file.readToEndAlloc(arena.allocator(), 1024 * 1024 * 256), 1024 * 1024 * 256, disk, arena.allocator());

        cpu_loop: while (true) {
            const inst = cpu.fetch() catch |exception| blk: {
                try riscv.trap.handleTrap(exception, &cpu);
                if (riscv.trap.isFatal(exception)) break;
                break :blk 0;
            };
            cpu.pc += 4;
            cpu.execute(inst) catch |exception| {
                try riscv.trap.handleTrap(exception, &cpu);
                if (riscv.trap.isFatal(exception)) break :cpu_loop;
            };

            if (try cpu.checkPendingInterrupt()) |interrupt|
                try riscv.trap.handleTrap(interrupt, &cpu);

            if (cpu.pc == 0) break :cpu_loop;
        }

        if (res.args.headless == 0) {
            fb_loop: while (true) {
                while (sdl2.pollEvent()) |ev| {
                    switch (ev) {
                        .quit => break :fb_loop,
                        else => {},
                    }
                }

                try renderer.?.setColorRGB(0xF7, 0xA4, 0x1D);
                try renderer.?.clear();

                renderer.?.present();
            }
        }

        //cpu.dumpRegisters();
        //cpu.dumpCsrs();
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
