const chipz = @import("chipz");
const std = @import("std");
const test_allocator = std.testing.allocator;
const expect_equal = std.testing.expectEqual;
const expect_equal_slices = std.testing.expectEqualSlices;
const expect = std.testing.expect;

test "clear screen" {
    var emu = chipz.ChipZ.init(test_allocator);

    emu.memory[1] = 0xE0;
    emu.display[4][4] = true;
    try emu.cycle();

    try expect_equal(emu.display[4][4], false);
}

test "jump" {
    var emu = chipz.ChipZ.init(test_allocator);

    emu.memory[0] = 0x11;
    try emu.cycle();
    try expect_equal(emu.program_counter, 0x100);
}

test "set vx nn and add x nn" {
    var emu = chipz.ChipZ.init(test_allocator);
    emu.memory[0] = 0x6A;
    emu.memory[1] = 0x12;
    emu.memory[2] = 0x7A;
    emu.memory[3] = 0x01;

    try emu.cycle();
    try expect_equal(emu.registers[0xA], 0x12);

    try emu.cycle();
    try expect_equal(emu.registers[0xA], 0x13);
}

test "set I" {
    var emu = chipz.ChipZ.init(test_allocator);
    emu.memory[0] = 0xA6;
    emu.memory[1] = 0x66;

    try emu.cycle();
    try expect_equal(emu.index_register, 0x666);
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

    try emu.cycle();
    // 00111100
    // 11000011
    // 11111111
    try expect_equal(emu.display[0][0], false);
    try expect_equal(emu.display[1][0], false);
    try expect_equal(emu.display[2][0], true);
    try expect_equal(emu.display[3][0], true);
    try expect_equal(emu.display[4][0], true);
    try expect_equal(emu.display[5][0], true);
    try expect_equal(emu.display[6][0], false);
    try expect_equal(emu.display[7][0], false);
    try expect_equal(emu.display[0][1], true);

    try expect_equal(emu.display[1][1], true);
    try expect_equal(emu.display[2][1], false);
    try expect_equal(emu.display[3][1], false);
    try expect_equal(emu.display[4][1], false);
    try expect_equal(emu.display[5][1], false);
    try expect_equal(emu.display[6][1], true);
    try expect_equal(emu.display[7][1], true);

    try expect_equal(emu.display[1][2], true);
    try expect_equal(emu.display[2][2], true);
    try expect_equal(emu.display[3][2], true);
    try expect_equal(emu.display[4][2], true);
    try expect_equal(emu.display[5][2], true);
    try expect_equal(emu.display[6][2], true);
    try expect_equal(emu.display[7][2], true);
    try expect_equal(emu.registers[0xF], 0);

    try emu.cycle();
    try expect_equal(emu.display[0][0], false);
    try expect_equal(emu.display[1][0], false);
    try expect_equal(emu.display[2][0], false);
    try expect_equal(emu.display[3][0], false);
    try expect_equal(emu.display[4][0], false);
    try expect_equal(emu.display[5][0], false);
    try expect_equal(emu.display[6][0], false);
    try expect_equal(emu.display[7][0], false);
    try expect_equal(emu.display[0][1], false);
    try expect_equal(emu.display[1][1], false);
    try expect_equal(emu.display[2][1], false);
    try expect_equal(emu.display[3][1], false);
    try expect_equal(emu.display[4][1], false);
    try expect_equal(emu.display[5][1], false);
    try expect_equal(emu.display[6][1], false);
    try expect_equal(emu.display[7][1], false);
    try expect_equal(emu.display[1][2], false);
    try expect_equal(emu.display[2][2], false);
    try expect_equal(emu.display[3][2], false);
    try expect_equal(emu.display[4][2], false);
    try expect_equal(emu.display[5][2], false);
    try expect_equal(emu.display[6][2], false);
    try expect_equal(emu.display[7][2], false);
    try expect_equal(emu.registers[0xF], 1);
}

