const std = @import("std");
const Cpu = @import("../cpu.zig");
const Bus = @import("../bus.zig");
const Trap = @import("../trap.zig");

pub fn emuTest(filename: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = [_]u8{0} ** 1024;
    var stream = std.io.fixedBufferStream(&buffer);

    var reader = std.io.bufferedReader(stream.reader());
    var writer = std.io.bufferedWriter(stream.writer());

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    var cpu = try Cpu.init(reader, writer);
    try cpu.init(try file.readToEndAlloc(arena.allocator(), 1024 * 1024 * 256), 1024 * 1024 * 256, arena.allocator());

    const stat = try file.stat();
    while (cpu.pc - Bus.DRAM_BASE < stat.size) {
        const inst = cpu.fetch() catch |exception| blk: {
            Trap.handleTrap(exception, &cpu);
            if (Trap.isFatal(exception)) break;
            break :blk 0;
        };
        cpu.pc += 4;
        cpu.execute(inst) catch |exception| {
            Trap.handleTrap(exception, &cpu);
            if (Trap.isFatal(exception)) break;
        };
        if (cpu.pc == 0) break;
    }

    try std.testing.expectEqual(cpu.regs[10], 0);
}

// rv64ui-p-*
test "rv64ui_p_add" {
    try emuTest("tests/rv64ui_p_add");
}

test "rv64ui_p_addi" {
    try emuTest("tests/rv64ui_p_addi");
}

test "rv64ui_p_addiw" {
    try emuTest("tests/rv64ui_p_addiw");
}

test "rv64ui_p_addw" {
    try emuTest("tests/rv64ui_p_addw");
}

test "rv64ui_p_and" {
    try emuTest("tests/rv64ui_p_and");
}

test "rv64ui_p_andi" {
    try emuTest("tests/rv64ui_p_andi");
}

test "rv64ui_p_auipc" {
    try emuTest("tests/rv64ui_p_auipc");
}

test "rv64ui_p_beq" {
    try emuTest("tests/rv64ui_p_beq");
}

test "rv64ui_p_bge" {
    try emuTest("tests/rv64ui_p_bge");
}

test "rv64ui_p_bgeu" {
    try emuTest("tests/rv64ui_p_bgeu");
}

test "rv64ui_p_blt" {
    try emuTest("tests/rv64ui_p_blt");
}

test "rv64ui_p_bltu" {
    try emuTest("tests/rv64ui_p_bltu");
}

test "rv64ui_p_bne" {
    try emuTest("tests/rv64ui_p_bne");
}

test "rv64ui_p_fence_i" {
    try emuTest("tests/rv64ui_p_fence_i");
}

test "rv64ui_p_jal" {
    try emuTest("tests/rv64ui_p_jal");
}

test "rv64ui_p_jalr" {
    try emuTest("tests/rv64ui_p_jalr");
}

test "rv64ui_p_lb" {
    try emuTest("tests/rv64ui_p_lb");
}

test "rv64ui_p_lbu" {
    try emuTest("tests/rv64ui_p_lbu");
}

test "rv64ui_p_ld" {
    try emuTest("tests/rv64ui_p_ld");
}

test "rv64ui_p_lh" {
    try emuTest("tests/rv64ui_p_lh");
}

test "rv64ui_p_lhu" {
    try emuTest("tests/rv64ui_p_lhu");
}

test "rv64ui_p_lui" {
    try emuTest("tests/rv64ui_p_lui");
}

test "rv64ui_p_lw" {
    try emuTest("tests/rv64ui_p_lw");
}

test "rv64ui_p_lwu" {
    try emuTest("tests/rv64ui_p_lwu");
}

test "rv64ui_p_or" {
    try emuTest("tests/rv64ui_p_or");
}

test "rv64ui_p_ori" {
    try emuTest("tests/rv64ui_p_ori");
}

test "rv64ui_p_sb" {
    try emuTest("tests/rv64ui_p_sb");
}

