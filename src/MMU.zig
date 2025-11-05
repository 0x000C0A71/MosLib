
const std = @import("std");
const Core = @import("Core.zig");

const Interface = Core.Interface;

// top 6 bits of core addr are page index
// 10 bits for different mapping tables
//   -> 16 bit lut inputs

const CorePageIndex = u6;
const TableId = u10;

const LutInput = packed struct(u16) {
	page_index: CorePageIndex,
	table_id: TableId,
};

const Perms = packed struct(u2) {
	read: bool,
	write: bool,
};

const MemPageIndex = u14;

pub const LutOutput = packed struct(u16) {
	page_index: MemPageIndex,
	perms: Perms
};

const MemAddress = packed struct(u24) {
	offset: u10,
	page_index: MemPageIndex,
};

const CoreAddress = packed struct(u16) {
	offset: u10,
	page_index: CorePageIndex,
};

lut: *[1<<@bitSizeOf(LutInput)]LutOutput,


active: TableId = 0,

lut_exposed: u16 = 0,

status: packed struct(u8) {
	is_priviledged: bool = true,
	is_bootrom: bool = true,
	unused: u6 = undefined,
} = .{},

last_attempted_write: u8,
last_attempted_write_addr: u16,

core: *Core,


core_interface: Core.Interface,

mem_interface: *MemInterface,

boot_rom: *const [0x100]u8,


pub fn init(lut: *[1<<@bitSizeOf(LutInput)]LutOutput, boot_rom: *const [0x100]u8, interface: *MemInterface) @This() {
	return .{
		.lut = lut,
		.core = undefined,
		.core_interface = .{
			.mem_read = core_read_fn,
			.mem_write = core_write_fn,
		},

		.last_attempted_write = undefined,
		.last_attempted_write_addr = undefined,

		.mem_interface = interface,
		.boot_rom = boot_rom,
		.status = .{},
	};
}

pub const MemInterface = struct {
	mem_read:  *const fn (*@This(), u24) u8,
	mem_write: *const fn (*@This(), u24, u8) void,
};


pub fn format(
	self: @This(),
	writer: anytype,
) !void {

	const fmt =
		\\MMU state:
		\\  active map: {}
		\\  exposed lut addr: 0x{X:0>4}
		\\  corresponding lut value: (0x{X:0>4})
		\\    mapped to: 0x{X} (+0x{X:0>6})
		\\    read allowed: {}
		\\    write allowed: {}
		\\  last attempted write: {} (0x{X:0>2}) at 0x{X:0>4}
		\\  status: (0x{X:0>2})
		\\    is_priviledged: {}
		\\    is_bootrom:     {}
	;
	const lut_res = self.lut[self.lut_exposed];

	try writer.print(fmt, .{
		self.active,
		self.lut_exposed,
		@as(u16, @bitCast(lut_res)),
			lut_res.page_index, @as(u24, lut_res.page_index) << 10,
			lut_res.perms.read,
			lut_res.perms.write,
		self.last_attempted_write, self.last_attempted_write, self.last_attempted_write_addr,
		@as(u8, @bitCast(self.status)),
			self.status.is_priviledged,
			self.status.is_bootrom,
	});
}


pub inline fn set_mapping(self: *@This(), table: TableId, page: CorePageIndex, to: LutOutput) void {
	const index: u16 = @bitCast(LutInput{ .page_index = page, .table_id = table });
	self.lut[index] = to;
}

pub fn load_table(self: *@This(), table: TableId, pages: [64]LutOutput) void {
	for (pages, 0..) |page, i| self.set_mapping(table, @intCast(i), page);
}

fn map_addr(self: *const @This(), addr: u16) struct { u24, Perms } {
	const split: CoreAddress = @bitCast(addr);
	const m_in = LutInput{
		.page_index =  split.page_index,
		.table_id = self.active,
	};

	const lutted = self.lut[@as(u16, @bitCast(m_in))];
	const mem_addr = MemAddress{
		.page_index = lutted.page_index,
		.offset = split.offset,
	};

	return .{ @bitCast(mem_addr), lutted.perms };
}


