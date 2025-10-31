
const std = @import("std");

const Operand        = @import("common.zig").Operand;
const Opcode         = @import("common.zig").Opcode;
const AddressingMode = @import("common.zig").AddressingMode;
const Instruction    = @import("common.zig").Instruction;

state: struct {
	// TODO: consider separating ISA state (e.g. the registers) from the microarch state (e.g. nmi_latch)
	accumulator: u8,
	x_index: u8,
	y_index: u8,
	stack_pointer: u8,
	program_counter: u16,

	flags: packed struct(u8) {
		carry: bool,
		zero: bool,
		interrupt: bool,
		decimal: bool,
		b_flag: bool = undefined,
		unused: bool = true,
		overflow: bool,
		negative: bool,
	},

	nmi_queued: bool = false,
	irq_active: bool = false,

	pub fn format(
		self: @This(),
		writer: anytype,
	) !void {

		const fmt =
			\\6502 state:
			\\  A:    0x{X:0>2} ({})
			\\  X:    0x{X:0>2} ({})
			\\  Y:    0x{X:0>2} ({})
			\\  S:  0x{X:0>4}
			\\  PC: 0x{X:0>4}
			\\  P:    0x{X:0>2}:
			\\    N: {}
			\\    V: {}
			\\    -: {}
			\\    B: {}
			\\    D: {}
			\\    I: {}
			\\    Z: {}
			\\    C: {}
			\\  u-arch:
			\\    NMI queued: {}
			\\    IRQ active: {}
		;
		try writer.print(fmt, .{
			self.accumulator, self.accumulator,
			self.x_index,     self.x_index,
			self.y_index,     self.y_index,

			@as(u16, self.stack_pointer) | 0x0100,
			self.program_counter,

			@as(u8, @bitCast(self.flags)),
				self.flags.negative,
				self.flags.overflow,
				self.flags.unused,
				self.flags.b_flag,
				self.flags.decimal,
				self.flags.interrupt,
				self.flags.zero,
				self.flags.carry,

			self.nmi_queued,
			self.irq_active,
		});
	}
},
interface: *Interface,

pub const Interface = struct {
	mem_read:  *const fn (*@This(), u16) u8,
	mem_write: *const fn (*@This(), u16, u8) void,
};