test "rv64ui_p_sd" {
    try emuTest("tests/rv64ui_p_sd");
}

test "rv64ui_p_sh" {
    try emuTest("tests/rv64ui_p_sh");
}

test "rv64ui_p_simple" {
    try emuTest("tests/rv64ui_p_simple");
}

test "rv64ui_p_sll" {
    try emuTest("tests/rv64ui_p_sll");
}

test "rv64ui_p_slli" {
    try emuTest("tests/rv64ui_p_slli");
}

test "rv64ui_p_slliw" {
    try emuTest("tests/rv64ui_p_slliw");
}

test "rv64ui_p_sllw" {
    try emuTest("tests/rv64ui_p_sllw");
}

test "rv64ui_p_slt" {
    try emuTest("tests/rv64ui_p_slt");
}

test "rv64ui_p_slti" {
    try emuTest("tests/rv64ui_p_slti");
}

test "rv64ui_p_sltiu" {
    try emuTest("tests/rv64ui_p_sltiu");
}

test "rv64ui_p_sltu" {
    try emuTest("tests/rv64ui_p_sltu");
}

test "rv64ui_p_sra" {
    try emuTest("tests/rv64ui_p_sra");
}

test "rv64ui_p_srai" {
    try emuTest("tests/rv64ui_p_srai");
}

test "rv64ui_p_sraiw" {
    try emuTest("tests/rv64ui_p_sraiw");
}

test "rv64ui_p_sraw" {
    try emuTest("tests/rv64ui_p_sraw");
}

test "rv64ui_p_srl" {
    try emuTest("tests/rv64ui_p_srl");
}

test "rv64ui_p_srli" {
    try emuTest("tests/rv64ui_p_srli");
}

test "rv64ui_p_srliw" {
    try emuTest("tests/rv64ui_p_srliw");
}

test "rv64ui_p_srlw" {
    try emuTest("tests/rv64ui_p_srlw");
}

test "rv64ui_p_sub" {
    try emuTest("tests/rv64ui_p_sub");
}

test "rv64ui_p_subw" {
    try emuTest("tests/rv64ui_p_subw");
}

test "rv64ui_p_sw" {
    try emuTest("tests/rv64ui_p_sw");
}

test "rv64ui_p_xor" {
    try emuTest("tests/rv64ui_p_xor");
}

test "rv64ui_p_xori" {
    try emuTest("tests/rv64ui_p_xori");
}

// rv64ui-v-*
//test "rv64ui_v_add" {
//    try emuTest("tests/rv64ui_v_add");
//}

//test "rv64ui_v_addi" {
//    try emuTest("tests/rv64ui_v_addi");
//}

//test "rv64ui_v_addiw" {
//    try emuTest("tests/rv64ui_v_addiw");
//}

//test "rv64ui_v_addw" {
//    try emuTest("tests/rv64ui_v_addw");
//}

//test "rv64ui_v_and" {
//    try emuTest("tests/rv64ui_v_and");
//}

//test "rv64ui_v_andi" {
//    try emuTest("tests/rv64ui_v_andi");
//}

//test "rv64ui_v_auipc" {
//    try emuTest("tests/rv64ui_v_auipc");
//}

//test "rv64ui_v_beq" {
//    try emuTest("tests/rv64ui_v_beq");
//}

//test "rv64ui_v_bge" {
//    try emuTest("tests/rv64ui_v_bge");
//}

//test "rv64ui_v_bgeu" {
//    try emuTest("tests/rv64ui_v_bgeu");
//}

//test "rv64ui_v_blt" {
//    try emuTest("tests/rv64ui_v_blt");
//}

//test "rv64ui_v_bltu" {
//    try emuTest("tests/rv64ui_v_bltu");
//}

//test "rv64ui_v_bne" {
//    try emuTest("tests/rv64ui_v_bne");
//}

