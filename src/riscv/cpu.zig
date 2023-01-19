const std = @import("std");
const Bus = @import("bus.zig");
const log = std.log.scoped(.Cpu);

const Self = @This();

/// Machine-level CSRs
pub const MachineCsrs = enum(u64) {
    /// Hardware thread ID.
    HwThreadId = 0xf14,
    /// Machine status register.
    Status = 0x300,
    /// Machine exception delefation register.
    ExceptionDelReg = 0x302,
    /// Machine interrupt delefation register.
    InterruptDelReg = 0x303,
    /// Machine interrupt-enable register.
    InterruptEnable = 0x304,
    /// Machine trap-handler base address.
    TrapHandler = 0x305,
    /// Machine counter enable.
    CounterEnable = 0x306,
    /// Scratch register for machine trap handlers.
    Scratch = 0x340,
    /// Machine exception program counter.
    ExceptionPc = 0x341,
    /// Machine trap cause.
    TrapCause = 0x342,
    /// Machine bad address or instruction.
    BadAddress = 0x343,
    /// Machine interrupt pending.
    InterruptPending = 0x344,
};

/// Supervisor-level CSRs.
pub const SupervisorCsrs = enum(u64) {
    /// Supervisor status register.
    Status = 0x100,
    /// Supervisor interrupt-enable register.
    InterruptEnable = 0x104,
    /// Supervisor trap handler base address.
    TrapHandler = 0x105,
    /// Scratch register for supervisor trap handlers.
    Scratch = 0x140,
    /// Supervisor exception program counter.
    ExceptionPc = 0x141,
    /// Supervisor trap cause
    TrapCause = 0x142,
    /// Supervisor bad address or instruction.
    BadAddress = 0x143,
    /// Supervisor interrupt pending.
    InterruptPending = 0x144,
    /// Supervisor address translation and protection.
    AddressTranslation = 0x180,
};

/// The privileged mode.
pub const Mode = enum(u2) {
    User = 0b00,
    Supervisor = 0b01,
    Machine = 0b11,
};

regs: [32]u64 = undefined,
pc: u64 = Bus.DRAM_BASE,
mode: Mode = .Machine,
bus: Bus = undefined,
csrs: [4096]u64 = undefined,

pub fn init(code: []u8, mem_size: usize) Self {
    var ret = Self{
        .bus = .{
            .dram = .{
                .dram = code,
                .size = mem_size,
            },
        },
    };

    // make sure our registers and csrs are 0 and not screaming in hex (12297829382473034410)
    var i: usize = 0;
    while (i < ret.regs.len) : (i += 1)
        ret.regs[i] = 0;

    ret.regs[2] = Bus.DRAM_BASE + mem_size;

    i = 0;
    while (i < ret.csrs.len) : (i += 1)
        ret.csrs[i] = 0;

    return ret;
}

pub fn dumpRegisters(self: *Self) void {
    // zig fmt: off
    const abi = [_][]const u8{
        "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0",
        "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5",
        "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
    };
    // zig fmt: on

    var i: usize = 0;
    while (i < 32) : (i += 4)
        log.debug("x{:0>2}({s})=0x{x} x{:0>2}({s})=0x{x} x{:0>2}({s})=0x{x} x{:0>2}({s})=0x{x}", .{
            i,
            abi[i],
            self.regs[i],
            i + 1,
            abi[i + 1],
            self.regs[i + 1],
            i + 2,
            abi[i + 2],
            self.regs[i + 2],
            i + 3,
            abi[i + 3],
            self.regs[i + 3],
        });
}

pub fn dumpCsrs(self: *Self) void {
    log.debug("mstatus=0x{x} mtvec=0x{x} mepc=0x{x} mcause=0x{x}", .{
        self.loadCsr(@enumToInt(MachineCsrs.Status)),
        self.loadCsr(@enumToInt(MachineCsrs.TrapHandler)),
        self.loadCsr(@enumToInt(MachineCsrs.ExceptionPc)),
        self.loadCsr(@enumToInt(MachineCsrs.TrapCause)),
    });
    log.debug("sstatus=0x{x} stvec=0x{x} sepc=0x{x} scause=0x{x}", .{
        self.loadCsr(@enumToInt(SupervisorCsrs.Status)),
        self.loadCsr(@enumToInt(SupervisorCsrs.TrapHandler)),
        self.loadCsr(@enumToInt(SupervisorCsrs.ExceptionPc)),
        self.loadCsr(@enumToInt(SupervisorCsrs.TrapCause)),
    });
}

pub fn loadCsr(self: *Self, address: u64) u64 {
    return switch (address) {
        @enumToInt(SupervisorCsrs.InterruptEnable) => self.csrs[@enumToInt(MachineCsrs.InterruptEnable)] & self.csrs[@enumToInt(MachineCsrs.InterruptDelReg)],
        else => self.csrs[address],
    };
}

