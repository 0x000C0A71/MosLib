const std = @import("std");
const MosLib = @import("MosLib");


fn apple1_main() !void {

	var stdout_buffer: [1024]u8 = undefined;
	var stdin_buffer: [1024]u8 = undefined;

	var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
	const stdout = &stdout_writer.interface;

	const stdin_file = std.fs.File.stdin();
	var stdin_reader = stdin_file.reader(&stdin_buffer);
	const stdin = &stdin_reader.interface;

	// Make stdin non-blocking
	{
		const old_flags = try std.posix.fcntl(stdin_file.handle, std.c.F.GETFL, 0);
		_ = try std.posix.fcntl(stdin_file.handle, std.c.F.SETFL, old_flags | std.os.linux.IN.NONBLOCK);
	}

	// Make stdin non-line-buffered and non-echoing
	const old_term_settings = try std.posix.tcgetattr(stdin_file.handle);
	defer _ = std.posix.tcsetattr(stdin_file.handle, .NOW, old_term_settings) catch {};
	{
		var new_term_settings = old_term_settings;
		new_term_settings.lflag.ICANON = false;
		new_term_settings.lflag.ECHO = false;
		_ = std.posix.tcsetattr(stdin_file.handle, .NOW, new_term_settings) catch {};
	}
	


	var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
	defer _ = gpa.deinit();

	const alloc = gpa.allocator();

	var mapper = MosLib.boards.Apple1.init(@ptrCast(try alloc.alloc(u8, 0x1000)), stdin, stdout);
	defer alloc.free(mapper.mem);

	var core = MosLib.Mos6502{
		.state = undefined,
		.interface = &mapper.interface,
	};


	core.reset();

	// Try `0:A9 0 AA 20 EF FF E8 8A 4C 2 0`
	// or try `0:A2 0 B5 F C9 0 F0 F8 20 EF FF E8 4C 2 0 4D` `10:4F 53 20 36 35 30 32 20 0`
	var instr_count: usize = 0;
	while (true) {
		try core.step_1_instruction();
		instr_count += 1;

		std.Thread.sleep(1_000_000); // for the 70s vibe
	}

}

fn rawmem_main() !void {


	var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
	defer _ = gpa.deinit();

	const alloc = gpa.allocator();

	var mapper = MosLib.boards.RawMemory.init(@ptrCast(try alloc.alloc(u8, 0x10000)));
	defer alloc.free(mapper.mem);

	var core = MosLib.Mos6502{
		.state = undefined,
		.interface = &mapper.interface,
	};


	mapper.write16(0xFFFC, 0x0200);
	mapper.write16(0xFFFA, 0x0300);
	mapper.blit(0x0200, &.{
		0xD8, 0x58, 0x18, 0xA9, 0x88, 0xA9, 0xFF, 0x4C,
		0x03, 0x02,
	});
	mapper.blit(0x0300, &.{
		0x68, 0xAA, 0x68, 0x48, 0x8A, 0x48, 0x58, 0x40,
	});
	

	core.reset();

	std.debug.print("{f}\n", .{core.state});
	for (0..20) |n| {
		if (n == 8) core.trigger_nmi();
		try core.step_1_instruction();
		std.debug.print("t {}\n{f}\n", .{n, core.state});
	}
}


pub fn main() !void {
	return apple1_main();
}