//test "rv64ui_v_fence_i" {
//    try emuTest("tests/rv64ui_v_fence_i");
//}

//test "rv64ui_v_jal" {
//    try emuTest("tests/rv64ui_v_jal");
//}

//test "rv64ui_v_jalr" {
//    try emuTest("tests/rv64ui_v_jalr");
//}

//test "rv64ui_v_lb" {
//    try emuTest("tests/rv64ui_v_lb");
//}

//test "rv64ui_v_lbu" {
//    try emuTest("tests/rv64ui_v_lbu");
//}

//test "rv64ui_v_ld" {
//    try emuTest("tests/rv64ui_v_ld");
//}

//test "rv64ui_v_lh" {
//    try emuTest("tests/rv64ui_v_lh");
//}

//test "rv64ui_v_lhu" {
//    try emuTest("tests/rv64ui_v_lhu");
//}

//test "rv64ui_v_lui" {
//    try emuTest("tests/rv64ui_v_lui");
//}

//test "rv64ui_v_lw" {
//    try emuTest("tests/rv64ui_v_lw");
//}

//test "rv64ui_v_lwu" {
//    try emuTest("tests/rv64ui_v_lwu");
//}

//test "rv64ui_v_or" {
//    try emuTest("tests/rv64ui_v_or");
//}

//test "rv64ui_v_ori" {
//    try emuTest("tests/rv64ui_v_ori");
//}

//test "rv64ui_v_sb" {
//    try emuTest("tests/rv64ui_v_sb");
//}

//test "rv64ui_v_sd" {
//    try emuTest("tests/rv64ui_v_sd");
//}

//test "rv64ui_v_sh" {
//    try emuTest("tests/rv64ui_v_sh");
//}

//test "rv64ui_v_simple" {
//    try emuTest("tests/rv64ui_v_simple");
//}

//test "rv64ui_v_sll" {
//    try emuTest("tests/rv64ui_v_sll");
//}

//test "rv64ui_v_slli" {
//    try emuTest("tests/rv64ui_v_slli");
//}

//test "rv64ui_v_slliw" {
//    try emuTest("tests/rv64ui_v_slliw");
//}

//test "rv64ui_v_sllw" {
//    try emuTest("tests/rv64ui_v_sllw");
//}

//test "rv64ui_v_slt" {
//    try emuTest("tests/rv64ui_v_slt");
//}

//test "rv64ui_v_slti" {
//    try emuTest("tests/rv64ui_v_slti");
//}

//test "rv64ui_v_sltiu" {
//    try emuTest("tests/rv64ui_v_sltiu");
//}

//test "rv64ui_v_sltu" {
//    try emuTest("tests/rv64ui_v_sltu");
//}

//test "rv64ui_v_sra" {
//    try emuTest("tests/rv64ui_v_sra");
//}

//test "rv64ui_v_srai" {
//    try emuTest("tests/rv64ui_v_srai");
//}

//test "rv64ui_v_sraiw" {
//    try emuTest("tests/rv64ui_v_sraiw");
//}

//test "rv64ui_v_sraw" {
//    try emuTest("tests/rv64ui_v_sraw");
//}

//test "rv64ui_v_srl" {
//    try emuTest("tests/rv64ui_v_srl");
//}

//test "rv64ui_v_srli" {
//    try emuTest("tests/rv64ui_v_srli");
//}

//test "rv64ui_v_srliw" {
//    try emuTest("tests/rv64ui_v_srliw");
//}

//test "rv64ui_v_srlw" {
//    try emuTest("tests/rv64ui_v_srlw");
//}

//test "rv64ui_v_sub" {
//    try emuTest("tests/rv64ui_v_sub");
//}

//test "rv64ui_v_subw" {
//    try emuTest("tests/rv64ui_v_subw");
//}

//test "rv64ui_v_sw" {
//    try emuTest("tests/rv64ui_v_sw");
//}

