const std = @import("std");
const random = std.crypto.random;
const Stack = std.ArrayList(u16);

/// This is the default font found on Tobias' guide.
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

/// An enum for the possible key presses.
pub const Key = enum(u8){
    Zero = 0,
    One = 1,
    Two = 2,
    Three = 3,
    Four = 4,
    Five = 5,
    Six = 6,
    Seven = 7,
    Eight = 8,
    Nine = 9,
    A = 0xA,
    B = 0xB,
    C = 0xC,
    D = 0xD,
    E = 0xE,
    F = 0xF,
};

pub const ExecuteError = error {
    UnknownInstruction,
    Unsupported0x0NNN
};

/// The main structure for Chip8 emulation.
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
        current_key_pressed: ?Key,
    },

    configuration: struct {
        shift_operations_sets_ry_into_rx: bool,
        bnnn_is_bxnn: bool,
    },

    /// Inits a ChipZ structure with sensible defaults.
    /// Namely, it inits the memory to and display to 0, prepares the stack
    /// It sets then the default font using set_font.
    pub fn init(allocator: std.mem.Allocator) ChipZ {
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
                .display_update = false,
                .current_key_pressed = null,
            },
            .configuration = .{
                .shift_operations_sets_ry_into_rx = false,
                .bnnn_is_bxnn = false
            }
        };

        chip.set_font(default_font);

        return chip;
    }

    /// Loads a program in memory, starting at address 0x200.
    pub fn load_program(self: *ChipZ, program: []u8) void {
        for(program) |byte, index| {
            self.memory[index+0x200] = byte;
        }
        self.program_counter = 0x200;
    }

    /// Cleanups the structure
    pub fn deinit(self: *ChipZ) void {
        self.stack.deinit();
    }

    /// quick tool for operation parameter type address.
    fn get_address(opcode: u16) u12 {
        return @intCast(u12 ,opcode & 0xFFF);
    }

    /// quick tool for operation parameter type 8 bit constant as the last byte.
    fn get_8bitconstant(opcode: u16) u8 {
        return @intCast(u8 ,opcode & 0xFF);
    }

    /// quick tool for operation parameter type 4 bit constant as the last nibble.
    fn get_4bitconstant(opcode: u16) u4 {
        return @intCast(u4 ,opcode & 0xF);
    }

    /// quick tool for operation parameter type "x", the second nibble.
    fn get_x(opcode: u16) u4 {
        return @intCast(u4 ,(opcode & 0x0F00) >> 8);
    }

    /// quick tool for operation parameter type "y", the third nibble.
    fn get_y(opcode: u16) u4 {
        return @intCast(u4 ,(opcode & 0x00F0) >> 4);
    }

    /// sets the spedified font at index 0x50 
    pub fn set_font(self: *ChipZ, font: [16*5]u8) void {
        for (font) |byte, index| {
            self.memory[index+0x50] = byte;
        }
    }

    /// Cycles and executes the next instruction.
    /// This is what makes the emulation run.
    /// If a display operation has been executed, the flag "display_update" will be set.
    /// This allows updating the display only when necessary.
    pub fn cycle(self: *ChipZ) !void {
        self.flags.display_update = false;
        try self.decode_and_execute(self.fetch());
    }

    /// Fetches the next instruction and moves the program counter by 2.
    /// The use of defer is absolutely unecessary here, except if, like me, you enjoy having the return value at the end.
    fn fetch(self: *ChipZ) u16 {
        defer self.program_counter += 2;
        return (@intCast(u16, self.memory[self.program_counter]) << 8) + self.memory[self.program_counter+1];
    }

    // All functions starting with op_ are individual operations.
    // Some comments are directly from Tobias' guide.

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
        self.stack.append(self.program_counter) catch @panic("Error on pushing on stack");
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
        _ = @subWithOverflow(u8, self.registers[x], self.registers[y], &self.registers[x]);
        self.registers[0xF] = if(self.registers[x] > self.registers[y])  0 else 1;
    }

    /// sets VX to the result of VY - VX.
    /// This subtraction will also affect the carry flag, but note that it’s opposite from what you might think.
    /// If the minuend (the first operand) is larger than the subtrahend (second operand), VF will be set to 1.
    /// If the subtrahend is larger, and we “underflow” the result, VF is set to 0.
    /// Another way of thinking of it is that VF is set to 1 before the subtraction, and then the subtraction either borrows from VF (setting it to 0) or not.
    fn op_8XY7(self: *ChipZ, x: u4, y: u4) void {
        _ = @subWithOverflow(u8, self.registers[y], self.registers[x], &self.registers[x]);
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

    /// BNNN: Jump with offset
    fn op_BNNN(self: *ChipZ, opcode: u16) void {
        if(self.configuration.bnnn_is_bxnn){
            const address = get_8bitconstant(opcode);
            const x = get_x(opcode);

            self.program_counter = address + self.registers[x];
        }
        else
        {
            const address = get_address(opcode);
            self.program_counter = address + self.registers[0];
        }
    }

    /// This instruction generates a random number, binary ANDs it with the value NN, and puts the result in VX.
    fn op_CXNN(self: *ChipZ, x: u4, value: u8) void {
        const rand = random.int(u8);
        self.registers[x] = rand & value;
    }

    /// EX9E will skip one instruction (increment PC by 2) if the key corresponding to the value in VX is pressed.
    fn op_EX9E(self: *ChipZ, x: u4) void {
        if(self.flags.current_key_pressed) |key| {
            if(@enumToInt(key) == self.registers[x])
            {
                self.program_counter += 2;
            }
        }
    }

    /// EXA1 skips if the key corresponding to the value in VX is not pressed.
    fn op_EXA1(self: *ChipZ, x: u4) void {
        if(self.flags.current_key_pressed) |key| {
            if(@enumToInt(key) != self.registers[x])
            {
                self.program_counter += 2;
            }
        }
        else
        {
            self.program_counter += 2;
        }
    }

    /// FX07 sets VX to the current value of the delay timer
    fn op_FX07(self: *ChipZ, x: u4) void {
        self.registers[x] = self.timer_delay;
    }

    /// FX15 sets the delay timer to the value in VX
    fn op_FX15(self: *ChipZ, x: u4) void {
        self.timer_delay = self.registers[x];
    }

    /// FX18 sets the sound timer to the value in VX
    fn op_FX18(self: *ChipZ, x: u4) void {
        self.timer_sound = self.registers[x];
    }

    /// The index register I will get the value in VX added to it.
    fn op_FX1E(self: *ChipZ, x: u4) void {
        self.index_register = self.index_register + self.registers[x];
        if(self.index_register > 0xFFF) {
            self.registers[0xF] = 1;
            self.index_register &= 0xFFF;
        }
    }

    /// FX0A: Get key
    /// This instruction “blocks”; it stops execution and waits for key input.
    /// In other words, if you followed my advice earlier and increment PC after fetching each instruction, then it should be decremented again here unless a key is pressed.
    /// Otherwise, PC should simply not be incremented.
    /// If a key is pressed while this instruction is waiting for input, its hexadecimal value will be put in VX and execution continues.
    fn op_FX0A(self: *ChipZ, x: u4) void {
        if(self.flags.current_key_pressed) |key| {
            self.registers[x] = @enumToInt(key);
        }
        else
        {
            self.program_counter -= 2;
        }
    }

    /// The index register I is set to the address of the hexadecimal character in VX
    fn op_FX29(self: *ChipZ, x: u4) void {
        const value = self.registers[x] & 0xF;
        self.index_register = 0x50 + (value * 5);
    }

    /// BCD conversion
    fn op_FX33(self: *ChipZ, x: u4) void {
        var value = self.registers[x];
        self.memory[self.index_register] = @divFloor(value, 100);
        self.memory[self.index_register + 1] = @divFloor(value, 10) % 10;
        self.memory[self.index_register + 2] = value % 10;
    }

    /// store in memory
    fn op_FX55(self: *ChipZ, x: u4) void {
        var index : usize = 0;
        while (index <= x) : (index += 1) {
            self.memory[self.index_register+index] = self.registers[index];
        }
    }

    /// load from memory
    fn op_FX65(self: *ChipZ, x: u4) void {
        var index : usize = 0;
        while (index <= x) : (index += 1) {
            self.registers[index] = self.memory[self.index_register+index];
        }
    }

    /// Simple structure to decode a 2-byte instruction into potential parameters.
    const OpDetails = struct {
        opcode : u4,
        x: u4,
        y: u4,
        n: u4,
        nn: u8,
        address: u12,

        fn get(opcode: u16) OpDetails {
            return OpDetails {
                .opcode = @intCast(u4, (opcode & 0xF000) >> 12),
                .x = get_x(opcode),
                .y = get_y(opcode),
                .n = get_4bitconstant(opcode),
                .nn = get_8bitconstant(opcode),
                .address = get_address(opcode)
            };
        }
    };

    /// Decodes the instruction, finds the appropriate function and execute it.
    fn decode_and_execute(self: *ChipZ, opcode: u16) !void {
        errdefer std.log.err("Faulting instruction {x} at program counter value {x}", .{opcode, self.program_counter});
        const op = OpDetails.get(opcode);
        switch(op.opcode) {
            0x0 => {
                switch(opcode) {
                    0x00E0 => self.op_00E0(),
                    0x00EE => self.op_00EE(),
                    else => {
                        return ExecuteError.Unsupported0x0NNN; // Calls machine code routine (RCA 1802 for COSMAC VIP) at address NNN. Not necessary for most ROMs.
                    }
                }
            },
            0x1 => self.op_1NNN(op.address),
            0x2 => self.op_2NNN(op.address),
            0x3 => self.op_3XNN(op.x, op.nn),
            0x4 => self.op_4XNN(op.x, op.nn),
            0x5 => {
                if((opcode & 0xF) == 0){
                    self.op_5XY0(op.x, op.y);
                }
                else return ExecuteError.UnknownInstruction;
            },
            0x6 => self.op_6XNN(op.x, op.nn),
            0x7 => self.op_7XNN(op.x, op.nn),
            0x8 => {
                const last_nibble : u4 = @intCast(u4, opcode & 0xF);
                switch (last_nibble) {
                    0x0 => self.op_8XY0(op.x, op.y),
                    0x1 => self.op_8XY1(op.x, op.y),
                    0x2 => self.op_8XY2(op.x, op.y),
                    0x3 => self.op_8XY3(op.x, op.y),
                    0x4 => self.op_8XY4(op.x, op.y),
                    0x5 => self.op_8XY5(op.x, op.y),
                    0x6 => self.op_8XY6(op.x, op.y),
                    0x7 => self.op_8XY7(op.x, op.y),
                    0xE => self.op_8XYE(op.x, op.y),
                    else => return ExecuteError.UnknownInstruction,
                }
            },
            0x9 => {
                if((opcode & 0xF) == 0){
                    self.op_9XY0(op.x, op.y);
                }
                else return ExecuteError.UnknownInstruction;
            },
            0xA => self.op_ANNN(op.address),
            0xB => self.op_BNNN(opcode),
            0xC => self.op_CXNN(op.x, op.nn),
            0xD => self.op_DXYN(op.x, op.y, op.n),
            0xE => {
                const last_byte : u8 = @intCast(u8, opcode & 0xFF);
                switch (last_byte) {
                    0x9E => self.op_EX9E(op.x),
                    0xA1 => self.op_EXA1(op.x),
                    else => return ExecuteError.UnknownInstruction,
                }
            },
            0xF => {
                switch (op.nn) {
                    0x07 => self.op_FX07(op.x),
                    0x0A => self.op_FX0A(op.x),
                    0x15 => self.op_FX15(op.x),
                    0x18 => self.op_FX18(op.x),
                    0x1E => self.op_FX1E(op.x),
                    0x29 => self.op_FX29(op.x),
                    0x33 => self.op_FX33(op.x),
                    0x55 => self.op_FX55(op.x),
                    0x65 => self.op_FX65(op.x),
                    else => return ExecuteError.UnknownInstruction,
                }
            },
        }
    }
};