test "BCD conversion" {
    var emu = chipz.ChipZ.init(test_allocator);
    var program = [_]u8{ 0xF0, 0x33 };
    emu.load_program(&program);
    emu.index_register = 0x500;
    emu.registers[0] = 0x9C;

    try emu.cycle();

    try expect_equal(@as(u8, @intCast(6)), emu.memory[0x502]);
    try expect_equal(@as(u8, @intCast(5)), emu.memory[0x501]);
    try expect_equal(@as(u8, @intCast(1)), emu.memory[0x500]);
}

test "bestcoder_rom" {
    var emu = chipz.ChipZ.init(test_allocator);
    const file_program = @embedFile("../demo_files/bc_test.ch8");
    var program = [_]u8{0} ** file_program.len;
    for (file_program, 0..) |byte, index| {
        program[index] = byte;
    }
    emu.load_program(&program);

    var index: usize = 0;
    while (index < 500) : (index += 1) {
        try emu.cycle();
    }

    const ExpectedCoords = struct { y: usize, x: usize };

    const expected = [_]ExpectedCoords{
        ExpectedCoords{ .y = 21, .x = 11 },
        ExpectedCoords{ .y = 22, .x = 11 },
        ExpectedCoords{ .y = 23, .x = 11 },
        ExpectedCoords{ .y = 24, .x = 11 },
        ExpectedCoords{ .y = 30, .x = 11 },
        ExpectedCoords{ .y = 31, .x = 11 },
        ExpectedCoords{ .y = 32, .x = 11 },
        ExpectedCoords{ .y = 33, .x = 11 },
        ExpectedCoords{ .y = 37, .x = 11 },
        ExpectedCoords{ .y = 42, .x = 11 },
        ExpectedCoords{ .y = 21, .x = 12 },
        ExpectedCoords{ .y = 25, .x = 12 },
        ExpectedCoords{ .y = 29, .x = 12 },
        ExpectedCoords{ .y = 34, .x = 12 },
        ExpectedCoords{ .y = 37, .x = 12 },
        ExpectedCoords{ .y = 38, .x = 12 },
        ExpectedCoords{ .y = 42, .x = 12 },
        ExpectedCoords{ .y = 21, .x = 13 },
        ExpectedCoords{ .y = 25, .x = 13 },
        ExpectedCoords{ .y = 29, .x = 13 },
        ExpectedCoords{ .y = 34, .x = 13 },
        ExpectedCoords{ .y = 37, .x = 13 },
        ExpectedCoords{ .y = 39, .x = 13 },
        ExpectedCoords{ .y = 42, .x = 13 },
        ExpectedCoords{ .y = 21, .x = 14 },
        ExpectedCoords{ .y = 22, .x = 14 },
        ExpectedCoords{ .y = 23, .x = 14 },
        ExpectedCoords{ .y = 24, .x = 14 },
        ExpectedCoords{ .y = 29, .x = 14 },
        ExpectedCoords{ .y = 34, .x = 14 },
        ExpectedCoords{ .y = 37, .x = 14 },
        ExpectedCoords{ .y = 40, .x = 14 },
        ExpectedCoords{ .y = 42, .x = 14 },
        ExpectedCoords{ .y = 21, .x = 15 },
        ExpectedCoords{ .y = 25, .x = 15 },
        ExpectedCoords{ .y = 29, .x = 15 },
        ExpectedCoords{ .y = 34, .x = 15 },
        ExpectedCoords{ .y = 37, .x = 15 },
        ExpectedCoords{ .y = 41, .x = 15 },
        ExpectedCoords{ .y = 42, .x = 15 },
        ExpectedCoords{ .y = 21, .x = 16 },
        ExpectedCoords{ .y = 25, .x = 16 },
        ExpectedCoords{ .y = 29, .x = 16 },
        ExpectedCoords{ .y = 34, .x = 16 },
        ExpectedCoords{ .y = 37, .x = 16 },
        ExpectedCoords{ .y = 42, .x = 16 },
        ExpectedCoords{ .y = 21, .x = 17 },
        ExpectedCoords{ .y = 25, .x = 17 },
        ExpectedCoords{ .y = 29, .x = 17 },
        ExpectedCoords{ .y = 34, .x = 17 },
        ExpectedCoords{ .y = 37, .x = 17 },
        ExpectedCoords{ .y = 42, .x = 17 },
        ExpectedCoords{ .y = 21, .x = 18 },
        ExpectedCoords{ .y = 22, .x = 18 },
        ExpectedCoords{ .y = 23, .x = 18 },
        ExpectedCoords{ .y = 24, .x = 18 },
        ExpectedCoords{ .y = 30, .x = 18 },
        ExpectedCoords{ .y = 31, .x = 18 },
        ExpectedCoords{ .y = 32, .x = 18 },
        ExpectedCoords{ .y = 33, .x = 18 },
        ExpectedCoords{ .y = 37, .x = 18 },
        ExpectedCoords{ .y = 42, .x = 18 },
        ExpectedCoords{ .y = 2, .x = 24 },
        ExpectedCoords{ .y = 3, .x = 24 },
        ExpectedCoords{ .y = 17, .x = 24 },
        ExpectedCoords{ .y = 18, .x = 24 },
        ExpectedCoords{ .y = 32, .x = 24 },
        ExpectedCoords{ .y = 37, .x = 24 },
        ExpectedCoords{ .y = 38, .x = 24 },
        ExpectedCoords{ .y = 39, .x = 24 },
        ExpectedCoords{ .y = 49, .x = 24 },
        ExpectedCoords{ .y = 2, .x = 25 },
        ExpectedCoords{ .y = 4, .x = 25 },
        ExpectedCoords{ .y = 17, .x = 25 },
        ExpectedCoords{ .y = 19, .x = 25 },
        ExpectedCoords{ .y = 32, .x = 25 },
        ExpectedCoords{ .y = 37, .x = 25 },
        ExpectedCoords{ .y = 49, .x = 25 },
        ExpectedCoords{ .y = 2, .x = 26 },
        ExpectedCoords{ .y = 4, .x = 26 },
        ExpectedCoords{ .y = 7, .x = 26 },
        ExpectedCoords{ .y = 9, .x = 26 },
        ExpectedCoords{ .y = 17, .x = 26 },
        ExpectedCoords{ .y = 19, .x = 26 },
        ExpectedCoords{ .y = 23, .x = 26 },
        ExpectedCoords{ .y = 24, .x = 26 },
        ExpectedCoords{ .y = 28, .x = 26 },
        ExpectedCoords{ .y = 29, .x = 26 },
        ExpectedCoords{ .y = 32, .x = 26 },
        ExpectedCoords{ .y = 33, .x = 26 },
        ExpectedCoords{ .y = 37, .x = 26 },
        ExpectedCoords{ .y = 43, .x = 26 },
        ExpectedCoords{ .y = 49, .x = 26 },
        ExpectedCoords{ .y = 53, .x = 26 },
        ExpectedCoords{ .y = 54, .x = 26 },
        ExpectedCoords{ .y = 2, .x = 27 },
        ExpectedCoords{ .y = 3, .x = 27 },
        ExpectedCoords{ .y = 7, .x = 27 },
        ExpectedCoords{ .y = 9, .x = 27 },
        ExpectedCoords{ .y = 17, .x = 27 },
        ExpectedCoords{ .y = 18, .x = 27 },
        ExpectedCoords{ .y = 22, .x = 27 },
        ExpectedCoords{ .y = 24, .x = 27 },
        ExpectedCoords{ .y = 27, .x = 27 },
        ExpectedCoords{ .y = 32, .x = 27 },
        ExpectedCoords{ .y = 37, .x = 27 },
        ExpectedCoords{ .y = 42, .x = 27 },
        ExpectedCoords{ .y = 44, .x = 27 },
        ExpectedCoords{ .y = 48, .x = 27 },
        ExpectedCoords{ .y = 49, .x = 27 },
        ExpectedCoords{ .y = 52, .x = 27 },
        ExpectedCoords{ .y = 54, .x = 27 },
        ExpectedCoords{ .y = 58, .x = 27 },
        ExpectedCoords{ .y = 59, .x = 27 },
        ExpectedCoords{ .y = 2, .x = 28 },
        ExpectedCoords{ .y = 4, .x = 28 },
        ExpectedCoords{ .y = 7, .x = 28 },
        ExpectedCoords{ .y = 8, .x = 28 },
        ExpectedCoords{ .y = 9, .x = 28 },
        ExpectedCoords{ .y = 17, .x = 28 },
        ExpectedCoords{ .y = 19, .x = 28 },
        ExpectedCoords{ .y = 22, .x = 28 },
        ExpectedCoords{ .y = 23, .x = 28 },
        ExpectedCoords{ .y = 28, .x = 28 },
        ExpectedCoords{ .y = 32, .x = 28 },
        ExpectedCoords{ .y = 37, .x = 28 },
        ExpectedCoords{ .y = 42, .x = 28 },
        ExpectedCoords{ .y = 44, .x = 28 },
        ExpectedCoords{ .y = 47, .x = 28 },
        ExpectedCoords{ .y = 49, .x = 28 },
        ExpectedCoords{ .y = 52, .x = 28 },
        ExpectedCoords{ .y = 53, .x = 28 },
        ExpectedCoords{ .y = 58, .x = 28 },
        ExpectedCoords{ .y = 2, .x = 29 },
        ExpectedCoords{ .y = 4, .x = 29 },
        ExpectedCoords{ .y = 9, .x = 29 },
        ExpectedCoords{ .y = 17, .x = 29 },
        ExpectedCoords{ .y = 19, .x = 29 },
        ExpectedCoords{ .y = 22, .x = 29 },
        ExpectedCoords{ .y = 29, .x = 29 },
        ExpectedCoords{ .y = 32, .x = 29 },
        ExpectedCoords{ .y = 37, .x = 29 },
        ExpectedCoords{ .y = 42, .x = 29 },
        ExpectedCoords{ .y = 44, .x = 29 },
        ExpectedCoords{ .y = 47, .x = 29 },
        ExpectedCoords{ .y = 49, .x = 29 },
        ExpectedCoords{ .y = 52, .x = 29 },
        ExpectedCoords{ .y = 58, .x = 29 },
        ExpectedCoords{ .y = 2, .x = 30 },
        ExpectedCoords{ .y = 3, .x = 30 },
        ExpectedCoords{ .y = 9, .x = 30 },
        ExpectedCoords{ .y = 17, .x = 30 },
        ExpectedCoords{ .y = 18, .x = 30 },
        ExpectedCoords{ .y = 23, .x = 30 },
        ExpectedCoords{ .y = 24, .x = 30 },
        ExpectedCoords{ .y = 27, .x = 30 },
        ExpectedCoords{ .y = 28, .x = 30 },
        ExpectedCoords{ .y = 33, .x = 30 },
        ExpectedCoords{ .y = 34, .x = 30 },
        ExpectedCoords{ .y = 37, .x = 30 },
        ExpectedCoords{ .y = 38, .x = 30 },
        ExpectedCoords{ .y = 39, .x = 30 },
        ExpectedCoords{ .y = 43, .x = 30 },
        ExpectedCoords{ .y = 48, .x = 30 },
        ExpectedCoords{ .y = 49, .x = 30 },
        ExpectedCoords{ .y = 53, .x = 30 },
        ExpectedCoords{ .y = 54, .x = 30 },
        ExpectedCoords{ .y = 58, .x = 30 },
        ExpectedCoords{ .y = 60, .x = 30 },
        ExpectedCoords{ .y = 7, .x = 31 },
        ExpectedCoords{ .y = 8, .x = 31 },
        ExpectedCoords{ .y = 9, .x = 31 },
    };

    for (expected) |coords| {
        try expect(emu.display[coords.y][coords.x]);
    }
}
