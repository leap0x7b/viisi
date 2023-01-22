const Cpu = @import("cpu.zig");

pub const Exception = error{
    InstructionAddressMisaligned,
    InstructionAccessFault,
    IllegalInstruction,
    Breakpoint,
    LoadAddressMisaligned,
    LoadAccessFault,
    StoreAMOAddressMisaligned,
    StoreAMOAccessFault,
    EnvironmentCallFromUMode,
    EnvironmentCallFromSMode,
    EnvironmentCallFromMMode,
    InstructionPageFault,
    LoadPageFault,
    StoreAMOPageFault,
};

pub fn exceptionCode(exception: Exception) u8 {
    return switch (exception) {
        error.InstructionAddressMisaligned => 0,
        error.InstructionAccessFault => 1,
        error.IllegalInstruction => 2,
        error.Breakpoint => 3,
        error.LoadAddressMisaligned => 4,
        error.LoadAccessFault => 5,
        error.StoreAMOAddressMisaligned => 6,
        error.StoreAMOAccessFault => 7,
        error.EnvironmentCallFromUMode => 8,
        error.EnvironmentCallFromSMode => 9,
        error.EnvironmentCallFromMMode => 11,
        error.InstructionPageFault => 12,
        error.LoadPageFault => 13,
        error.StoreAMOPageFault => 15,
    };
}

pub fn isFatal(exception: Exception) bool {
    return switch (exception) {
        error.InstructionAddressMisaligned,
        error.InstructionAccessFault,
        error.LoadAccessFault,
        error.StoreAMOAddressMisaligned,
        error.StoreAMOAccessFault,
        => true,
        else => false,
    };
}

pub fn handleTrap(exception: Exception, cpu: anytype) void {
    const exception_pc = cpu.pc - 4;
    const previous_mode = cpu.mode;

    const cause = exceptionCode(exception);
    if ((previous_mode == .Supervisor) and ((cpu.loadCsr(Cpu.MEDELEG) >> @truncate(u6, cause)) & 1 != 0)) {
        cpu.mode = .Supervisor;
        cpu.pc = cpu.loadCsr(Cpu.STVEC) & ~@intCast(u64, 1);
        cpu.storeCsr(Cpu.SEPC, exception_pc & @intCast(u64, 1));
        cpu.storeCsr(Cpu.SCAUSE, cause);
        cpu.storeCsr(Cpu.STVAL, 0);
        cpu.storeCsr(
            Cpu.SSTATUS,
            if (((cpu.loadCsr(Cpu.SSTATUS) >> 1) & 1) == 1)
                cpu.loadCsr(Cpu.SSTATUS) | (1 << 5)
            else
                cpu.loadCsr(Cpu.SSTATUS) & ~@intCast(u64, 1 << 5),
        );
        switch (previous_mode) {
            .User => cpu.storeCsr(Cpu.SSTATUS, cpu.loadCsr(Cpu.SSTATUS) & ~@intCast(u64, 1 << 8)),
            else => cpu.storeCsr(Cpu.SSTATUS, cpu.loadCsr(Cpu.SSTATUS) | (1 << 8)),
        }
    } else {
        cpu.mode = .Machine;
        cpu.pc = cpu.loadCsr(Cpu.MTVEC) & ~@intCast(u64, 1);
        cpu.storeCsr(Cpu.MEPC, exception_pc & ~@intCast(u64, 1));
        cpu.storeCsr(Cpu.MCAUSE, cause);
        cpu.storeCsr(Cpu.MTVAL, 0);
        cpu.storeCsr(
            Cpu.MSTATUS,
            if (((cpu.loadCsr(Cpu.MSTATUS) >> 3) & 1) == 1)
                cpu.loadCsr(Cpu.MSTATUS) | (1 << 7)
            else
                cpu.loadCsr(Cpu.MSTATUS) & ~@intCast(u64, 1 << 7),
        );
        cpu.storeCsr(Cpu.MSTATUS, cpu.loadCsr(Cpu.MSTATUS) & ~@intCast(u64, 1 << 3));
        cpu.storeCsr(Cpu.MSTATUS, cpu.loadCsr(Cpu.MSTATUS) & ~@intCast(u64, 0b11 << 11));
    }
}