const decode_map: [256]?struct{Opcode, AddressingMode} = .{
	.{.BRK, .implied   }, .{.ORA, .x_indexed_indirect},       null         , null,             null             , .{.ORA, .zeropage           }, .{.ASL, .zeropage           }, null, .{.PHP, .implied}, .{.ORA, .immediate          }, .{.ASL, .accumulator      }, null,             null             , .{.ORA, .absolute           }, .{.ASL, .absolute           }, null,
	.{.BPL, .relative  }, .{.ORA, .indirect_y_indexed},       null         , null,             null             , .{.ORA, .zeropage_x_indexed }, .{.ASL, .zeropage_x_indexed }, null, .{.CLC, .implied}, .{.ORA, .absolute_y_indexed },          null              , null,             null             , .{.ORA, .absolute_x_indexed }, .{.ASL, .absolute_x_indexed }, null,
	.{.JSR, .absolute  }, .{.AND, .x_indexed_indirect},       null         , null, .{.BIT, .zeropage           }, .{.AND, .zeropage           }, .{.ROL, .zeropage           }, null, .{.PLP, .implied}, .{.AND, .immediate          }, .{.ROL, .accumulator      }, null, .{.BIT, .absolute           }, .{.AND, .absolute           }, .{.ROL, .absolute           }, null,
	.{.BMI, .relative  }, .{.AND, .indirect_y_indexed},       null         , null,             null             , .{.AND, .zeropage_x_indexed }, .{.ROL, .zeropage_x_indexed }, null, .{.SEC, .implied}, .{.AND, .absolute_y_indexed },          null              , null,             null             , .{.AND, .absolute_x_indexed }, .{.ROL, .absolute_x_indexed }, null,
	.{.RTI, .implied   }, .{.EOR, .x_indexed_indirect},       null         , null,             null             , .{.EOR, .zeropage           }, .{.LSR, .zeropage           }, null, .{.PHA, .implied}, .{.EOR, .immediate          }, .{.LSR, .accumulator      }, null, .{.JMP, .absolute           }, .{.EOR, .absolute           }, .{.LSR, .absolute           }, null,
	.{.BVC, .relative  }, .{.EOR, .indirect_y_indexed},       null         , null,             null             , .{.EOR, .zeropage_x_indexed }, .{.LSR, .zeropage_x_indexed }, null, .{.CLI, .implied}, .{.EOR, .absolute_y_indexed },          null              , null,             null             , .{.EOR, .absolute_x_indexed }, .{.LSR, .absolute_x_indexed }, null,
	.{.RTS, .implied   }, .{.ADC, .x_indexed_indirect},       null         , null,             null             , .{.ADC, .zeropage           }, .{.ROR, .zeropage           }, null, .{.PLA, .implied}, .{.ADC, .immediate          }, .{.ROR, .accumulator      }, null, .{.JMP, .indirect           }, .{.ADC, .absolute           }, .{.ROR, .absolute           }, null,
	.{.BVS, .relative  }, .{.ADC, .indirect_y_indexed},       null         , null,             null             , .{.ADC, .zeropage_x_indexed }, .{.ROR, .zeropage_x_indexed }, null, .{.SEI, .implied}, .{.ADC, .absolute_y_indexed },          null              , null,             null             , .{.ADC, .absolute_x_indexed }, .{.ROR, .absolute_x_indexed }, null,
	       null         , .{.STA, .x_indexed_indirect},       null         , null, .{.STY, .zeropage           }, .{.STA, .zeropage           }, .{.STX, .zeropage           }, null, .{.DEY, .implied},             null             , .{.TXA, .implied          }, null, .{.STY, .absolute           }, .{.STA, .absolute           }, .{.STX, .absolute           }, null,
	.{.BCC, .relative  }, .{.STA, .indirect_y_indexed},       null         , null, .{.STY, .zeropage_x_indexed }, .{.STA, .zeropage_x_indexed }, .{.STX, .zeropage_y_indexed }, null, .{.TYA, .implied}, .{.STA, .absolute_y_indexed }, .{.TXS, .implied          }, null,             null             , .{.STA, .absolute_x_indexed },         null                 , null,
	.{.LDY, .immediate }, .{.LDA, .x_indexed_indirect}, .{.LDX, .immediate}, null, .{.LDY, .zeropage           }, .{.LDA, .zeropage           }, .{.LDX, .zeropage           }, null, .{.TAY, .implied}, .{.LDA, .immediate          }, .{.TAX, .implied          }, null, .{.LDY, .absolute           }, .{.LDA, .absolute           }, .{.LDX, .absolute           }, null,
	.{.BCS, .relative  }, .{.LDA, .indirect_y_indexed},       null         , null, .{.LDY, .zeropage_x_indexed }, .{.LDA, .zeropage_x_indexed }, .{.LDX, .zeropage_y_indexed }, null, .{.CLV, .implied}, .{.LDA, .absolute_y_indexed }, .{.TSX, .implied          }, null, .{.LDY, .absolute_x_indexed }, .{.LDA, .absolute_x_indexed }, .{.LDX, .absolute_y_indexed }, null,
	.{.CPY, .immediate }, .{.CMP, .x_indexed_indirect},       null         , null, .{.CPY, .zeropage           }, .{.CMP, .zeropage           }, .{.DEC, .zeropage           }, null, .{.INY, .implied}, .{.CMP, .immediate          }, .{.DEX, .implied          }, null, .{.CPY, .absolute           }, .{.CMP, .absolute           }, .{.DEC, .absolute           }, null,
	.{.BNE, .relative  }, .{.CMP, .indirect_y_indexed},       null         , null,             null             , .{.CMP, .zeropage_x_indexed }, .{.DEC, .zeropage_x_indexed }, null, .{.CLD, .implied}, .{.CMP, .absolute_y_indexed },          null              , null,             null             , .{.CMP, .absolute_x_indexed }, .{.DEC, .absolute_x_indexed }, null,
	.{.CPX, .immediate }, .{.SBC, .x_indexed_indirect},       null         , null, .{.CPX, .zeropage           }, .{.SBC, .zeropage           }, .{.INC, .zeropage           }, null, .{.INX, .implied}, .{.SBC, .immediate          }, .{.NOP, .implied          }, null, .{.CPX, .absolute           }, .{.SBC, .absolute           }, .{.INC, .absolute           }, null,
	.{.BEQ, .relative  }, .{.SBC, .indirect_y_indexed},       null         , null,             null             , .{.SBC, .zeropage_x_indexed }, .{.INC, .zeropage_x_indexed }, null, .{.SED, .implied}, .{.SBC, .absolute_y_indexed },          null              , null,             null             , .{.SBC, .absolute_x_indexed }, .{.INC, .absolute_x_indexed }, null,
};