//test "rv64ui_v_xor" {
//    try emuTest("tests/rv64ui_v_xor");
//}

//test "rv64ui_v_xori" {
//    try emuTest("tests/rv64ui_v_xori");
//}

// rv64ua-p-*
test "rv64ua_p_amoadd_d" {
    try emuTest("tests/rv64ua_p_amoadd_d");
}

test "rv64ua_p_amoadd_w" {
    try emuTest("tests/rv64ua_p_amoadd_w");
}

test "rv64ua_p_amoand_d" {
    try emuTest("tests/rv64ua_p_amoand_d");
}

test "rv64ua_p_amoand_w" {
    try emuTest("tests/rv64ua_p_amoand_w");
}

test "rv64ua_p_amomax_d" {
    try emuTest("tests/rv64ua_p_amomax_d");
}

test "rv64ua_p_amomax_w" {
    try emuTest("tests/rv64ua_p_amomax_w");
}

test "rv64ua_p_amomaxu_d" {
    try emuTest("tests/rv64ua_p_amomaxu_d");
}

test "rv64ua_p_amomaxu_w" {
    try emuTest("tests/rv64ua_p_amomaxu_w");
}

test "rv64ua_p_amomin_d" {
    try emuTest("tests/rv64ua_p_amomin_d");
}

test "rv64ua_p_amomin_w" {
    try emuTest("tests/rv64ua_p_amomin_w");
}

test "rv64ua_p_amominu_d" {
    try emuTest("tests/rv64ua_p_amominu_d");
}

test "rv64ua_p_amominu_w" {
    try emuTest("tests/rv64ua_p_amominu_w");
}

test "rv64ua_p_amoor_d" {
    try emuTest("tests/rv64ua_p_amoor_d");
}

test "rv64ua_p_amoor_w" {
    try emuTest("tests/rv64ua_p_amoor_w");
}

test "rv64ua_p_amoswap_d" {
    try emuTest("tests/rv64ua_p_amoswap_d");
}

test "rv64ua_p_amoswap_w" {
    try emuTest("tests/rv64ua_p_amoswap_w");
}

test "rv64ua_p_amoxor_d" {
    try emuTest("tests/rv64ua_p_amoxor_d");
}

test "rv64ua_p_amoxor_w" {
    try emuTest("tests/rv64ua_p_amoxor_w");
}

//TODO fix
test "rv64ua_p_lrsc" {
    try emuTest("tests/rv64ua_p_lrsc");
}

// rv64ud-p-*
//test "rv64ud_p_fadd" {
//    try emuTest("tests/rv64ud_p_fadd");
//}

//test "rv64ud_p_fclass" {
//    try emuTest("tests/rv64ud_p_fclass");
//}

//test "rv64ud_p_fcmp" {
//    try emuTest("tests/rv64ud_p_fcmp");
//}

//test "rv64ud_p_fcvt" {
//    try emuTest("tests/rv64ud_p_fcvt");
//}

//test "rv64ud_p_fcvt_w" {
//    try emuTest("tests/rv64ud_p_fcvt_w");
//}

//test "rv64ud_p_fdiv" {
//    try emuTest("tests/rv64ud_p_fdiv");
//}

//test "rv64ud_p_fmadd" {
//    try emuTest("tests/rv64ud_p_fmadd");
//}

//test "rv64ud_p_fmin" {
//    try emuTest("tests/rv64ud_p_fmin");
//}

//test "rv64ud_p_ldst" {
//    try emuTest("tests/rv64ud_p_ldst");
//}

//test "rv64ud_p_move" {
//    try emuTest("tests/rv64ud_p_move");
//}

//test "rv64ud_p_recoding" {
//    try emuTest("tests/rv64ud_p_recoding");
//}

//test "rv64ud_p_structural" {
//    try emuTest("tests/rv64ud_p_structural");
//}

// rv64uf-p-*
//test "rv64uf_p_fadd" {
//    try emuTest("tests/rv64uf_p_fadd");
//}

