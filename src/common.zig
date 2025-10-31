
pub const AddressingMode = enum {
	accumulator,        // A       Accumulator           OPC A         operand is AC (implied single byte instruction)
	absolute,           // abs     absolute              OPC $LLHH     operand is address $HHLL *
	absolute_x_indexed, // abs,X   absolute, X-indexed   OPC $LLHH,X   operand is address; effective address is address incremented by X with carry **
	absolute_y_indexed, // abs,Y   absolute, Y-indexed   OPC $LLHH,Y   operand is address; effective address is address incremented by Y with carry **
	immediate,          // #       immediate             OPC #$BB      operand is byte BB
	implied,            // impl    implied               OPC           operand implied
	indirect,           // ind     indirect              OPC ($LLHH)   operand is address; effective address is contents of word at address: C.w($HHLL)
	x_indexed_indirect, // X,ind   X-indexed, indirect   OPC ($LL,X)   operand is zeropage address; effective address is word in (LL + X, LL + X + 1), inc. without carry: C.w($00LL + X)
	indirect_y_indexed, // ind,Y   indirect, Y-indexed   OPC ($LL),Y   operand is zeropage address; effective address is word in (LL, LL + 1) incremented by Y with carry: C.w($00LL) + Y
	relative,           // rel     relative              OPC $BB       branch target is PC + signed offset BB ***
	zeropage,           // zpg     zeropage              OPC $LL       operand is zeropage address (hi-byte is zero, address = $00LL)
	zeropage_x_indexed, // zpg,X   zeropage, X-indexed   OPC $LL,X     operand is zeropage address; effective address is address incremented by X without carry **
	zeropage_y_indexed, // zpg,Y   zeropage, Y-indexed   OPC $LL,Y     operand is zeropage address; effective address is address incremented by Y without carry **

	// *   16-bit address words are little endian, lo(w)-byte first, followed by the hi(gh)-byte.
	//     (An assembler will use a human readable, big-endian notation as in $HHLL.)
	// 
	// **  The available 16-bit address space is conceived as consisting of pages of 256 bytes each, with
	//     address hi-bytes represententing the page index. An increment with carry may affect the hi-byte
	//     and may thus result in a crossing of page boundaries, adding an extra cycle to the execution.
	//     Increments without carry do not affect the hi-byte of an address and no page transitions do occur.
	//     Generally, increments of 16-bit addresses include a carry, increments of zeropage addresses don't.
	//     Notably this is not related in any way to the state of the carry flag in the status register.
	// 
	// *** Branch offsets are signed 8-bit values, -128 ... +127, negative offsets in two's complement.
	//     Page transitions may occur and add an extra cycle to the exucution. 
};

pub const Opcode = enum {
	ADC, // add with carry
	AND, // and (with accumulator)
	ASL, // arithmetic shift left
	BCC, // branch on carry clear
	BCS, // branch on carry set
	BEQ, // branch on equal (zero set)
	BIT, // bit test
	BMI, // branch on minus (negative set)
	BNE, // branch on not equal (zero clear)
	BPL, // branch on plus (negative clear)
	BRK, // break / interrupt
	BVC, // branch on overflow clear
	BVS, // branch on overflow set
	CLC, // clear carry
	CLD, // clear decimal
	CLI, // clear interrupt disable
	CLV, // clear overflow
	CMP, // compare (with accumulator)
	CPX, // compare with X
	CPY, // compare with Y
	DEC, // decrement
	DEX, // decrement X
	DEY, // decrement Y
	EOR, // exclusive or (with accumulator)
	INC, // increment
	INX, // increment X
	INY, // increment Y
	JMP, // jump
	JSR, // jump subroutine
	LDA, // load accumulator
	LDX, // load X
	LDY, // load Y
	LSR, // logical shift right
	NOP, // no operation
	ORA, // or with accumulator
	PHA, // push accumulator
	PHP, // push processor status (SR)
	PLA, // pull accumulator
	PLP, // pull processor status (SR)
	ROL, // rotate left
	ROR, // rotate right
	RTI, // return from interrupt
	RTS, // return from subroutine
	SBC, // subtract with carry
	SEC, // set carry
	SED, // set decimal
	SEI, // set interrupt disable
	STA, // store accumulator
	STX, // store X
	STY, // store Y
	TAX, // transfer accumulator to X
	TAY, // transfer accumulator to Y
	TSX, // transfer stack pointer to X
	TXA, // transfer X to accumulator
	TXS, // transfer X to stack pointer
	TYA, // transfer Y to accumulator 
};

pub const Operand = union(AddressingMode) {
	accumulator,             // A       Accumulator           OPC A         operand is AC (implied single byte instruction)
	absolute: u16,           // abs     absolute              OPC $LLHH     operand is address $HHLL *
	absolute_x_indexed: u16, // abs,X   absolute, X-indexed   OPC $LLHH,X   operand is address; effective address is address incremented by X with carry **
	absolute_y_indexed: u16, // abs,Y   absolute, Y-indexed   OPC $LLHH,Y   operand is address; effective address is address incremented by Y with carry **
	immediate: u8,           // #       immediate             OPC #$BB      operand is byte BB
	implied,                 // impl    implied               OPC           operand implied
	indirect: u16,           // ind     indirect              OPC ($LLHH)   operand is address; effective address is contents of word at address: C.w($HHLL)
	x_indexed_indirect: u8,  // X,ind   X-indexed, indirect   OPC ($LL,X)   operand is zeropage address; effective address is word in (LL + X, LL + X + 1), inc. without carry: C.w($00LL + X)
	indirect_y_indexed: u8,  // ind,Y   indirect, Y-indexed   OPC ($LL),Y   operand is zeropage address; effective address is word in (LL, LL + 1) incremented by Y with carry: C.w($00LL) + Y
	relative: i8,            // rel     relative              OPC $BB       branch target is PC + signed offset BB ***
	zeropage: u8,            // zpg     zeropage              OPC $LL       operand is zeropage address (hi-byte is zero, address = $00LL)
	zeropage_x_indexed: u8,  // zpg,X   zeropage, X-indexed   OPC $LL,X     operand is zeropage address; effective address is address incremented by X without carry **
	zeropage_y_indexed: u8,  // zpg,Y   zeropage, Y-indexed   OPC $LL,Y     operand is zeropage address; effective address is address incremented by Y without carry **
};


pub const Instruction = struct{ Opcode, Operand };