pub fn storeCsr(self: *Self, address: u64, value: u64) void {
    switch (address) {
        @enumToInt(SupervisorCsrs.InterruptEnable) => self.csrs[@enumToInt(MachineCsrs.InterruptEnable)] = (self.csrs[@enumToInt(MachineCsrs.InterruptEnable)] & ~self.csrs[@enumToInt(MachineCsrs.InterruptDelReg)]) | (value & ~self.csrs[@enumToInt(MachineCsrs.InterruptDelReg)]),
        else => self.csrs[address] = value,
    }
}

pub fn fetch(self: *Self) u64 {
    return self.bus.load(u32, self.pc);
}

pub fn execute(self: *Self, inst: u64) !void {
    const opcode = inst & 0x7f;
    const rd = (inst >> 7) & 0x1f;
    const rs1 = (inst >> 15) & 0x1f;
    const rs2 = (inst >> 20) & 0x1f;
    const funct3 = (inst >> 12) & 0x7;
    const funct7 = (inst >> 35) & 0x7f;

    self.regs[0] = 0;

    switch (opcode) {
        // nop
        0x00 => {},
        0x03 => {
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst))) >> 20);
            const addr = self.regs[rs1] + imm;

            self.regs[rd] = switch (funct3) {
                // lb
                0 => blk: {
                    const val = self.bus.load(u8, addr);
                    break :blk @bitCast(u64, @as(i64, @bitCast(i8, @truncate(u8, val))));
                },
                // lh
                1 => blk: {
                    const val = self.bus.load(u16, addr);
                    break :blk @bitCast(u64, @as(i64, @bitCast(i16, @truncate(u16, val))));
                },
                // lw
                2 => blk: {
                    const val = self.bus.load(u32, addr);
                    break :blk @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, val))));
                },
                // ld
                3 => self.bus.load(u64, addr),
                // lbu
                4 => self.bus.load(u8, addr),
                // lhu
                5 => self.bus.load(u16, addr),
                // lwu
                6 => self.bus.load(u32, addr),
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        0x13 => {
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))) >> 20);
            const shamt = @truncate(u32, imm & 0x3f);

            self.regs[rd] = switch (funct3) {
                // addi
                0 => self.regs[rs1] + imm,
                // slli
                1 => self.regs[rs1] << @truncate(u6, shamt),
                // slti
                2 => if (@bitCast(i64, self.regs[rs1]) < @bitCast(i64, imm)) 1 else 0,
                // sltiu
                3 => if (self.regs[rs1] < imm) 1 else 0,
                // xori
                4 => self.regs[rs1] ^ imm,
                5 => switch (funct7 >> 1) {
                    // slri
                    0x00 => self.regs[rs1] >> @truncate(u6, shamt),
                    // srai
                    0x10 => @bitCast(u64, @bitCast(i64, self.regs[rs1]) >> @truncate(u6, shamt)),
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                // ori
                6 => self.regs[rs1] | imm,
                // andi
                7 => self.regs[rs1] & imm,
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        // auipc
        0x17 => {
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))));
            self.regs[rd] = (self.pc + imm) - 4;
        },
        0x1b => {
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst))) >> 20);
            const shamt = @truncate(u32, imm & 0x1f);

            self.regs[rd] = switch (funct3) {
                // addiw
                0 => @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, self.regs[rs1] + imm)))),
                // slliw
                1 => @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, self.regs[rs1] << @truncate(u6, shamt))))),
                5 => switch (funct7) {
                    // slriw
                    0x00 => @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, self.regs[rs1]) >> @intCast(u5, shamt)))),
                    // sraiw
                    0x20 => @bitCast(u64, @as(i64, @truncate(u32, self.regs[rs1]) >> @intCast(u5, shamt))),
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        0x23 => {
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0xfe000000))) >> 20) | ((inst >> 7) & 0x1f);
            const addr = self.regs[rs1] + imm;

            switch (funct3) {
                // sb
                0 => self.bus.store(u8, addr, self.regs[rs2]),
                // sh
                1 => self.bus.store(u16, addr, self.regs[rs2]),
                // sw
                2 => self.bus.store(u32, addr, self.regs[rs2]),
                // sd
                3 => self.bus.store(u64, addr, self.regs[rs2]),
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            }
        },
        // RV64A: "A" standard extension for atomic instructions
        0x2f => {
            const funct5 = (funct7 & 0b1111100) >> 2;
            const acquire = (funct7 & 0b10) >> 1;
            const release = funct7 & 0b1;

            _ = acquire;
            _ = release;

            self.regs[rd] = switch (funct5) {
                0 => switch (funct3) {
                    // amoadd.w
                    2 => blk: {
                        const _rs1 = self.bus.load(u32, self.regs[rs1]);
                        self.bus.store(u32, self.regs[rs1], _rs1 + self.regs[rs2]);
                        break :blk _rs1;
                    },
                    // amoadd.d
                    3 => blk: {
                        const _rs1 = self.bus.load(u64, self.regs[rs1]);
                        self.bus.store(u64, self.regs[rs1], _rs1 + self.regs[rs2]);
                        break :blk _rs1;
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                1 => switch (funct3) {
                    // amoswap.w
                    2 => blk: {
                        const _rs1 = self.bus.load(u32, self.regs[rs1]);
                        self.bus.store(u32, self.regs[rs1], self.regs[rs2]);
                        break :blk _rs1;
                    },
                    // amoadd.d
                    3 => blk: {
                        const _rs1 = self.bus.load(u64, self.regs[rs1]);
                        self.bus.store(u64, self.regs[rs1], self.regs[rs2]);
                        break :blk _rs1;
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                else => {
                    log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        0x33 => {
            const shamt = @truncate(u32, self.regs[rs2] & 0x3f);

            self.regs[rd] = switch (funct3) {
                0 => switch (funct7) {
                    // add
                    0x00 => self.regs[rs1] + self.regs[rs2],
                    // mul
                    0x01 => self.regs[rs1] * self.regs[rs2],
                    // sub
                    0x20 => self.regs[rs1] - self.regs[rs2],
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                // sll
                1 => self.regs[rs1] << @truncate(u6, shamt),
                // slt
                2 => if (@bitCast(i64, self.regs[rs1]) < @bitCast(i64, self.regs[rs2])) 1 else 0,
                // sltu
                3 => if (self.regs[rs1] < self.regs[rs2]) 1 else 0,
                4 => switch (funct7) {
                    // xor
                    0x00 => self.regs[rs1] ^ self.regs[rs2],
                    // div
                    0x01 => switch (self.regs[rs2]) {
                        0 => std.math.maxInt(u64),
                        else => blk: {
                            const dividend = @bitCast(i64, self.regs[rs1]);
                            const divisor = @bitCast(i64, self.regs[rs2]);
                            break :blk @bitCast(u64, @divExact(dividend, divisor));
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                5 => switch (funct7) {
                    // srl
                    0x00 => self.regs[rs1] >> @truncate(u6, shamt),
                    // divu
                    0x01 => switch (self.regs[rs2]) {
                        0 => std.math.maxInt(u64),
                        else => blk: {
                            const dividend = self.regs[rs1];
                            const divisor = self.regs[rs2];
                            break :blk dividend / divisor;
                        },
                    },
                    // sra
                    0x20 => @bitCast(u64, @bitCast(i64, self.regs[rs1]) >> @truncate(u6, self.regs[rs2])),
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                6 => switch (funct7) {
                    // or
                    0x00 => self.regs[rs1] | self.regs[rs2],
                    // rem
                    0x01 => switch (self.regs[rs2]) {
                        0 => self.regs[rs1],
                        else => blk: {
                            const dividend = @bitCast(i64, self.regs[rs1]);
                            const divisor = @bitCast(i64, self.regs[rs2]);
                            break :blk @bitCast(u64, @rem(dividend, divisor));
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                7 => switch (funct7) {
                    // and
                    0x00 => self.regs[rs1] & self.regs[rs2],
                    // remu
                    0x01 => switch (self.regs[rs2]) {
                        0 => self.regs[rs1],
                        else => blk: {
                            const dividend = self.regs[rs1];
                            const divisor = self.regs[rs2];
                            break :blk dividend % divisor;
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        // lui
        0x37 => self.regs[rd] = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0xfffff000)))),
        0x3b => {
            const shamt = @truncate(u32, self.regs[rs2] & 0x1f);

            self.regs[rd] = switch (funct3) {
                0 => switch (funct7) {
                    // addw
                    0x00 => @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, self.regs[rs1] + self.regs[rs2])))),
                    // subw
                    0x20 => @intCast(u64, @bitCast(i32, @truncate(u32, self.regs[rs1] - self.regs[rs2]))),
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                // sllw
                1 => @intCast(u64, @bitCast(i32, @truncate(u32, self.regs[rs1])) << @truncate(u5, shamt)),
                4 => switch (funct7) {
                    // divw
                    0x01 => switch (self.regs[rs2]) {
                        0 => std.math.maxInt(u64),
                        else => blk: {
                            const dividend = @bitCast(i32, @truncate(u32, self.regs[rs1]));
                            const divisor = @bitCast(i32, @truncate(u32, self.regs[rs2]));
                            break :blk @intCast(u64, @divExact(dividend, divisor));
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                5 => switch (funct7) {
                    // srlw
                    0x00 => @intCast(u64, @bitCast(i32, @truncate(u32, self.regs[rs1])) >> @truncate(u5, shamt)),
                    // divuw
                    0x01 => switch (self.regs[rs2]) {
                        0 => std.math.maxInt(u64),
                        else => blk: {
                            const dividend = @truncate(u32, self.regs[rs1]);
                            const divisor = @truncate(u32, self.regs[rs2]);
                            break :blk @intCast(u64, @bitCast(i32, dividend / divisor));
                        },
                    },
                    // sraw
                    0x20 => @intCast(u64, @bitCast(i32, @truncate(u32, self.regs[rs1]) >> @truncate(u5, @bitCast(u32, @bitCast(i32, shamt))))),
                    else => {
                        log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                6 => switch (funct7) {
                    // remw
                    0x01 => switch (self.regs[rs2]) {
                        0 => self.regs[rs1],
                        else => blk: {
                            const dividend = @bitCast(i32, @truncate(u32, self.regs[rs1]));
                            const divisor = @bitCast(i32, @truncate(u32, self.regs[rs2]));
                            break :blk @intCast(u64, @rem(dividend, divisor));
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                7 => switch (funct7) {
                    // remuw
                    0x01 => switch (self.regs[rs2]) {
                        0 => self.regs[rs1],
                        else => blk: {
                            const dividend = @truncate(u32, self.regs[rs1]);
                            const divisor = @truncate(u32, self.regs[rs2]);
                            break :blk @intCast(u64, @bitCast(i32, dividend % divisor));
                        },
                    },
                    else => {
                        log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                        return error.UnimplementedOpcode;
                    },
                },
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        0x63 => {
            // zig fmt: off
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0x80000000))) >> 19)
                | ((inst & 0x80) << 4)
                | ((inst >> 20) & 0x7e0)
                | ((inst >> 7) & 0x1e);
            // zig fmt: on
            self.pc = switch (funct3) {
                // beq
                0 => if (self.regs[rs1] == self.regs[rs2]) (self.pc + imm) - 4 else 0,
                // bne
                1 => if (self.regs[rs1] != self.regs[rs2]) (self.pc + imm) - 4 else 0,
                // blt
                4 => if (@bitCast(i64, self.regs[rs1]) < @bitCast(i64, self.regs[rs2])) (self.pc + imm) - 4 else 0,
                // bge
                5 => if (@bitCast(i64, self.regs[rs1]) >= @bitCast(i64, self.regs[rs2])) (self.pc + imm) - 4 else 0,
                // bltu
                6 => if (self.regs[rs1] < self.regs[rs2]) (self.pc + imm) - 4 else 0,
                // bgeu
                7 => if (self.regs[rs1] >= self.regs[rs2]) (self.pc + imm) - 4 else 0,
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            };
        },
        // jalr
        0x67 => {
            const pc = self.pc;

            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))) >> 20);
            self.pc = (self.regs[rs1] + imm) & ~@intCast(u64, 1);

            self.regs[rd] = pc;
        },
        // jal
        0x6f => {
            self.regs[rd] = self.pc;

            // zig fmt: off
            const imm = @bitCast(u64, @as(i64, @bitCast(i32, @truncate(u32, inst & 0x80000000))) >> 11)
                | (inst & 0xff000)
                | ((inst >> 9) & 0x800)
                | ((inst >> 20) & 0x7fe);
            // zig fmt: on
            self.pc = (self.pc + imm) - 4;
        },
        0x73 => {
            const csr_addr = (inst & 0xfff00000) >> 20;

            switch (funct3) {
                // csrrw
                1 => {
                    const csr = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, self.regs[rs1]);
                    self.regs[rd] = csr;
                },
                // csrrs
                2 => {
                    const csr = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, csr | self.regs[rs1]);
                    self.regs[rd] = csr;
                },
                // csrrc
                3 => {
                    const csr = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, csr & ~self.regs[rs1]);
                    self.regs[rd] = csr;
                },
                // csrrwi
                5 => {
                    self.regs[rd] = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, rs1);
                },
                // csrrsi
                6 => {
                    const csr = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, csr | rs1);
                    self.regs[rd] = csr;
                },
                // csrrci
                7 => {
                    const csr = self.loadCsr(csr_addr);
                    self.storeCsr(csr_addr, csr & ~rs1);
                    self.regs[rd] = csr;
                },
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.UnimplementedOpcode;
                },
            }
        },
        else => {
            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
            return error.UnimplementedOpcode;
        },
    }
}
