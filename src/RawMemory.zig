

// mapper.write16(0xFFFC, 0xFF00);
// mapper.blit(0xFF00, &.{
//     0x18, 0xA2, 0xFF, 0xA9, 0xBA, 0xE9, 0xBB, 0x90,
//     0x02, 0xA2, 0x00, 0x4C, 0x0B, 0xFF, 0x00, 0x00,
// });

const std = @import("std");
const Core = @import("Core.zig");

const Interface = Core.Interface;

mem: *[0x10000]u8,

interface: Interface,

pub fn init(mem: *[0x10000]u8) @This() {
	return .{
		.mem = mem,
		.interface = .{
			.mem_read = read_fn,
			.mem_write = write_fn,
		},
	};
}

fn read_fn(interface: *Interface, addr: u16) u8 {
	const self: *@This() = @fieldParentPtr("interface", interface);
	return self.mem[addr];
}

fn write_fn(interface: *Interface, addr: u16, val: u8) void {
	const self: *@This() = @fieldParentPtr("interface", interface);
	self.mem[addr] = val;
}

pub fn write16(self: *const @This(), addr: u16, val: u16) void {
	self.mem[addr] = @truncate(val);
	self.mem[addr+1] = @truncate(val >> 8);
}

pub fn blit(self: *const @This(), start_addr: u16, content: []const u8) void {
	@memcpy(self.mem[start_addr..start_addr+content.len], content);
}

