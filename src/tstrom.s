




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Boot rom
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



* = $FF00
mmu_status:   .word 0 ; status
mmu_active_l: .byte 0 ; active_lo  ( This marks which map the mmu will use to map rn                 )
mmu_active_h: .byte 0 ; active_hi  ( This marks which map the mmu will use to map rn                 )
mmu_lut_i_l:  .byte 0 ; lut_in_lo  ( writing an address here enables writing to that cell of the lut )
mmu_lut_i_h:  .byte 0 ; lut_in_hi  ( writing an address here enables writing to that cell of the lut )
mmu_lut_o_l:  .byte 0 ; lut_out_lo ( This mapps to the above selected cell of the lut                )
mmu_lut_o_h:  .byte 0 ; lut_out_hi ( This mapps to the above selected cell of the lut                )

_start = $0200 ; where any process' `_start` symbol points to

nmi_handler:
	; backup registers
	pha
	txa ; this would be simpler with extended instrs
	pha
	tya ; this would be simpler with extended instrs
	pha

	; backup exiting task's sp
	lda $00
	pha
	tsx
	stx $00

	; jump to kernel mem-space
	lda mmu_active_l
	ldy mmu_active_h
	ldx #0
	stx mmu_active_l
	stx mmu_active_h

	; load kernel stackpointer
	ldx $00
	txs

	; return control back to kernel
	rts

	; kernel will jsr here when it wants to run a task
continue_task:

	; store kernel stackpointer
	tsx
	stx $00

	; jump to new process mem-space
	sta mmu_active_l
	sty mmu_active_h

	; restore task's sp
	ldx $00
	txs
	pla
	sta $00

	; set unpriviledged
	lda mmu_status
	and #$fe
	sta mmu_status

	; restore registers
	pla
	tay
	pla
	tax
	pla

	; return from interrupt
	rti


	; kernel will jsr here when it wants to init a task
init_task:

	; store kernel stackpointer
	tsx
	stx $00

	; jump to new process mem-space
	sta mmu_active_l
	sty mmu_active_h

	; init the sp to 0
	ldx #0
	txs

	; set unpriviledged
	lda mmu_status
	and #$fe
	sta mmu_status

	; return from interrupt
	jmp _start



* = $FFFA
	.word nmi_handler ; nmi
	.word $0200 ; reset
	.word $ABCD ; irq




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Kernel
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


* = $0200

sp_backup = $00

	; the table of process 1
	lda #1
	ldy #0
	jsr init_task

	; the table of process 2
	lda #2
	ldy #0
	jsr init_task

	; continue process 1
	lda #1
	ldy #0
	jsr continue_task

	; continue process 2
	lda #2
	ldy #0
	jsr continue_task

over:
	lda #$de
	lda #$ad
	lda #$be
	lda #$ef
	jmp over


;;;;; What follows is info on how a task would be initialized that
;;;   does not its _start symbol at the usual spot. This is currently
;;;   not supported, but as I've already done the thinking I'm gonna
;;;   leave it here for future reference
;;;
;;; stack layout needed for process switch of receiving process:
;;;
;;; - [ prev stack ]
;;; - pc_low
;;; - pc_high
;;; - sr
;;; - a
;;; - x
;;; - y
;;; - $00
;;; -       <- sp_proc
;;;
;;; and sp_proc is stored at $00
;;;
;;; so, to init a process (calling its _start symbol), the following mem
;;; things need to be written (within its mem-map):
;;;   $0100 <- <_start
;;;   $0101 <- >_start
;;;   $0000 <- 7 (initial stack pointer)
;;;

;;;;; What follows is the above kernel code in c for the llvm-mos compiler.
;;;   The above code was hand-written, and I was curious as to how well
;;;   llvm-mos would handle it. Turns out it handles it perfectly!
;;;   The idea is, that I will likely implement the kernel in C as to not
;;;   get lost in the sauce completely
;;;
;;; __attribute__((always_inline))
;;; static inline uint16_t call_continue(uint16_t tid) {
;;;     const uint8_t in_l = tid & 0xff;
;;;     const uint8_t in_h = tid >> 8;
;;;
;;;     uint8_t out_l;
;;;     uint8_t out_h;
;;;
;;;     __asm__(
;;;         "jsr continue_task"
;;;         : "=a" (out_l), "=y" (out_h)
;;;         :  "a" (in_l ),  "y" (in_h )
;;;     );
;;;
;;;     const uint16_t out_l_d = out_l;
;;;     const uint16_t out_h_d = out_h;
;;;
;;;     return (out_h_d << 8) | out_l_d;
;;; }
;;;
;;;
;;; __attribute__((always_inline))
;;; static inline uint16_t call_init(uint16_t tid) {
;;;     const uint8_t in_l = tid & 0xff;
;;;     const uint8_t in_h = tid >> 8;
;;;
;;;     uint8_t out_l;
;;;     uint8_t out_h;
;;;
;;;     __asm__(
;;;         "jsr init_task"
;;;         : "=a" (out_l), "=y" (out_h)
;;;         :  "a" (in_l ),  "y" (in_h )
;;;     );
;;;
;;;     const uint16_t out_l_d = out_l;
;;;     const uint16_t out_h_d = out_h;
;;;
;;;     return (out_h_d << 8) | out_l_d;
;;; }
;;;
;;; void kernel(void) {
;;;     call_init(1);
;;;     call_init(2);
;;;     call_continue(1);
;;;     call_continue(2);
;;;
;;;     while (1) {}
;;; }
;;;




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Process 1
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


* = $0200
_start:
	lda #$88
	ldx #$44

	jsr yield

	tax
	txa
	tax
	txa

	sta $8000


yield:
	pha
	lda #0
	sta $FFFF
	pla
	rts



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Process 2
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


reg1 = $80
reg2 = $81

* = $0200
_start:
	; fib
	lda #0
	sta reg1
	lda #1

loop:
	ldx reg1
	stx reg2
	sta reg1
	adc reg2

	cmp #5
	beq do_yield
	cmp #55
	beq do_yield
	jmp loop

do_yield:
	jsr yield
	jmp loop


yield:
	pha
	lda #0
	sta $FFFF
	pla
	rts