fn read_regs(self: *const @This(), offset: u4) u8 {
	// 0000 status
	// 0001 law_val    ( last attempted write           )
	// 0010 law_lo     ( last attempted write addr low  )
	// 0011 law_hi     ( last attempted write addr high )
	// 0100 lut_in_lo  ( writing an address here enables writing to that cell of the lut )
	// 0101 lut_in_hi  ( writing an address here enables writing to that cell of the lut )
	// 0110 lut_out_lo ( This mapps to the above selected cell of the lut                )
	// 0111 lut_out_hi ( This mapps to the above selected cell of the lut                )
	// 1000 active_lo  ( This marks which map the mmu will use to map rn                 )
	// 1001 active_hi  ( This marks which map the mmu will use to map rn                 )
	// 1010 active_lo  ( mirrored                                                        )
	// 1011 active_hi  ( mirrored                                                        )
	// 1100 active_lo  ( mirrored                                                        )
	// 1101 active_hi  ( mirrored                                                        )
	// 1110 active_lo  ( mirrored                                                        )
	// 1111 active_hi  ( mirrored                                                        )

	return switch (offset) {
		0b0000 => @bitCast(self.status),

		0b0001 => self.last_attempted_write,
		0b0010 => @truncate(@as(u16, self.last_attempted_write_addr)),
		0b0011 => @truncate(@as(u16, self.last_attempted_write_addr) >> 8),

		0b0100 => @truncate(@as(u16, self.lut_exposed)),
		0b0101 => @truncate(@as(u16, self.lut_exposed) >> 8),
		0b0110 => @truncate(@as(u16, @bitCast(self.lut[self.lut_exposed]))),
		0b0111 => @truncate(@as(u16, @bitCast(self.lut[self.lut_exposed])) >> 8),

		0b1000, 0b1010, 0b1100, 0b1110 => @truncate(@as(u16, self.active)),
		0b1001, 0b1011, 0b1101, 0b1111 => @truncate(@as(u16, self.active) >> 8),
	};
}

fn write_regs(self: *@This(), offset: u4, val: u8) void {
	// 0000 status
	// 0001 law_val    ( last attempted write           )
	// 0010 law_lo     ( last attempted write addr low  )
	// 0011 law_hi     ( last attempted write addr high )
	// 0100 lut_in_lo  ( writing an address here enables writing to that cell of the lut )
	// 0101 lut_in_hi  ( writing an address here enables writing to that cell of the lut )
	// 0110 lut_out_lo ( This mapps to the above selected cell of the lut                )
	// 0111 lut_out_hi ( This mapps to the above selected cell of the lut                )
	// 1000 active_lo  ( This marks which map the mmu will use to map rn                 )
	// 1001 active_hi  ( This marks which map the mmu will use to map rn                 )
	// 1010 active_lo  ( mirrored                                                        )
	// 1011 active_hi  ( mirrored                                                        )
	// 1100 active_lo  ( mirrored                                                        )
	// 1101 active_hi  ( mirrored                                                        )
	// 1110 active_lo  ( mirrored                                                        )
	// 1111 active_hi  ( mirrored                                                        )

	switch (offset) {
		0b0000 => self.status = @bitCast(val),
		0b0001 => self.last_attempted_write = val,
		0b0010 => {
			const old = @as(u16, self.last_attempted_write_addr) & 0xFF00;
			self.last_attempted_write_addr = @truncate(old | val);
		},
		0b0011 => {
			const old = @as(u16, self.last_attempted_write_addr) & 0x00FF;
			self.last_attempted_write_addr = @truncate(old | (@as(u16, val) << 8));
		},
		0b0100 => {
			const old = self.lut_exposed & 0xFF00;
			self.lut_exposed = @truncate(old | val);
		},
		0b0101 => {
			const old = self.lut_exposed & 0x00FF;
			self.lut_exposed = @truncate(old | (@as(u16, val) << 8));
		},
		0b0110 => {
			const old = @as(u16, @bitCast(self.lut[self.lut_exposed])) & 0xFF00;
			self.lut[self.lut_exposed] = @bitCast(old | val);
		},
		0b0111 => {
			const old = @as(u16, @bitCast(self.lut[self.lut_exposed])) & 0xFF00;
			self.lut[self.lut_exposed] = @bitCast(old | (@as(u16, val) << 8));
		},
		0b1000, 0b1010, 0b1100, 0b1110 => {
			const old = @as(u16, self.active) & 0xFF00;
			self.active = @truncate(old | val);
		},
		0b1001, 0b1011, 0b1101, 0b1111 => {
			const old = @as(u16, self.active) & 0x00FF;
			self.active = @truncate(old | (@as(u16, val) << 8));
		},
	}
}

