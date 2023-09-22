// From https://github.com/xyaman/mibu/blob/main/src/term.zig

const std = @import("std");

/// ReadMode defines the read behaivour when using raw mode
pub const ReadMode = enum {
    blocking,
    nonblocking,
};

pub fn enableRawMode(handle: std.os.system.fd_t, blocking: ReadMode) !RawMode {
    var original_termios = try std.os.tcgetattr(handle);
    var termios = original_termios;

    // https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    // All of this are bitflags, so we do NOT and then AND to disable

    // ICRNL (iflag) : fix CTRL-M (carriage returns)
    // IXON (iflag)  : disable Ctrl-S and Ctrl-Q

    // OPOST (oflag) : turn off all output processing

    // ECHO (lflag)  : disable prints every key to terminal
    // ICANON (lflag): disable to reads byte per byte instead of line (or when user press enter)
    // IEXTEN (lflag): disable Ctrl-V
    // ISIG (lflag)  : disable Ctrl-C and Ctrl-Z

    // Miscellaneous flags (most modern terminal already have them disabled)
    // BRKINT, INPCK, ISTRIP and CS8

    termios.iflag &= ~(std.os.system.BRKINT | std.os.system.ICRNL | std.os.system.INPCK | std.os.system.ISTRIP | std.os.system.IXON);
    termios.oflag &= ~(std.os.system.OPOST);
    termios.cflag |= (std.os.system.CS8);
    termios.lflag &= ~(std.os.system.ECHO | std.os.system.ICANON | std.os.system.IEXTEN | std.os.system.ISIG);

    switch (blocking) {
        // Wait until it reads at least one byte
        .blocking => termios.cc[std.os.system.V.MIN] = 1,

        // Don't wait
        .nonblocking => termios.cc[std.os.system.V.MIN] = 0,
    }

    // Wait 100 miliseconds at maximum.
    termios.cc[std.os.system.V.TIME] = 1;

    // apply changes
    try std.os.tcsetattr(handle, .FLUSH, termios);

    return RawMode{
        .orig_termios = original_termios,
        .handle = handle,
    };
}

/// A raw terminal representation, you can enter terminal raw mode
/// using this struct. Raw mode is essential to create a TUI.
pub const RawMode = struct {
    orig_termios: std.os.termios,

    /// The OS-specific file descriptor or file handle.
    handle: std.os.system.fd_t,

    const Self = @This();

    /// Returns to the previous terminal state
    pub fn disableRawMode(self: *Self) !void {
        try std.os.tcsetattr(self.handle, .FLUSH, self.orig_termios);
    }
};