inline fn memory_read(self: *const @This(), addr: u16) u8 { return self.interface.mem_read(self.interface, addr); }
inline fn memory_write(self: *const @This(), addr: u16, val: u8) void { return self.interface.mem_write(self.interface, addr, val); }

fn memory_read16(self: *const @This(), addr: u16) u16 {
	const lower: u16 = self.memory_read(addr + 0);
	const upper: u16 = self.memory_read(addr + 1);

	return (upper << 8) | lower;
}

fn next_operand(self: *@This(), mode: AddressingMode) Operand {
	const OperandSize = enum { none, one, two };

	const ip = self.state.program_counter;
	switch (mode) {
		inline else => |v| {
			const size: OperandSize = switch (comptime v) {
				.accumulator        => .none,
				.absolute           => .two,
				.absolute_x_indexed => .two,
				.absolute_y_indexed => .two,
				.immediate          => .one,
				.implied            => .none,
				.indirect           => .two,
				.x_indexed_indirect => .one,
				.indirect_y_indexed => .one,
				.relative           => .one,
				.zeropage           => .one,
				.zeropage_x_indexed => .one,
				.zeropage_y_indexed => .one,
			};

			switch (comptime size) {
				.none => {},
				.one  => self.state.program_counter += 1,
				.two  => self.state.program_counter += 2,
			}

			return switch (comptime size) {
				.none => v,
				.two  => @unionInit(Operand, @tagName(v), @bitCast(self.memory_read16(ip))),
				.one  => @unionInit(Operand, @tagName(v), @bitCast(self.memory_read(ip))),
			};
		}
	}
}

fn next_instruction(self: *@This()) !Instruction {
	const ip = self.state.program_counter; self.state.program_counter += 1;
	const opc = self.memory_read(ip);

	const opcode, const addressing_mode = decode_map[opc] orelse return error.DecodeFailed;

	const operand = self.next_operand(addressing_mode);

	return .{ opcode, operand };
}

pub fn reset(self: *@This()) void {
	self.state.nmi_queued = false; // TODO: check if there is no better way to handle this
	self.state.irq_active = false; // TODO: check if there is no better way to handle this
	self.state.program_counter = self.memory_read16(0xFFFC);
}


fn get_effective_address(self: *const @This(), operand: Operand) u16 {
	return switch (operand) {
		.absolute => |v| v,
		.absolute_x_indexed => |v| v + self.state.x_index,
		.absolute_y_indexed => |v| v + self.state.y_index,
		.indirect => |v| self.memory_read16(v),
		.x_indexed_indirect => |v| self.memory_read16(@as(u16, v) + self.state.x_index), // TODO: find out if ($ff,x) with x=0xff overflows out of zeropage
		.indirect_y_indexed => |v| self.memory_read16(v) + self.state.y_index, // TODO: Again like above, does add wrap in page
		.relative => |v| self.state.program_counter +% @as(u16, @bitCast(@as(i16, v))), // TODO: program counter likely should be offset // TODO: we're adding a signed number to an unsigned number. zig might not like
		.zeropage => |v| @as(u16, v),
		.zeropage_x_indexed => |v| @as(u16, v + self.state.x_index), // TODO: check that overflow is handled correctly
		.zeropage_y_indexed => |v| @as(u16, v + self.state.y_index), // TODO: check that overflow is handled correctly

		.accumulator, .implied, .immediate => unreachable, // these do not have effective addresses
	};
}