//test "rv64uf_p_fclass" {
//    try emuTest("tests/rv64uf_p_fclass");
//}

//test "rv64uf_p_fcmp" {
//    try emuTest("tests/rv64uf_p_fcmp");
//}

//test "rv64uf_p_fcvt" {
//    try emuTest("tests/rv64uf_p_fcvt");
//}

//test "rv64uf_p_fcvt_w" {
//    try emuTest("tests/rv64uf_p_fcvt_w");
//}

//test "rv64uf_p_fdiv" {
//    try emuTest("tests/rv64uf_p_fdiv");
//}

//test "rv64uf_p_fmadd" {
//    try emuTest("tests/rv64uf_p_fmadd");
//}

//test "rv64uf_p_fmin" {
//    try emuTest("tests/rv64uf_p_fmin");
//}

//test "rv64uf_p_ldst" {
//    try emuTest("tests/rv64uf_p_ldst");
//}

//test "rv64uf_p_move" {
//    try emuTest("tests/rv64uf_p_move");
//}

//test "rv64uf_p_recoding" {
//    try emuTest("tests/rv64uf_p_recoding");
//}

// rv64um-p-*
test "rv64um_p_div" {
    try emuTest("tests/rv64um_p_div");
}

test "rv64um_p_divu" {
    try emuTest("tests/rv64um_p_divu");
}

test "rv64um_p_divuw" {
    try emuTest("tests/rv64um_p_divuw");
}

test "rv64um_p_divw" {
    try emuTest("tests/rv64um_p_divw");
}

test "rv64um_p_mul" {
    try emuTest("tests/rv64um_p_mul");
}

test "rv64um_p_mulh" {
    try emuTest("tests/rv64um_p_mulh");
}

test "rv64um_p_mulhsu" {
    try emuTest("tests/rv64um_p_mulhsu");
}

test "rv64um_p_mulhu" {
    try emuTest("tests/rv64um_p_mulhu");
}

test "rv64um_p_mulw" {
    try emuTest("tests/rv64um_p_mulw");
}

test "rv64um_p_rem" {
    try emuTest("tests/rv64um_p_rem");
}

test "rv64um_p_remu" {
    try emuTest("tests/rv64um_p_remu");
}

test "rv64um_p_remuw" {
    try emuTest("tests/rv64um_p_remuw");
}

test "rv64um_p_remw" {
    try emuTest("tests/rv64um_p_remw");
}

// rv64uc-p-*
test "rv64uc_p_rvc" {
    try emuTest("tests/rv64uc_p_rvc");
}

// rv64mi-p-*
test "rv64mi_p_access" {
    try emuTest("tests/rv64mi_p_access");
}

test "rv64mi_p_breakpoint" {
    try emuTest("tests/rv64mi_p_breakpoint");
}

test "rv64mi_p_csr" {
    try emuTest("tests/rv64mi_p_csr");
}

test "rv64mi_p_illegal" {
    try emuTest("tests/rv64mi_p_illegal");
}

test "rv64mi_p_ma_addr" {
    try emuTest("tests/rv64mi_p_ma_addr");
}

test "rv64mi_p_ma_fetch" {
    try emuTest("tests/rv64mi_p_ma_fetch");
}

test "rv64mi_p_mcsr" {
    try emuTest("tests/rv64mi_p_mcsr");
}

test "rv64mi_p_sbreak" {
    try emuTest("tests/rv64mi_p_sbreak");
}

test "rv64mi_p_scall" {
    try emuTest("tests/rv64mi_p_scall");
}

// rv64si-p-*
test "rv64si_p_csr" {
    try emuTest("tests/rv64si_p_csr");
}

test "rv64si_p_dirty" {
    try emuTest("tests/rv64si_p_dirty");
}

test "rv64si_p_icache_alias" {
    try emuTest("tests/rv64si_p_icache_alias");
}
