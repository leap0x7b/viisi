const std = @import("std");
const trap = @import("trap.zig");
const bus = @import("bus.zig");
const uart = @import("uart.zig");
const Drive = @import("uart.zig");
const Plic = @import("plic.zig");
const log = std.log.scoped(.cpu);

/// The page size (4 KiB) for the virtual dram system.
const PAGE_SIZE: u64 = 0x1000;

// Machine-level CSRs
/// Hardware thread ID.
pub const MHARTID = 0xf14;
/// Machine status register.
pub const MSTATUS = 0x300;
/// Machine exception delefation register.
pub const MEDELEG = 0x302;
/// Machine interrupt delefation register.
pub const MIDELEG = 0x303;
/// Machine interrupt-enable register.
pub const MIE = 0x304;
/// Machine trap-handler base address.
pub const MTVEC = 0x305;
/// Machine counter enable.
pub const MCOUNTEREN = 0x306;
/// Scratch register for machine trap handlers.
pub const MSCRATCH = 0x340;
/// Machine exception program counter.
pub const MEPC = 0x341;
/// Machine trap cause.
pub const MCAUSE = 0x342;
/// Machine bad address or instruction.
pub const MTVAL = 0x343;
/// Machine interrupt pending.
pub const MIP = 0x344;

/// MIP fields.
pub const Mip = enum(u64) {
    SSIP = 1 << 1,
    MSIP = 1 << 3,
    STIP = 1 << 5,
    MTIP = 1 << 7,
    SEIP = 1 << 9,
    MEIP = 1 << 11,
};

// Supervisor-level CSRs.
/// Supervisor status register.
pub const SSTATUS = 0x100;
/// Supervisor interrupt-enable register.
pub const SIE = 0x104;
/// Supervisor trap handler base address.
pub const STVEC = 0x105;
/// Scratch register for supervisor trap handlers.
pub const SSCRATCH = 0x140;
/// Supervisor exception program counter.
pub const SEPC = 0x141;
/// Supervisor trap cause
pub const SCAUSE = 0x142;
/// Supervisor bad address or instruction.
pub const STVAL = 0x143;
/// Supervisor interrupt pending.
pub const SIP = 0x144;
/// Supervisor address translation and protection.
pub const SATP = 0x180;

/// The privileged mode.
pub const Mode = enum(u2) {
    User = 0b00,
    Supervisor = 0b01,
    Machine = 0b11,
};

/// Access type that is used in the virtual address translation process. It decides which exception
/// should raises (InstructionPageFault, LoadPageFault or StoreAMOPageFault).
pub const AccessType = enum {
    /// Raises the exception InstructionPageFault. It is used for an instruction fetch.
    Instruction,
    /// Raises the exception LoadPageFault.
    Load,
    /// Raises the exception StoreAMOPageFault.
    Store,
};

pub fn init(reader: anytype, writer: anytype) !Cpu(@TypeOf(reader), @TypeOf(writer)) {
    return .{
        .bus = .{
            .uart = try uart.Uart(@TypeOf(reader), @TypeOf(writer)).init(reader, writer),
            .dram = undefined,
            .drive = null,
        },
    };
}