fn read_operand(self: *const @This(), operand: Operand) u8 {
	return switch (operand) {
		.accumulator => self.state.accumulator,
		.immediate => |v| v,
		.implied => unreachable, // these are to be handled on an instruction by instruction basis

		else => self.memory_read(self.get_effective_address(operand)),
	};
}

fn write_operand(self: *@This(), operand: Operand, val: u8) void {
	switch (operand) {
		.accumulator => self.state.accumulator = val,
		.implied => unreachable, // these are to be handled on an instruction by instruction basis
		.immediate => unreachable, // cannot write an immediate

		else => self.memory_write(self.get_effective_address(operand), val),
	}
}

// TODO: candidate for inlining
fn cond_jmp(self: *@This(), cond: bool, operand: Operand) void {
	if (cond) self.state.program_counter = self.get_effective_address(operand);
}

// TODO: candidate for inlining
fn set_nz_from(self: *@This(), val: u8) void {
	self.state.flags.negative = val >= 0x80;
	self.state.flags.zero = val == 0;
}

// TODO: candidate for inlining
fn push8(self: *@This(), val: u8) void {
	const addr = @as(u16, self.state.stack_pointer) | 0x0100;
	self.memory_write(addr, val);
	self.state.stack_pointer +%= 1;
}

// TODO: candidate for inlining
fn pull8(self: *@This()) u8 {
	self.state.stack_pointer -%= 1;
	const addr = @as(u16, self.state.stack_pointer) | 0x0100;
	return self.memory_read(addr);
}

// TODO: candidate for inlining
fn push16(self: *@This(), val: u16) void {
	self.push8(@truncate(val));
	self.push8(@truncate(val>>8));
	// TODO: if the stack pointer is at 0x01FF,
	//       do the 2 bytes get put in the same page?
}

// TODO: candidate for inlining
fn pull16(self: *@This()) u16 {
	const upper: u16 = self.pull8();
	const lower: u16 = self.pull8();
	return (upper << 8) | lower;
}


inline fn donz(self: *@This(), val: u8) u8 {
	self.set_nz_from(val);
	return val;
}
inline fn fanz(self: *@This()) void {
	self.set_nz_from(self.state.accumulator);
}