fn internal_read(self: *const @This(), offset: u8) u8 {
	// all addresses that match $FFxx get mapped here

	// 111111110000xxxx passed through to regs (see read_regs and write_regs)
	// 11111111xxxxxxxx passed through to 0000000000000000xxxxxxxx or to bootroom depending on flag

	if ((offset & 0b11110000) == 0)	return self.read_regs(@truncate(offset));

	if (self.status.is_bootrom) {
		return self.boot_rom[offset];
	} else {
		return self.mem_interface.mem_read(self.mem_interface, offset);
	}
}

fn internal_write(self: *@This(), offset: u8, val: u8) void {
	// all addresses that match $FFxx get mapped here


	// 111111110000xxxx passed through to regs (see read_regs and write_regs)
	// 11111111xxxxxxxx passed through to 0000000000000000xxxxxxxx or to bootroom depending on flag


	if ((offset & 0b11110000) == 0)	self.write_regs(@truncate(offset), val);

	if (self.status.is_bootrom) {
		//return self.boot_rom[offset];
		std.debug.print("tried to write 0x{X:0>2} to rom+0x{X:0>2}\n", .{val, offset});
	} else {
		self.mem_interface.mem_write(self.mem_interface, offset, val);
	}
}

fn trip(self: *@This()) void {
	std.debug.print("trip!\n", .{});
	// oh-oh! someone doing something naughty!


	// TODO: here we have a problem. If an instruction does 2 writes,
	//       the first one will trip, and set it to priviledged, as it
	//       is now priviledged, the second will go through
	//
	//       one idea is to wait with teh priviledge escaltation until
	//       the nmi vector is read
	self.core.trigger_nmi();
	self.status.is_priviledged = true;

}


fn core_read_fn(interface: *Interface, addr: u16) u8 {
	const self: *@This() = @fieldParentPtr("core_interface", interface);

	if ((addr & 0xFF00) == 0xFF00) {
		return self.internal_read(@truncate(addr));
	}

	const out_addr, const perms = self.map_addr(addr);

	const is_legal = perms.read | self.status.is_priviledged;

	if (!is_legal) {
		self.trip();
		return 0x00;
	}

	return self.mem_interface.mem_read(self.mem_interface, out_addr);
}

fn core_write_fn(interface: *Interface, addr: u16, val: u8) void {
	const self: *@This() = @fieldParentPtr("core_interface", interface);

	if ((addr & 0xFF00) == 0xFF00) {
		if (!self.status.is_priviledged) {
			self.last_attempted_write = val;
			self.last_attempted_write_addr = addr;
			self.trip();
			return;
		}

		self.internal_write(@truncate(addr), val);
		return;
	}

	const out_addr, const perms = self.map_addr(addr);

	const is_legal = perms.write | self.status.is_priviledged;

	if (!is_legal) {
		self.last_attempted_write = 0;
		self.last_attempted_write_addr = addr;
		self.trip();
		return;
	}

	self.mem_interface.mem_write(self.mem_interface, out_addr, val);
}


pub fn blit_mapped(self: *@This(), under: TableId, start_addr: u16, content: []const u8) void {
	const old_active = self.active;
	defer self.active = old_active;

	self.active = under;
	for (content, start_addr..) |b, addr| {
		// I hope this enables the zig compiler to make the loop chunked...
		@call(.always_inline, @This().core_write_fn, .{&self.core_interface, @as(u16, @intCast(addr)), b});
	}
}