pub fn Cpu(comptime reader: anytype, comptime writer: anytype) type {
    return struct {
        const Self = @This();

        regs: [32]u64 = [_]u64{0} ** 32,
        pc: u64 = bus.DRAM_BASE,
        mode: Mode = .Machine,
        bus: bus.Bus(reader, writer) = undefined,
        csrs: [4096]u64 = [_]u64{0} ** 4096,
        idle: bool = false,
        enable_paging: bool = false,
        page_table: u64 = 0,

        pub fn init(self: *Self, code: []u8, comptime mem_size: usize, disk: ?*std.fs.File, allocator: std.mem.Allocator) !void {
            var dram = try allocator.alloc(u8, mem_size);
            std.mem.copy(u8, dram, code);
            self.bus.dram = .{
                .dram = dram,
                .size = mem_size,
            };

            if (disk) |d|
                self.bus.drive = .{ .disk = d };

            self.regs[2] = bus.DRAM_BASE + mem_size;
        }

        pub fn dumpRegisters(self: *Self) void {
            // zig fmt: off
            const abi = [_][]const u8{
                "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0",
                "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5",
                "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
            };
            // zig fmt: on

            log.debug("Registers:", .{});
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
            log.debug("CSRs:", .{});
            log.debug("mstatus=0x{x} mtvec=0x{x} mepc=0x{x} mcause=0x{x}", .{
                self.loadCsr(MSTATUS),
                self.loadCsr(MTVEC),
                self.loadCsr(MEPC),
                self.loadCsr(MCAUSE),
            });
            log.debug("sstatus=0x{x} stvec=0x{x} sepc=0x{x} scause=0x{x}", .{
                self.loadCsr(SSTATUS),
                self.loadCsr(STVEC),
                self.loadCsr(SEPC),
                self.loadCsr(SCAUSE),
            });
        }

        pub fn checkPendingInterrupt(self: *Self) !?trap.Interrupt {
            switch (self.mode) {
                .Machine => if ((self.loadCsr(MSTATUS) >> 3) & 1 == 0) {
                    return null;
                },
                .Supervisor => if ((self.loadCsr(SSTATUS) >> 3) & 1 == 0) {
                    return null;
                },
                else => {},
            }

            var irq: u64 = 0;
            if (self.bus.uart.isInterrupting()) {
                irq = uart.IRQ;
            }

            if (self.bus.drive != null) {
                if (self.bus.drive.?.isInterrupting()) {
                    try self.bus.accessDrive();
                    irq = Drive.IRQ;
                }
            }

            if (irq != 0) {
                try self.store(u32, Plic.SCLAIM, irq);
                self.storeCsr(MIP, self.loadCsr(MIP) | @intFromEnum(Mip.SEIP));
            }

            const pending = self.loadCsr(MIE) & self.loadCsr(MIP);

            if ((pending & @intFromEnum(Mip.MEIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.MEIP));
                return .MachineExternal;
            }
            if ((pending & @intFromEnum(Mip.MSIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.MSIP));
                return .MachineSoftware;
            }
            if ((pending & @intFromEnum(Mip.MTIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.MTIP));
                return .MachineTimer;
            }
            if ((pending & @intFromEnum(Mip.SEIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.SEIP));
                return .SupervisorExternal;
            }
            if ((pending & @intFromEnum(Mip.SSIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.SSIP));
                return .SupervisorSoftware;
            }
            if ((pending & @intFromEnum(Mip.STIP)) != 0) {
                self.storeCsr(MIP, self.loadCsr(MIP) & ~@intFromEnum(Mip.STIP));
                return .SupervisorTimer;
            }

            return null;
        }

        pub fn updatePaging(self: *Self, csr_address: u64) void {
            if (csr_address != SATP) return;

            self.page_table = (self.loadCsr(SATP) & ((1 << 44) - 1)) * PAGE_SIZE;
            const mode = self.loadCsr(SATP) >> 60;

            if (mode == 8)
                self.enable_paging = true
            else
                self.enable_paging = false;
        }

        pub fn translate(self: *Self, address: u64, access_type: AccessType) trap.Exception!u64 {
            if (!self.enable_paging) return address;

            const levels = 3;
            const vpn: [3]u64 = .{
                (address >> 12) & 0x1ff,
                (address >> 21) & 0x1ff,
                (address >> 30) & 0x1ff,
            };

            var a = self.page_table;
            var i: u64 = levels - 1;
            var pte: u64 = 0;
            while (true) {
                pte = try self.load(u64, a + vpn[i] * 8);

                const v = pte & 1;
                const r = (pte >> 1) & 1;
                const w = (pte >> 2) & 1;
                const x = (pte >> 3) & 1;
                if ((v == 0) or (r == 0 and w == 1))
                    return switch (access_type) {
                        .Instruction => error.InstructionPageFault,
                        .Load => error.LoadPageFault,
                        .Store => error.StoreAMOPageFault,
                    };

                if ((r == 1) or (x == 1)) break;
                i -= 1;

                const ppn = (pte >> 10) & 0xfffffffffff;
                a = ppn * PAGE_SIZE;
                if (i < 0)
                    return switch (access_type) {
                        .Instruction => error.InstructionPageFault,
                        .Load => error.LoadPageFault,
                        .Store => error.StoreAMOPageFault,
                    };
            }

            const ppn: [3]u64 = .{
                (pte >> 10) & 0x1ff,
                (pte >> 19) & 0x1ff,
                (pte >> 28) & 0x3ffffff,
            };

            const offset = address & 0xfff;
            return switch (i) {
                0 => blk: {
                    const _ppn = (pte >> 10) & 0xfffffffffff;
                    break :blk (_ppn << 12) | offset;
                },
                1, 2 => (ppn[2] << 30) | (ppn[1] << 21) | (vpn[0] << 12) | offset,
                else => switch (access_type) {
                    .Instruction => error.InstructionPageFault,
                    .Load => error.LoadPageFault,
                    .Store => error.StoreAMOPageFault,
                },
            };
        }

        pub fn loadCsr(self: *Self, address: u64) u64 {
            return switch (address) {
                SIE => self.csrs[MIE] & self.csrs[MIDELEG],
                else => self.csrs[address],
            };
        }

        pub fn storeCsr(self: *Self, address: u64, value: u64) void {
            switch (address) {
                SIE => self.csrs[MIE] = (self.csrs[MIE] & ~self.csrs[MIDELEG]) | (value & ~self.csrs[MIDELEG]),
                else => self.csrs[address] = value,
            }
        }

        pub fn load(self: *Self, comptime T: type, address: u64) trap.Exception!u64 {
            const addr = try self.translate(address, .Load);
            return self.bus.load(T, addr);
        }

        pub fn store(self: *Self, comptime T: type, address: u64, value: u64) trap.Exception!void {
            const addr = try self.translate(address, .Load);
            return self.bus.store(T, addr, value);
        }

        pub fn fetch(self: *Self) trap.Exception!u64 {
            const pc = try self.translate(self.pc, .Instruction);
            return self.bus.load(u32, pc) catch error.InstructionAccessFault;
        }

        pub fn execute(self: *Self, inst: u64) trap.Exception!void {
            if (self.idle) return;

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
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst))))) >> 20));
                    const addr = self.regs[rs1] +% imm;

                    self.regs[rd] = switch (funct3) {
                        // lb
                        0 => blk: {
                            const val = try self.load(u8, addr);
                            break :blk @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
                        },
                        // lh
                        1 => blk: {
                            const val = try self.load(u16, addr);
                            break :blk @as(u64, @bitCast(@as(i64, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
                        },
                        // lw
                        2 => blk: {
                            const val = try self.load(u32, addr);
                            break :blk @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                        },
                        // ld
                        3 => try self.load(u64, addr),
                        // lbu
                        4 => try self.load(u8, addr),
                        // lhu
                        5 => try self.load(u16, addr),
                        // lwu
                        6 => try self.load(u32, addr),
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                0x0f => {
                    switch (funct3) {
                        // fence(.i)
                        // Do nothing for now.
                        0, 1 => {},
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    }
                },
                0x13 => {
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0xfff00000))))) >> 20));
                    const shamt = @as(u32, @truncate(imm & 0x3f));

                    self.regs[rd] = switch (funct3) {
                        // addi
                        0 => self.regs[rs1] +% imm,
                        // slli
                        1 => std.math.shl(u64, self.regs[rs1], shamt),
                        // slti
                        2 => if (@as(i64, @bitCast(self.regs[rs1])) < @as(i64, @bitCast(imm))) 1 else 0,
                        // sltiu
                        3 => if (self.regs[rs1] < imm) 1 else 0,
                        // xori
                        4 => self.regs[rs1] ^ imm,
                        5 => switch (funct7 >> 1) {
                            // slri
                            0x00 => std.math.shr(u64, self.regs[rs1], shamt),
                            // srai
                            0x10 => @as(u64, @bitCast(std.math.shr(i64, @as(i64, @bitCast(self.regs[rs1])), shamt))),
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        // ori
                        6 => self.regs[rs1] | imm,
                        // andi
                        7 => self.regs[rs1] & imm,
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                // auipc
                0x17 => {
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0xfff00000)))))));
                    self.regs[rd] = (self.pc +% imm) - 4;
                },
                0x1b => {
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst))))) >> 20));
                    const shamt = @as(u32, @truncate(imm & 0x1f));

                    self.regs[rd] = switch (funct3) {
                        // addiw
                        0 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1] +% imm))))))),
                        // slliw
                        1 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(std.math.shl(u64, self.regs[rs1], shamt)))))))),
                        5 => switch (funct7) {
                            // slriw
                            0x00 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(std.math.shr(u32, @as(u32, @truncate(self.regs[rs1])), shamt)))))),
                            // sraiw
                            0x20 => @as(u64, @bitCast(@as(i64, std.math.shr(u32, @as(u32, @truncate(self.regs[rs1])), shamt)))),
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                0x23 => {
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0xfe000000))))) >> 20)) | ((inst >> 7) & 0x1f);
                    const addr = self.regs[rs1] +% imm;

                    switch (funct3) {
                        // sb
                        0 => try self.store(u8, addr, self.regs[rs2]),
                        // sh
                        1 => try self.store(u16, addr, self.regs[rs2]),
                        // sw
                        2 => try self.store(u32, addr, self.regs[rs2]),
                        // sd
                        3 => try self.store(u64, addr, self.regs[rs2]),
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    }
                },
                // the fuck is 0x2a and why is it in my tests for some reason
                0x2a => {},
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
                                const _rs1 = try self.load(u32, self.regs[rs1]);
                                try self.store(u32, self.regs[rs1], _rs1 + self.regs[rs2]);
                                break :blk _rs1;
                            },
                            // amoadd.d
                            3 => blk: {
                                const _rs1 = try self.load(u64, self.regs[rs1]);
                                try self.store(u64, self.regs[rs1], _rs1 + self.regs[rs2]);
                                break :blk _rs1;
                            },
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        1 => switch (funct3) {
                            // amoswap.w
                            2 => blk: {
                                const _rs1 = try self.load(u32, self.regs[rs1]);
                                try self.store(u32, self.regs[rs1], self.regs[rs2]);
                                break :blk _rs1;
                            },
                            // amoadd.d
                            3 => blk: {
                                const _rs1 = try self.load(u64, self.regs[rs1]);
                                try self.store(u64, self.regs[rs1], self.regs[rs2]);
                                break :blk _rs1;
                            },
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        else => {
                            log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                0x33 => {
                    const shamt = @as(u32, @truncate(self.regs[rs2] & 0x3f));

                    self.regs[rd] = switch (funct3) {
                        0 => switch (funct7) {
                            // add
                            0x00 => self.regs[rs1] +% self.regs[rs2],
                            // mul
                            0x01 => self.regs[rs1] *% self.regs[rs2],
                            // sub
                            0x20 => self.regs[rs1] -% self.regs[rs2],
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        // sll
                        1 => std.math.shl(u64, self.regs[rs1], shamt),
                        // slt
                        2 => if (@as(i64, @bitCast(self.regs[rs1])) < @as(i64, @bitCast(self.regs[rs2]))) 1 else 0,
                        // sltu
                        3 => if (self.regs[rs1] < self.regs[rs2]) 1 else 0,
                        4 => switch (funct7) {
                            // xor
                            0x00 => self.regs[rs1] ^ self.regs[rs2],
                            // div
                            0x01 => switch (self.regs[rs2]) {
                                0 => std.math.maxInt(u64),
                                else => blk: {
                                    const dividend = @as(i64, @bitCast(self.regs[rs1]));
                                    const divisor = @as(i64, @bitCast(self.regs[rs2]));
                                    break :blk @as(u64, @bitCast(@divTrunc(dividend, divisor)));
                                },
                            },
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        5 => switch (funct7) {
                            // srl
                            0x00 => std.math.shr(u64, self.regs[rs1], shamt),
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
                            0x20 => @as(u64, @bitCast(std.math.shr(i64, @as(i64, @bitCast(self.regs[rs1])), self.regs[rs2]))),
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        6 => switch (funct7) {
                            // or
                            0x00 => self.regs[rs1] | self.regs[rs2],
                            // rem
                            0x01 => switch (self.regs[rs2]) {
                                0 => self.regs[rs1],
                                else => blk: {
                                    const dividend = @as(i64, @bitCast(self.regs[rs1]));
                                    const divisor = @as(i64, @bitCast(self.regs[rs2]));
                                    break :blk @as(u64, @bitCast(@mod(dividend, divisor)));
                                },
                            },
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
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
                                return error.IllegalInstruction;
                            },
                        },
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                // lui
                0x37 => self.regs[rd] = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0xfffff000))))))),
                0x3b => {
                    const shamt = @as(u32, @truncate(self.regs[rs2] & 0x1f));

                    self.regs[rd] = switch (funct3) {
                        0 => switch (funct7) {
                            // addw
                            0x00 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1] +% self.regs[rs2]))))))),
                            // subw
                            0x20 => @as(u64, @intCast(@as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1] -% self.regs[rs2])))))),
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        // sllw
                        1 => @as(u64, @intCast(@as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1])))) << @as(u5, @truncate(shamt)))),
                        4 => switch (funct7) {
                            // divw
                            0x01 => switch (self.regs[rs2]) {
                                0 => std.math.maxInt(u64),
                                else => blk: {
                                    const dividend = @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1]))));
                                    const divisor = @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs2]))));
                                    break :blk @as(u64, @intCast(@divTrunc(dividend, divisor)));
                                },
                            },
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        5 => switch (funct7) {
                            // srlw
                            0x00 => @as(u64, @intCast(std.math.shr(i32, @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1])))), shamt))),
                            // divuw
                            0x01 => switch (self.regs[rs2]) {
                                0 => std.math.maxInt(u64),
                                else => blk: {
                                    const dividend = @as(u32, @truncate(self.regs[rs1]));
                                    const divisor = @as(u32, @truncate(self.regs[rs2]));
                                    break :blk @as(u64, @intCast(@as(i32, @bitCast(dividend / divisor))));
                                },
                            },
                            // sraw
                            0x20 => @as(u64, @intCast(@as(i32, @bitCast(std.math.shr(u32, @as(u32, @truncate(self.regs[rs1])), @as(i32, @bitCast(shamt))))))),
                            else => {
                                log.err("Unimplemented opcode: {x} (funct3: {x}, funct7: {x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        6 => switch (funct7) {
                            // remw
                            0x01 => switch (self.regs[rs2]) {
                                0 => self.regs[rs1],
                                else => blk: {
                                    const dividend = @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs1]))));
                                    const divisor = @as(i32, @bitCast(@as(u32, @truncate(self.regs[rs2]))));
                                    break :blk @as(u64, @intCast(@mod(dividend, divisor)));
                                },
                            },
                            else => {
                                log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        7 => switch (funct7) {
                            // remuw
                            0x01 => switch (self.regs[rs2]) {
                                0 => self.regs[rs1],
                                else => blk: {
                                    const dividend = @as(u32, @truncate(self.regs[rs1]));
                                    const divisor = @as(u32, @truncate(self.regs[rs2]));
                                    break :blk @as(u64, @intCast(@as(i32, @bitCast(dividend % divisor))));
                                },
                            },
                            else => {
                                log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                                return error.IllegalInstruction;
                            },
                        },
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                0x63 => {
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0x80000000))))) >> 19)) | ((inst & 0x80) << 4) | ((inst >> 20) & 0x7e0) | ((inst >> 7) & 0x1e);
                    self.pc = switch (funct3) {
                        // beq
                        0 => if (self.regs[rs1] == self.regs[rs2]) (self.pc +% imm) - 4 else 0,
                        // bne
                        1 => if (self.regs[rs1] != self.regs[rs2]) (self.pc +% imm) - 4 else 0,
                        // blt
                        4 => if (@as(i64, @bitCast(self.regs[rs1])) < @as(i64, @bitCast(self.regs[rs2]))) (self.pc +% imm) - 4 else 0,
                        // bge
                        5 => if (@as(i64, @bitCast(self.regs[rs1])) >= @as(i64, @bitCast(self.regs[rs2]))) (self.pc +% imm) - 4 else 0,
                        // bltu
                        6 => if (self.regs[rs1] < self.regs[rs2]) (self.pc +% imm) - 4 else 0,
                        // bgeu
                        7 => if (self.regs[rs1] >= self.regs[rs2]) (self.pc +% imm) - 4 else 0,
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    };
                },
                // jalr
                0x67 => {
                    const pc = self.pc;

                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0xfff00000))))) >> 20));
                    self.pc = (self.regs[rs1] +% imm) & ~@as(u64, @intCast(1));

                    self.regs[rd] = pc;
                },
                // jal
                0x6f => {
                    self.regs[rd] = self.pc;
                    const imm = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(inst & 0x80000000))))) >> 11)) | (inst & 0xff000) | ((inst >> 9) & 0x800) | ((inst >> 20) & 0x7fe);
                    self.pc = (self.pc +% imm) - 4;
                },
                0x73 => {
                    const csr_address = (inst & 0xfff00000) >> 20;
                    switch (funct3) {
                        0 => switch (rs2) {
                            // ecall
                            0 => switch (self.mode) {
                                .User => return error.EnvironmentCallFromUMode,
                                .Supervisor => return error.EnvironmentCallFromSMode,
                                .Machine => return error.EnvironmentCallFromMMode,
                            },
                            // ebreak
                            1 => return error.Breakpoint,
                            2 => switch (funct7) {
                                // sret
                                0x08 => {
                                    self.pc = self.loadCsr(SEPC);
                                    self.mode = switch ((self.loadCsr(SSTATUS) >> 8) & 1) {
                                        1 => .Supervisor,
                                        else => .User,
                                    };
                                    self.storeCsr(
                                        SSTATUS,
                                        if (((self.loadCsr(SSTATUS) >> 5) & 1) == 1)
                                            self.loadCsr(SSTATUS) | (1 << 1)
                                        else
                                            self.loadCsr(SSTATUS) & ~@as(u64, @intCast(1 << 1)),
                                    );
                                    self.storeCsr(SSTATUS, self.loadCsr(SSTATUS) | (1 << 1));
                                    self.storeCsr(SSTATUS, self.loadCsr(SSTATUS) & ~@as(u64, @intCast(1 << 1)));
                                },
                                // mret
                                0x18 => {
                                    self.pc = self.loadCsr(MEPC);
                                    self.mode = switch ((self.loadCsr(MSTATUS) >> 11) & 0b11) {
                                        2 => .Machine,
                                        1 => .Supervisor,
                                        else => .User,
                                    };
                                    self.storeCsr(
                                        MSTATUS,
                                        if (((self.loadCsr(MSTATUS) >> 7) & 1) == 1)
                                            self.loadCsr(MSTATUS) | (1 << 3)
                                        else
                                            self.loadCsr(MSTATUS) & ~@as(u64, @intCast(1 << 3)),
                                    );
                                    self.storeCsr(MSTATUS, self.loadCsr(MSTATUS) | (1 << 7));
                                    self.storeCsr(MSTATUS, self.loadCsr(MSTATUS) & ~@as(u64, @intCast(0b11 << 11)));
                                },
                                else => {},
                            },
                            5 => switch (funct7) {
                                // wfi
                                0x8 => self.idle = true,
                                else => {},
                            },
                            else => {
                                // sfence.vma
                                // Do nothing.
                                if (funct7 == 0x09) {} else {
                                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                                    return error.IllegalInstruction;
                                }
                            },
                        },
                        // csrrw
                        1 => {
                            const csr = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, self.regs[rs1]);
                            self.regs[rd] = csr;
                            self.updatePaging(csr_address);
                        },
                        // csrrs
                        2 => {
                            const csr = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, csr | self.regs[rs1]);
                            self.regs[rd] = csr;
                            self.updatePaging(csr_address);
                        },
                        // csrrc
                        3 => {
                            const csr = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, csr & ~self.regs[rs1]);
                            self.regs[rd] = csr;
                            self.updatePaging(csr_address);
                        },
                        // csrrwi
                        5 => {
                            self.regs[rd] = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, rs1);
                            self.updatePaging(csr_address);
                        },
                        // csrrsi
                        6 => {
                            const csr = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, csr | rs1);
                            self.regs[rd] = csr;
                            self.updatePaging(csr_address);
                        },
                        // csrrci
                        7 => {
                            const csr = self.loadCsr(csr_address);
                            self.storeCsr(csr_address, csr & ~rs1);
                            self.regs[rd] = csr;
                            self.updatePaging(csr_address);
                        },
                        else => {
                            log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                            return error.IllegalInstruction;
                        },
                    }
                },
                else => {
                    log.err("Unimplemented opcode: 0x{x} (funct3: 0x{x}, funct7: 0x{x})", .{ opcode, funct3, funct7 });
                    return error.IllegalInstruction;
                },
            }
        }
    };
}