fn run_instruction(self: *@This(), instr: Instruction) void {
	const opcode, const operand = instr;
	switch (opcode) {
		.BEQ => self.cond_jmp( self.state.flags.zero    , operand),
		.BCS => self.cond_jmp( self.state.flags.carry   , operand),
		.BMI => self.cond_jmp( self.state.flags.negative, operand),
		.BVS => self.cond_jmp( self.state.flags.overflow, operand),
		.BNE => self.cond_jmp(!self.state.flags.zero    , operand),
		.BCC => self.cond_jmp(!self.state.flags.carry   , operand),
		.BPL => self.cond_jmp(!self.state.flags.negative, operand),
		.BVC => self.cond_jmp(!self.state.flags.overflow, operand),

		.JMP => self.cond_jmp(true, operand),

		.SEC => self.state.flags.carry     = true,
		.SED => self.state.flags.decimal   = true,
		.SEI => self.state.flags.interrupt = true,
		.CLC => self.state.flags.carry     = false,
		.CLD => self.state.flags.decimal   = false,
		.CLV => self.state.flags.overflow  = false,
		.CLI => self.state.flags.interrupt = false,

		.STA => self.write_operand(operand, self.state.accumulator),
		.STX => self.write_operand(operand, self.state.x_index),
		.STY => self.write_operand(operand, self.state.y_index),
		//.TXS => self.state.stack_pointer = self.state.x_index,

		.LDA => self.state.accumulator = self.donz(self.read_operand(operand)),
		.LDX => self.state.x_index = self.donz(self.read_operand(operand)),
		.LDY => self.state.y_index = self.donz(self.read_operand(operand)),

		.EOR => { self.state.accumulator ^= self.read_operand(operand); self.fanz(); },
		.ORA => { self.state.accumulator |= self.read_operand(operand); self.fanz(); },
		.AND => { self.state.accumulator &= self.read_operand(operand); self.fanz(); },

		.INX => { self.state.x_index +%= 1; self.set_nz_from(self.state.x_index); },
		.INY => { self.state.y_index +%= 1; self.set_nz_from(self.state.y_index); },
		.DEX => { self.state.x_index -%= 1; self.set_nz_from(self.state.x_index); },
		.DEY => { self.state.y_index -%= 1; self.set_nz_from(self.state.y_index); },

		.PHA => self.push8(self.state.accumulator),
		.PLA => self.state.accumulator = self.pull8(),

		.TAX => self.state.x_index = self.donz(self.state.accumulator),
		.TAY => self.state.y_index = self.donz(self.state.accumulator),
		.TSX => self.state.x_index = self.donz(self.state.stack_pointer),
		.TXS => {
			const r = self.state.x_index;
			//self.set_nz_from(r); // TODO: masswerk says this isn't done. Verify
			self.state.stack_pointer = r;
		},
		.TXA => self.state.accumulator = self.donz(self.state.x_index),
		.TYA => self.state.accumulator = self.donz(self.state.y_index),

		.ADC => {
			const a = self.state.accumulator;
			const m = self.read_operand(operand);

			const i, const c1 = @addWithOverflow(a, m);
			const r, const c2 = if (self.state.flags.carry) @addWithOverflow(i, 1) else .{ i, 0 };
			// TODO: maybe there's a way in only one @addWIthOverflow?

			const c = (c1 > 0) or (c2 > 0); // new carry
			const v = if (a ^ m < 0x80) a ^ r >= 0x80 else false; // new overflow
			// TODO: Check whether the overflow calculation is correct

			self.set_nz_from(r);
			self.state.flags.carry = c;
			self.state.flags.overflow = v;

			self.state.accumulator = r;
		},
		.SBC => {
			const a = self.state.accumulator;
			const m = self.read_operand(operand);

			const i, const c1 = @subWithOverflow(a, m);
			const r, const c2 = if (!self.state.flags.carry) @subWithOverflow(i, 1) else .{ i, 0 }; // TODO: masswerk implies that the carry flag is inverted, but that seems wrong to me
			// TODO: maybe there's a way in only one @addWIthOverflow?

			const c = (c1 > 0) or (c2 > 0); // new carry
			const v = if (a ^ m < 0x80) a ^ r >= 0x80 else false; // new overflow
			// TODO: Check whether the overflow calculation is correct

			self.set_nz_from(r);
			self.state.flags.carry = !c;
			self.state.flags.overflow = v;
			self.state.accumulator = r;
		},
		.CMP => {
			// C  Carry Flag         Set if A >= M
			// Z  Zero Flag          Set if A = M
			// I  Interrupt Disable  Not affected
			// D  Decimal Mode Flag  Not affected
			// B  Break Command      Not affected
			// V  Overflow Flag      Not affected
			// N  Negative Flag      Set if bit 7 of the result is set

			//std.debug.print("-- CMP --\n", .{});
			//std.debug.print("{f}\n", .{self.state});
			//std.debug.print("{}\n", .{operand});
			const a = self.state.accumulator;
			const m = self.read_operand(operand);

			const r, const c = @subWithOverflow(a, m);

			self.set_nz_from(r);
			self.state.flags.carry = c == 0;
			//std.debug.print("{f}\n", .{self.state});
		},
		.CPX => {
			const a = self.state.x_index;
			const m = self.read_operand(operand);

			const r, const c = @subWithOverflow(a, m);

			self.set_nz_from(r);
			self.state.flags.carry = c > 0;
		},
		.CPY => {
			const a = self.state.y_index;
			const m = self.read_operand(operand);

			const r, const c = @subWithOverflow(a, m);

			self.set_nz_from(r);
			self.state.flags.carry = c > 0;
		},

		.INC => {
			const r = self.read_operand(operand) +% 1;
			self.set_nz_from(r);
			self.write_operand(operand, r);
		},

		.JSR => {
			self.push16(self.state.program_counter);
			self.state.program_counter = self.get_effective_address(operand);
			// TODO: check whether the pushed address matches
			//       chances are, that the pushed address should be one less
		},
		.RTS => self.state.program_counter = self.pull16(),

		.BIT => {
			const m = self.read_operand(operand);
			const r = self.state.accumulator & m;

			self.state.flags.negative = m >= 0x80;
			self.state.flags.zero = r == 0;
			self.state.flags.overflow = (m & 0x40) != 0;
			// TODO: the description of bit is rather confusing. check if the implementation is correct
		},


		.ASL => {
			const orig = self.read_operand(operand);
			const r, const c = @shlWithOverflow(orig, 1);
			self.set_nz_from(r);
			self.state.flags.carry = c > 0;
			self.write_operand(operand, r);
		},
		.ROL => {
			const orig = self.read_operand(operand);
			const i, const c = @shlWithOverflow(orig, 1);
			const r = i | @as(u8, if (self.state.flags.carry) 0x01 else 0x00);
			self.set_nz_from(r);
			self.state.flags.carry = c > 0;
			self.write_operand(operand, r);
		},
		.LSR => {
			const orig = self.read_operand(operand);
			const r = orig >> 1;
			self.set_nz_from(r);
			self.state.flags.carry = (orig & 0x01) != 0;
			self.write_operand(operand, r);
		},

		.RTI => {
			self.pull_sr();
			self.state.program_counter = self.pull16();
		},

		else => |i| {
			std.debug.print("!!! UNIMPLEMENTED INSTRUCTION: {s}\n", .{@tagName(i)});
			unreachable;
		},
	}
}


