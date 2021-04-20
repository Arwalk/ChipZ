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

    configuration: struct {
        shift_operations_sets_ry_into_rx: bool,
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
            },
            .configuration = .{
                .shift_operations_sets_ry_into_rx = true,   
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
    fn op_DXYN(self: *ChipZ, r_col: u8, r_lin: u8, base_height: u4) void {
        const col = self.registers[r_col];
        const lin = self.registers[r_lin];
        self.registers[0xF] = 0;
        self.flags.display_update = true;
        for (self.memory[self.index_register..self.index_register+base_height]) |sprite_line, index_sprite| {
            var x: u4 = 0;
            while (x < 8) : ( x += 1) {
                if(((@intCast(usize, sprite_line) >> (7-x)) & 1) == 1) {
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

    /// return from subroutine
    fn op_00EE(self: *ChipZ) void {
        self.program_counter = self.stack.pop();
    }

    /// start subroutine
    fn op_2NNN(self: *ChipZ, address: u12) void {
        self.stack.append(self.program_counter) catch |err| @panic("Error on pushing on stack");
        self.program_counter = address;
    }

    /// skip instruction if VX == value
    fn op_3XNN(self: *ChipZ, register: u4, value: u8) void {
        if(self.registers[register] == value) {
            self.program_counter += 2;
        }
    }

    /// skip instruction if VX != value
    fn op_4XNN(self: *ChipZ, register: u4, value: u8) void {
        if(self.registers[register] != value) {
            self.program_counter += 2;
        }
    }

    /// skip instruction if VX == VY
    fn op_5XY0(self: *ChipZ, register_a: u4, register_b: u4) void {
        if(self.registers[register_a] == self.registers[register_b]) {
            self.program_counter += 2;
        }
    }

    /// skip instruction if VX != VY
    fn op_9XY0(self: *ChipZ, register_a: u4, register_b: u4) void {
        if(self.registers[register_a] != self.registers[register_b]) {
            self.program_counter += 2;
        }
    }

    /// Sets VX to the value of VY.
    fn op_8XY0(self: *ChipZ, x: u4, y: u4) void {
        self.registers[x] =  self.registers[y];
    }

    /// VX is set to the bitwise logical disjunction (OR) of VX and VY.
    fn op_8XY1(self: *ChipZ, x: u4, y: u4) void {
        self.registers[x] =  self.registers[x] | self.registers[y];
    }

    /// VX is set to the bitwise logical conjunction (AND) of VX and VY
    fn op_8XY2(self: *ChipZ, x: u4, y: u4) void {
        self.registers[x] =  self.registers[x] & self.registers[y];
    }

    /// VX is set to the bitwise exclusive OR (XOR) of VX and VY. 
    fn op_8XY3(self: *ChipZ, x: u4, y: u4) void {
        self.registers[x] =  self.registers[x] ^ self.registers[y];
    }

    /// VX is set to the value of VX plus the value of VY
    /// Unlike 7XNN, this addition will affect the carry flag. 
    /// If the result is larger than 255 (and thus overflows the 8-bit register VX), the flag register VF is set to 1. 
    /// If it doesn’t overflow, VF is set to 0.
    fn op_8XY4(self: *ChipZ, x: u4, y: u4) void {
        const overflow = @addWithOverflow(u8, self.registers[x], self.registers[y], &self.registers[x]);
        self.registers[0xF] = if(overflow) 1 else 0;
    }

    /// sets VX to the result of VX - VY.
    /// This subtraction will also affect the carry flag, but note that it’s opposite from what you might think.
    /// If the minuend (the first operand) is larger than the subtrahend (second operand), VF will be set to 1.
    /// If the subtrahend is larger, and we “underflow” the result, VF is set to 0.
    /// Another way of thinking of it is that VF is set to 1 before the subtraction, and then the subtraction either borrows from VF (setting it to 0) or not.
    fn op_8XY5(self: *ChipZ, x: u4, y: u4) void {
        const overflow = @subWithOverflow(u8, self.registers[x], self.registers[y], &self.registers[x]);
        self.registers[0xF] = if(self.registers[x] > self.registers[y])  1 else 0;

    }

    /// sets VX to the result of VY - VX.
    /// This subtraction will also affect the carry flag, but note that it’s opposite from what you might think.
    /// If the minuend (the first operand) is larger than the subtrahend (second operand), VF will be set to 1.
    /// If the subtrahend is larger, and we “underflow” the result, VF is set to 0.
    /// Another way of thinking of it is that VF is set to 1 before the subtraction, and then the subtraction either borrows from VF (setting it to 0) or not.
    fn op_8XY7(self: *ChipZ, x: u4, y: u4) void {
        const overflow = @subWithOverflow(u8, self.registers[y], self.registers[x], &self.registers[x]);
        self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1 else 0;
    }

    /// shift 1 bit right for vx
    fn op_8XY6(self: *ChipZ, x: u4, y: u4) void {
        if(self.configuration.shift_operations_sets_ry_into_rx) {
            self.registers[x] = self.registers[y];
        }
        
        self.registers[0xF] = if(self.registers[x] & 1 == 1)  1 else 0;
        
        self.registers[x] = self.registers[x] >> 1;
    }

    /// shift 1 bit left for vx
    fn op_8XYE(self: *ChipZ, x: u4, y: u4) void {
        if(self.configuration.shift_operations_sets_ry_into_rx) {
            self.registers[x] = self.registers[y];
        }
        
        const overflow = @shlWithOverflow(u8, self.registers[x], 1, &self.registers[x]);

        self.registers[0xF] = if(overflow) 1 else 0;
        
    }

    fn decode_and_execute(self: *ChipZ, opcode: u16) void {
        const first_nibble : u4 = @intCast(u4, (opcode & 0xF000) >> 12);
        switch(first_nibble) {
            0x0 => {
                switch(opcode) {
                    0x00E0 => self.op_00E0(),
                    0x00EE => self.op_00EE(),
                    else => {
                        @panic("0x0NNN requires knowledge of the machine running the code.");// Calls machine code routine (RCA 1802 for COSMAC VIP) at address NNN. Not necessary for most ROMs.
                    }
                }
            },
            0x1 => self.op_1NNN(get_address(opcode)),
            0x2 => self.op_2NNN(get_address(opcode)),
            0x3 => self.op_3XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x4 => self.op_4XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x5 => {
                if((opcode & 0xF) == 0){
                    self.op_5XY0(get_x(opcode), get_y(opcode));
                }
                else @panic("Unknown instruction!");
            },
            0x6 => self.op_6XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x7 => self.op_7XNN(get_x(opcode), get_8bitconstant(opcode)),
            0x8 => {
                const last_nibble : u4 = @intCast(u4, opcode & 0xF);
                switch (last_nibble) {
                    0x0 => self.op_8XY0(get_x(opcode), get_y(opcode)),
                    0x1 => self.op_8XY1(get_x(opcode), get_y(opcode)),
                    0x2 => self.op_8XY2(get_x(opcode), get_y(opcode)),
                    0x3 => self.op_8XY3(get_x(opcode), get_y(opcode)),
                    0x4 => self.op_8XY4(get_x(opcode), get_y(opcode)),
                    0x5 => self.op_8XY5(get_x(opcode), get_y(opcode)),
                    0x6 => self.op_8XY6(get_x(opcode), get_y(opcode)),
                    0x7 => self.op_8XY7(get_x(opcode), get_y(opcode)),
                    0xE => self.op_8XYE(get_x(opcode), get_y(opcode)),
                    else => @panic("Unknown instruction!"),
                }
            },
            0x9 => {
                if((opcode & 0xF) == 0){
                    self.op_9XY0(get_x(opcode), get_y(opcode));
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