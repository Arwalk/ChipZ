const std = @import("std");
const Stack = std.ArrayList(u16);

const default_font = [_]u8 {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
};

pub const ChipZ = struct {
    memory: [4096]u8,
    display: [64][32]bool,
    stack: Stack,
    timer_delay: u8,
    timer_sound: u8,
    program_counter: u16,
    index_register: u16,
    registers: [16]u8,

    flags : struct {
        display_update: bool,  
    },

    pub fn init(allocator: *std.mem.Allocator) ChipZ {
        var chip = ChipZ{
            .memory = [1]u8{0} ** 4096,
            .display = [_][32]bool{[_]bool{false} ** 32} ** 64,
            .stack = Stack.init(allocator),
            .timer_delay = 0,
            .timer_sound = 0,
            .program_counter = 0,
            .index_register = 0,
            .registers = [_]u8{0} ** 16,
            .flags = .{
                .display_update = false
            }
        };

        chip.set_font(default_font);

        return chip;
    }

    pub fn load_program(self: *ChipZ, program: []u8) void {
        for(program) |byte, index| {
            self.memory[index+0x200] = byte;
        }
        self.program_counter = 0x200;
    }

    pub fn deinit(self: *ChipZ) void {
        self.stack.deinit();
    }

    fn get_address(opcode: u16) u12 {
        return @intCast(u12 ,opcode & 0xFFF);
    }

    fn get_8bitconstant(opcode: u16) u8 {
        return @intCast(u8 ,opcode & 0xFF);
    }

    fn get_4bitconstant(opcode: u16) u4 {
        return @intCast(u4 ,opcode & 0xF);
    }

    fn get_x(opcode: u16) u4 {
        return @intCast(u4 ,(opcode & 0x0F00) >> 8);
    }

    fn get_y(opcode: u16) u4 {
        return @intCast(u4 ,(opcode & 0x00F0) >> 4);
    }

    pub fn set_font(self: *ChipZ, font: [16*5]u8) void {
        for (font) |byte, index| {
            self.memory[index+0x50] = byte;
        }
    }

    pub fn cycle(self: *ChipZ) void {
        self.flags.display_update = false;
        self.decode_and_execute(self.fetch());
    }

    fn fetch(self: *ChipZ) u16 {
        defer self.program_counter += 2;
        return (@intCast(u16, self.memory[self.program_counter]) << 8) + self.memory[self.program_counter+1];
    }

    /// Clears the screen.
    fn op_00E0(self: *ChipZ) void {
        for (self.display) |*row| {
            for (row) |*column| {
                column.* = false;
            }
        } 
    }

    /// Jumps to address NNN.
    fn op_1NNN(self: *ChipZ, address: u12) void {
        self.program_counter = address;
    }

    /// Sets VX to NN.
    fn op_6XNN(self: *ChipZ, register: u4, value: u8) void {
        self.registers[register] = value;
    }

    /// Adds NN to VX. (Carry flag is not changed)
    fn op_7XNN(self: *ChipZ, register: u4, value: u8) void {
        _ = @addWithOverflow(u8, self.registers[register], value, &self.registers[register]);
    }

    /// Sets I to the address NNN.
    fn op_ANNN(self: *ChipZ, address: u12) void {
        self.index_register = address;
    }

    /// Draws a sprite at coordinate (VX, VY) that has a width of 8 pixels and a height of N+1 pixels.
    /// Each row of 8 pixels is read as bit-coded starting from memory location I; I value doesn’t change after the execution of this instruction.
    /// As described above, VF is set to 1 if any screen pixels are flipped from set to unset when the sprite is drawn, and to 0 if that doesn’t happen
    fn op_DXYN(self: *ChipZ, col: u8, lin: u8, base_height: u4) void {
        self.registers[0xF] = 0;
        self.flags.display_update = true;
        for (self.memory[self.index_register..self.index_register+base_height]) |sprite_line, index_sprite| {
            var x: u4 = 0;
            while (x < 8) : ( x += 1) {
                if(((@intCast(usize, sprite_line) >> (7-x)) & 1)== 1) {
                    const coord_x = (col+x)%64;
                    const coord_y = (lin+index_sprite)%32;
                    if(self.display[coord_x][coord_y]) {
                        self.registers[0xF] = self.registers[0xF] | 1;
                    }
                    self.display[coord_x][coord_y] = !self.display[coord_x][coord_y];
                }
            }
        }
        
    }

    fn decode_and_execute(self: *ChipZ, opcode: u16) void {
        const first_nibble : u4 = @intCast(u4, (opcode & 0xF000) >> 12);
        switch(first_nibble) {
            0x0 => {
                switch(opcode) {
                    0x00E0 => self.op_00E0(),
                    0x00EE => {
                        // Returns from a subroutine.
                    },
                    else => {
                        // Calls machine code routine (RCA 1802 for COSMAC VIP) at address NNN. Not necessary for most ROMs.
                    }
                }
            },
            0x1 => self.op_1NNN(get_address(opcode)),
            0x2 => {
                // Calls subroutine at NNN.
            },
            0x3 => {
                // Skips the next instruction if VX equals NN. (Usually the next instruction is a jump to skip a code block)
            },
            0x4 => {
                // Skips the next instruction if VX doesn't equal NN. (Usually the next instruction is a jump to skip a code block)
            },
            0x5 => {
                // Skips the next instruction if VX equals VY. (Usually the next instruction is a jump to skip a code block)
            },
            0x6 => self.op_6XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x7 => self.op_7XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x8 => {
                const last_nibble : u4 = @intCast(u4, opcode & 0xF);
                switch (last_nibble) {
                    0x0 => {
                        // Sets VX to the value of VY.
                    },
                    0x1 => {
                        // Sets VX to VX or VY. (Bitwise OR operation)
                    },
                    0x2 => {
                        // Sets VX to VX and VY. (Bitwise AND operation)
                    },
                    0x3 => {
                        // Sets VX to VX xor VY.
                    },
                    0x4 => {
                        // Adds VY to VX. VF is set to 1 when there's a carry, and to 0 when there isn't.
                    },
                    0x5 => {
                        // VY is subtracted from VX. VF is set to 0 when there's a borrow, and 1 when there isn't.
                    },
                    0x6 => {
                        // Stores the least significant bit of VX in VF and then shifts VX to the right by 1.[b]
                    },
                    0x7 => {
                        // Sets VX to VY minus VX. VF is set to 0 when there's a borrow, and 1 when there isn't.
                    },
                    0xE => {
                        // Stores the most significant bit of VX in VF and then shifts VX to the left by 1.[b]
                    },
                    else => @panic("Unknown instruction!"),
                }
            },
            0x9 => {
                if((opcode & 0xF) == 0){
                    // Skips the next instruction if VX doesn't equal VY. (Usually the next instruction is a jump to skip a code block)
                }
                else @panic("Unknown instruction!");
            },
            0xA => self.op_ANNN(get_address(opcode)),
            0xB => {
                // Jumps to the address NNN plus V0.
            },
            0xC => {
                // Sets VX to the result of a bitwise and operation on a random number (Typically: 0 to 255) and NN.
            },
            0xD => self.op_DXYN(get_x(opcode), get_y(opcode), get_4bitconstant(opcode)),
            0xE => {
                const last_byte : u8 = @intCast(u8, opcode & 0xFF);
                switch (last_byte) {
                    0x9E => {
                        // Skips the next instruction if the key stored in VX is pressed. (Usually the next instruction is a jump to skip a code block)
                    },
                    0xA1 => {
                        // Skips the next instruction if the key stored in VX isn't pressed. (Usually the next instruction is a jump to skip a code block)
                    },
                    else => @panic("Unknown instruction!"),
                }
            },
            0xF => {
                const last_byte : u8 = @intCast(u8, opcode & 0xFF);
                switch (last_byte) {
                    0x07 => {
                        // Sets VX to the value of the delay timer.
                    },
                    0x0A => {
                        // A key press is awaited, and then stored in VX. (Blocking Operation. All instruction halted until next key event)
                    },
                    0x15 => {
                        // Sets the delay timer to VX.
                    },
                    0x18 => {
                        // Sets the sound timer to VX.
                    },
                    0x1E => {
                        // Adds VX to I. VF is not affected.[c]
                    },
                    0x29 => {
                        // Sets I to the location of the sprite for the character in VX. Characters 0-F (in hexadecimal) are represented by a 4x5 font.
                    },
                    0x33 => {
                        // Stores the binary-coded decimal representation of VX, with the most significant of three digits at the address in I, the middle digit at I plus 1, and the least significant digit at I plus 2.
                        // (In other words, take the decimal representation of VX, place the hundreds digit in memory at location in I, the tens digit at location I+1, and the ones digit at location I+2.)
                    },
                    0x55 => {
                        // Stores V0 to VX (including VX) in memory starting at address I. The offset from I is increased by 1 for each value written, but I itself is left unmodified.[d]
                    },
                    0x65 => {
                        // Fills V0 to VX (including VX) with values from memory starting at address I. The offset from I is increased by 1 for each value written, but I itself is left unmodified.[d]
                    },
                    else => @panic("Unknown instruction!"),
                }
            },
        }
    }
};