pub inline fn trigger_nmi(self: *@This()) void {
	self.state.nmi_queued = true;
}

// TODO: candidate for inlining
fn push_sr(self: *@This(), b_flag: bool) void {
	var flags = self.state.flags;
	flags.b_flag = b_flag; // TODO: verify that the implementation of the B-flag is correct

	const as_byte: u8 = @bitCast(flags);
	self.push8(as_byte);
}

// TODO: candidate for inlining
fn pull_sr(self: *@This()) void {
	const as_byte: u8 = self.pull8();
	self.state.flags = @bitCast(as_byte);

	// TODO: verify that the b-flag has no influence on popping
}

// TODO: candidate for inlining
fn enter_interrupt(self: *@This(), is_nmi: bool) void {
	self.push16(self.state.program_counter);
	self.push_sr(undefined); // TODO: figure out what to do here with the B-flag
	self.state.flags.interrupt = true;
	self.state.program_counter = self.memory_read16(if (is_nmi) 0xFFFA else 0xFFFE);
}

pub fn step_1_instruction(self: *@This()) !void {
	if (self.state.nmi_queued) {
		std.debug.print("doing nmi\n", .{});

		self.enter_interrupt(true);
		self.state.nmi_queued = false;

	} else if (self.state.irq_active and !self.state.flags.interrupt) {
		self.enter_interrupt(false);
	}


	const ip = self.state.program_counter;
	const instr = try self.next_instruction();
	//std.debug.print("running instr {} from 0x{X:0>4}\n", .{instr, ip});
	_ = ip;
	self.run_instruction(instr);
}





