const chipz = @import("chipz");
const std = @import("std");
const test_allocator = std.testing.allocator;
const expect_equal = std.testing.expectEqual;
const expect_equal_slices = std.testing.expectEqualSlices;

test "clear screen" {
    var emu = chipz.ChipZ.init(test_allocator);

    emu.memory[1] = 0xE0;
    emu.display[4][4] = true;
    emu.cycle();

    expect_equal(emu.display[4][4], false);
}

test "jump" {
    var emu = chipz.ChipZ.init(test_allocator);

    emu.memory[0] = 0x11;
    emu.cycle();
    expect_equal(emu.program_counter, 0x100);
}

test "set vx nn and add x nn" {
    var emu = chipz.ChipZ.init(test_allocator);
    emu.memory[0] = 0x6A;
    emu.memory[1] = 0x12;
    emu.memory[2] = 0x7A;
    emu.memory[3] = 0x01;

    emu.cycle();
    expect_equal(emu.registers[0xA], 0x12);

    emu.cycle();
    expect_equal(emu.registers[0xA], 0x13);
}

test "set I" {
    var emu = chipz.ChipZ.init(test_allocator);
    emu.memory[0] = 0xA6;
    emu.memory[1] = 0x66;

    emu.cycle();
    expect_equal(emu.index_register, 0x666);
}

test "display simple" {
    var emu = chipz.ChipZ.init(test_allocator);

    //setting up instruction
    // drawing 3 height sprite at 0,0
    emu.memory[0] = 0xD0;
    emu.memory[1] = 0x03;
    emu.memory[2] = 0xD0;
    emu.memory[3] = 0x03;

    // setting up sprite
    emu.memory[0x200] = 0x3C;
    emu.memory[0x201] = 0xC3;
    emu.memory[0x202] = 0xFF;
    emu.index_register = 0x200;

    emu.cycle();
    // 00111100
    // 11000011
    // 11111111
    expect_equal(emu.display[0][0], false);
    expect_equal(emu.display[1][0], false);
    expect_equal(emu.display[2][0], true);
    expect_equal(emu.display[3][0], true);
    expect_equal(emu.display[4][0], true);
    expect_equal(emu.display[5][0], true);
    expect_equal(emu.display[6][0], false);
    expect_equal(emu.display[7][0], false);
    expect_equal(emu.display[0][1], true);

    expect_equal(emu.display[1][1], true);
    expect_equal(emu.display[2][1], false);
    expect_equal(emu.display[3][1], false);
    expect_equal(emu.display[4][1], false);
    expect_equal(emu.display[5][1], false);
    expect_equal(emu.display[6][1], true);
    expect_equal(emu.display[7][1], true);

    expect_equal(emu.display[1][2], true);
    expect_equal(emu.display[2][2], true);
    expect_equal(emu.display[3][2], true);
    expect_equal(emu.display[4][2], true);
    expect_equal(emu.display[5][2], true);
    expect_equal(emu.display[6][2], true);
    expect_equal(emu.display[7][2], true);
    expect_equal(emu.registers[0xF], 0);

    emu.cycle();
    expect_equal(emu.display[0][0], false);
    expect_equal(emu.display[1][0], false);
    expect_equal(emu.display[2][0], false);
    expect_equal(emu.display[3][0], false);
    expect_equal(emu.display[4][0], false);
    expect_equal(emu.display[5][0], false);
    expect_equal(emu.display[6][0], false);
    expect_equal(emu.display[7][0], false);
    expect_equal(emu.display[0][1], false);
    expect_equal(emu.display[1][1], false);
    expect_equal(emu.display[2][1], false);
    expect_equal(emu.display[3][1], false);
    expect_equal(emu.display[4][1], false);
    expect_equal(emu.display[5][1], false);
    expect_equal(emu.display[6][1], false);
    expect_equal(emu.display[7][1], false);
    expect_equal(emu.display[1][2], false);
    expect_equal(emu.display[2][2], false);
    expect_equal(emu.display[3][2], false);
    expect_equal(emu.display[4][2], false);
    expect_equal(emu.display[5][2], false);
    expect_equal(emu.display[6][2], false);
    expect_equal(emu.display[7][2], false);
    expect_equal(emu.registers[0xF], 1);

}

test "ibm" {
    var emu = chipz.ChipZ.init(test_allocator);
    const ibm = @embedFile("../demo_files/IBM Logo.ch8");

    var ibm_data : [132]u8 = [_]u8{0} ** 132;
    for (ibm) |byte, index| ibm_data[index] = byte; 

    emu.load_program(&ibm_data);
    emu.cycle();
    emu.cycle();
    expect_equal(emu.index_register, 0x22A);
    
    emu.cycle();
    expect_equal(emu.registers[0], 0x0C);
    
    emu.cycle();
    expect_equal(emu.registers[1], 0x08);

}