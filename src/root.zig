//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const Mos6502 = @import("Core.zig");

pub const boards = struct {
	pub const Apple1 = @import("Apple1.zig");
	pub const RawMemory = @import("RawMemory.zig");
	pub const MMU = @import("MMU.zig");
};

