	include "neogeo.inc"
	include "macros.inc"
	include "sp1.inc"
	include "../common/error_codes.inc"
	include "../common/comm.inc"

	global _start
	global check_ram_oe_dsub
	global p1_input_update
	global p1p2_input_update
	global send_p1p2_controller
	global timer_interrupt
	global vblank_interrupt
	global wait_frame
	global wait_scanline
	global STR_ACTUAL
	global STR_ADDRESS
	global STR_EXPECTED
	global XY_STR_D_MAIN_MENU

	section	text

	; These are options to force the bios to do
	; z80 or goto manual tests since its not
	; practical to be holding down buttons on boot
	; with mame.

;force_z80_tests 	equ 1
;force_manual_tests 	equ 1


;




; start
_start:
	WATCHDOG
	clr.b	REG_POUTPUT
	clr.b	p1_input
	clr.b	p1_input_edge
	clr.b	p1_input_aux
	clr.b	p1_input_aux_edge
	move.w	#7, REG_IRQACK
	move.w	#$4000, REG_LSPCMODE
	lea	REG_VRAMRW, a6					; a6 will always be REG_VRAMRW
	moveq	#DSUB_INIT_PSEUDO, d7				; init dsub for pseudo subroutines
	move.l	#$7fff0000, PALETTE_RAM_START+$2		; white on black for text
	move.l	#$07770000, PALETTE_RAM_START+PALETTE_SIZE+$2	;  gray on black for text (disabled menu items)
	clr.w	PALETTE_REFERENCE
	clr.w	PALETTE_BACKDROP

	SSA3	fix_clear

	moveq	#-$10, d0
	and.b	REG_P1CNT, d0			; check for A+B+C+D being pressed, if not automatic_tests

	ifnd force_manual_tests
		bne	automatic_tests
	endif

	movea.l	$0, a7				; re-init SP
	moveq	#DSUB_INIT_REAL, d7		; init dsub for real subroutines
	clr.b	main_menu_cursor
	bra	manual_tests

automatic_tests:
	PSUB	print_header
	PSUB	watchdog_stuck_test
	PSUB	automatic_psub_tests

	movea.l	$0, a7				; re-init SP
	moveq	#DSUB_INIT_REAL, d7		; init dsub for real subroutines

	clr.b	z80_test_flags

	btst	#7, REG_P1CNT			; if P1 "D" was pressed at boot
	beq	.z80_test_enabled

	; auto-detect m1 by checking for the HELLO message (ie diag m1 + AES or MV-1B/C)
	move.b	#COMM_TEST_HELLO, d1
	cmp.b	REG_SOUND, d1
	beq	.z80_test_enabled

 	ifnd force_z80_tests
		bne	skip_z80_test		; skip Z80 tests if "D" not pressed
 	endif

.z80_test_enabled:

	bset.b	#Z80_TEST_FLAG_ENABLED, z80_test_flags

	cmp.b	REG_SOUND, d1
	beq	skip_slot_switch		; skip slot switch if auto-detected m1

	tst.b	REG_STATUS_B
	bpl	skip_slot_switch		; skip slot switch if AES

	btst	#5, REG_P1CNT
	beq	skip_slot_switch		; skip slot switch if P1 "B" is pressed

	bsr	z80_slot_switch

skip_slot_switch:

	bsr	z80_comm_test
	lea	XY_STR_Z80_WAITING, a0
	RSUB	print_xy_string_struct_clear

.loop_try_again:
	WATCHDOG
	bsr	z80_check_error
	bsr	z80_check_sm1_test
	bsr	z80_check_done
	bne	.loop_try_again

skip_z80_test:

	bsr	automatic_function_tests
	lea	XY_STR_ALL_TESTS_PASSED, a0
	RSUB	print_xy_string_struct_clear

	lea	XY_STR_ABCD_MAIN_MENU, a0
	RSUB	print_xy_string_struct_clear

	tst.b	z80_test_flags

	bne	.loop_user_input

	lea	XY_STR_Z80_TESTS_SKIPPED, a0
	RSUB	print_xy_string_struct_clear

	lea	XY_STR_Z80_HOLD_D_AND_SOFT, a0
	RSUB	print_xy_string_struct_clear

	lea	XY_STR_Z80_RESET_WITH_CART, a0
	RSUB	print_xy_string_struct_clear

.loop_user_input
	WATCHDOG
	bsr	check_reset_request

	moveq	#-$10, d0
	and.b	REG_P1CNT, d0		; ABCD pressed?
	bne	.loop_user_input

	movea.l	$0, a7			; re-init SP
	moveq	#DSUB_INIT_REAL, d7	; init dsub for real subroutines
	clr.b	main_menu_cursor
	SSA3	fix_clear
	bra	manual_tests

watchdog_stuck_test_dsub:
	lea	XY_STR_WATCHDOG_DELAY, a0
	DSUB	print_xy_string_struct_clear
	lea	XY_STR_WATCHDOG_TEXT_REMAINS, a0
	DSUB	print_xy_string_struct_clear
	lea	XY_STR_WATCHDOG_STUCK, a0
	DSUB	print_xy_string_struct_clear

	move.l	#$c930, d0		; 128760us / 128.76ms
	DSUB	delay

	moveq	#8, d0
	SSA3	fix_clear_line
	moveq	#10, d0
	SSA3	fix_clear_line
	DSUB_RETURN

; runs automatic tests that are psub based
automatic_psub_tests_dsub:
	moveq	#0, d6
.loop_next_test:
	movea.l	(AUTOMATIC_PSUB_TEST_STRUCT_START+4,pc,d6.w),a0
	moveq	#4, d0
	moveq	#5, d1
	DSUB	print_xy_string_clear			; print the test description to screen

	movea.l	(AUTOMATIC_PSUB_TEST_STRUCT_START,pc,d6.w), a2
	lea	(.dsub_return), a3			; manually do dsub call since the DSUB macro wont
	bra	dsub_enter				; work in this case
.dsub_return

	tst.b	d0					; check result
	beq	.test_passed

	move.b	d0, d6
	DSUB	print_error
	move.b	d6, d0

	tst.b	REG_STATUS_B
	bpl	.skip_error_to_credit_leds	; skip if aes
	move.b	d6, d0
	DSUB	error_to_credit_leds

.skip_error_to_credit_leds
	bra	loop_reset_check_dsub

.test_passed:
	addq.w	#8, d6
	cmp.w	#(AUTOMATIC_PSUB_TEST_STRUCT_END - AUTOMATIC_PSUB_TEST_STRUCT_START), d6
	bne	.loop_next_test
	DSUB_RETURN


AUTOMATIC_PSUB_TEST_STRUCT_START:
	dc.l	auto_bios_mirror_test_dsub, STR_TESTING_BIOS_MIRROR
	dc.l	auto_bios_crc32_test_dsub, STR_TESTING_BIOS_CRC32
	dc.l	auto_ram_oe_tests_dsub, STR_TESTING_RAM_OE
	dc.l	auto_ram_we_tests_dsub, STR_TESTING_RAM_WE
	dc.l	auto_wram_data_tests_dsub, STR_TESTING_WRAM_DATA
	dc.l	auto_wram_address_tests_dsub, STR_TESTING_WRAM_ADDRESS
AUTOMATIC_PSUB_TEST_STRUCT_END:


; runs automatic tests that are subroutine based;
automatic_function_tests:
	lea	AUTOMATIC_FUNC_TEST_STRUCT_START, a5
	moveq	#((AUTOMATIC_FUNC_TEST_STRUCT_END - AUTOMATIC_FUNC_TEST_STRUCT_START)/8 - 1), d6

.loop_next_test:
	movea.l	(a5)+, a4			; test function address
	movea.l	(a5)+, a0			; test name string address
	movea.l	a0, a0
	moveq	#4, d0
	moveq	#5, d1
	RSUB	print_xy_string_clear		; at 4,5 print test name

	move.l	a5, -(a7)
	move.w	d6, -(a7)
	jsr	(a4)				; run function
	move.w	(a7)+, d6
	movea.l	(a7)+, a5

	tst.b	d0				; check result
	beq	.test_passed

	move.w	d0, -(a7)
	RSUB	print_error
	move.w	(a7)+, d0

	tst.b	z80_test_flags			; if z80 test enabled, send error code to z80
	beq	.skip_error_to_z80
	move.b	d0, REG_SOUND

.skip_error_to_z80:
	tst.b	REG_STATUS_B
	bpl	.skip_error_to_credit_leds	; skip if aes
	RSUB	error_to_credit_leds

.skip_error_to_credit_leds
	bra	loop_reset_check

.test_passed:
	dbra	d6, .loop_next_test
	rts


AUTOMATIC_FUNC_TEST_STRUCT_START:
	dc.l	auto_bram_tests, STR_TESTING_BRAM
	dc.l	auto_palette_ram_tests, STR_TESTING_PALETTE_RAM
	dc.l	auto_vram_tests, STR_TESTING_VRAM
	dc.l	auto_mmio_tests, STR_TESTING_MMIO
AUTOMATIC_FUNC_TEST_STRUCT_END:



; swiches to cart M1/S1 roms;
z80_slot_switch:

	bset.b	#Z80_TEST_FLAG_SLOT_SWITCH, z80_test_flags

	lea	XY_STR_Z80_SWITCHING_M1, a0
	RSUB	print_xy_string_struct_clear

	move.b	#$01, REG_SOUND				; tell z80 to prep for m1 switch

	move.l	#$1388, d0				; 12500us / 12.5ms
	RSUB	delay

	cmpi.b	#$01, REG_SOUND
	beq	.z80_slot_switch_ready
	bsr	z80_slot_switch_ignored

.z80_slot_switch_ready:

	move.b	REG_P1CNT, d0
	moveq	#$f, d1
	and.b	d1, d0
	eor.b	d1, d0

	moveq	#((Z80_SLOT_SELECT_END - Z80_SLOT_SELECT_START)/2 - 1), d1
	lea	(Z80_SLOT_SELECT_START - 1), a0

.loop_next_entry:
	addq.l	#1, a0
	cmp.b	(a0)+, d0
	dbeq	d1, .loop_next_entry		; loop through struct looking for p1 input match
	beq	.z80_do_slot_switch

	addq.l	#2, a0				; nothing matched, use the last entry (slot 1)

.z80_do_slot_switch:

	move.b	(a0), d3
	lea	(XY_STR_Z80_SLOT_SWITCH_NUM), a0	; "[SS ]"
	RSUB	print_xy_string_struct

	move.b	#32, d0
	moveq	#4, d1
	moveq	#0, d2
	move.b	d3, d2
	RSUB	print_digit			; print the slot number

	subq	#1, d3				; convert to what REG_SLOT expects, 0 to 5
	move.b	d3, REG_SLOT			; set slot
	move.b	d0, REG_CRTFIX			; switch to carts m1/s1
	move.b	#$3, REG_SOUND			; tell z80 to reset
	rts


; struct {
; 	byte buttons_pressed; 	(up/down/left/right)
;  	byte slot;
; }
Z80_SLOT_SELECT_START:
	dc.b	$01, $02			; up = slot 2
	dc.b	$09, $03			; up+right = slot 3
	dc.b	$08, $04			; right = slot 4
	dc.b	$0a, $05			; down+right = slot 5
	dc.b	$02, $06			; down = slot 6
Z80_SLOT_SELECT_END:
	dc.b	$00, $01			; no match = slot 1


z80_slot_switch_ignored:
	lea	XY_STR_Z80_IGNORED_SM1, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_Z80_SM1_UNRESPONSIVE, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_Z80_MV1BC_HOLD_B, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_Z80_PRESS_START, a0
	RSUB	print_xy_string_struct_clear

	bsr	print_hold_ss_to_reset

.loop_start_not_pressed:
	WATCHDOG
	bsr	check_reset_request
	btst	#0, REG_STATUS_B
	bne	.loop_start_not_pressed		; loop waiting for user to press start or do a reboot request

.loop_start_pressed:
	WATCHDOG
	bsr	check_reset_request
	btst	#0, REG_STATUS_B
	beq	.loop_start_pressed		; loop waiting for user to release start or do a reboot request

	moveq	#27, d0
	SSA3	fix_clear_line
	moveq	#7, d0
	SSA3	fix_clear_line
	moveq	#10, d0
	SSA3	fix_clear_line
	moveq	#12, d0
	SSA3	fix_clear_line
	rts

; params:
;  d0 * 2.5us = how long to delay
delay_dsub:
	move.b	d0, REG_WATCHDOG	; 16 cycles
	subq.l	#1, d0			; 4 cycles
	bne	delay_dsub		; 10 cycles
	DSUB_RETURN

; see if the z80 sent us an error
z80_check_error:
	moveq	#-$40, d0
	and.b	REG_SOUND, d0
	cmp.b	#$40, d0		; 0x40 = flag indicating a z80 error code
	bne	.no_error

	move.b	REG_SOUND, d0		; get the error (again?)
	move.b	d0, d2
	move.l	#$100000, d1
	bsr	z80_ack_error		; ack the error by sending it back, and wait for z80 to ack our ack
	bne	loop_reset_check

	move.b	d2, d0
	and.b	#$3f, d0		; drop the error flag to get the actual error code

	; bypassing the normal print_error call here since the
	; z80 might have sent a corrupt error code which we
	; still want to print with print_error_z80
	move.w	d0, -(a7)
	DSUB	error_code_lookup
	bsr	print_error_z80
	move.w	(a7)+, d0

	tst.b	REG_STATUS_B
	bpl	.skip_error_to_credit_leds	; skip if aes
	RSUB	error_to_credit_leds

.skip_error_to_credit_leds

	bra	loop_reset_check

.no_error:
	rts

z80_check_sm1_test:

	; diag m1 is asking us to swap m1 -> sm1
	move.b	REG_SOUND, d0
	cmp.b	#COMM_SM1_TEST_SWITCH_SM1, d0
	bne	.check_swap_to_m1

	btst	#Z80_TEST_FLAG_SLOT_SWITCH, z80_test_flags		; only allow if we did a slot switch
	bne	.switch_sm1_allow

	move.b  #COMM_SM1_TEST_SWITCH_SM1_DENY, REG_SOUND
	bsr	z80_wait_clear
	rts

.switch_sm1_allow:
	move.b	d0, REG_BRDFIX
	move.b	#COMM_SM1_TEST_SWITCH_SM1_DONE, REG_SOUND

	lea	(XY_STR_Z80_SM1_TESTS), a0		; "[SM1]" to indicate m1 is running sm1 tests
	RSUB	print_xy_string_struct

	bsr	z80_wait_clear
	rts

.check_swap_to_m1:
	; diag m1 asking us to swap sm1 -> m1
	cmp.b	#COMM_SM1_TEST_SWITCH_M1, d0
	bne	.no_swaps

	move.b	d0, REG_CRTFIX
	move.b	#COMM_SM1_TEST_SWITCH_M1_DONE, REG_SOUND

	bsr	z80_wait_clear

.no_swaps:
	rts

; d0 = loop until we stop getting this byte from z80
z80_wait_clear:
	WATCHDOG
	cmp.b	REG_SOUND, d0
	beq	z80_wait_clear
	rts

; see if z80 says its done testing (with no issues)
z80_check_done:
	move.b	#COMM_Z80_TESTS_COMPLETE, d0
	cmp.b	REG_SOUND, d0
	rts

z80_comm_test:

	lea	XY_STR_Z80_M1_ENABLED, a0
	RSUB	print_xy_string_struct

	lea	XY_STR_Z80_TESTING_COMM_PORT, a0
	RSUB	print_xy_string_struct_clear

	move.b	#COMM_TEST_HELLO, d1
	move.w  #500, d2
	bra	.loop_start_wait_hello

; wait up to 5 seconds for hello (10ms * 500 loops)
.loop_wait_hello
	move.w	#4000, d0
	RSUB	delay
.loop_start_wait_hello
	cmp.b	REG_SOUND, d1
	dbeq	d2, .loop_wait_hello
	bne	.z80_hello_timeout

	move.b	#COMM_TEST_HANDSHAKE, REG_SOUND

	moveq	#COMM_TEST_ACK, d1
	move.w	#100, d2
	bra	.loop_start_wait_ack

; Wait up to 1 second for ack response (10ms delay * 100 loops)
; This is kinda long but the z80 has its own loop waiting for a
; Z80_SEND_HANDSHAKE request.  We need our loop to last longer
; so the z80 has a chance to timeout and give us an error,
; otherwise we will just get the last thing to wrote (Z80_RECV_HELLO).
.loop_wait_ack:
	move.w	#4000, d0
	RSUB	delay
.loop_start_wait_ack:
	cmp.b	REG_SOUND, d1
	dbeq	d2, .loop_wait_ack
	bne	.z80_ack_timeout
	rts

.z80_hello_timeout
	lea	XY_STR_Z80_COMM_NO_HELLO, a0
	bra	.print_comm_error

.z80_ack_timeout
	lea	XY_STR_Z80_COMM_NO_ACK, a0

.print_comm_error
	move.b	d1, d0
	bra	z80_print_comm_error



; loop forever checking for reset request;
loop_reset_check:
	bsr	print_hold_ss_to_reset
.loop_forever:
	WATCHDOG
	bsr	check_reset_request
	bra	.loop_forever


; loop forever checking for reset request
loop_reset_check_dsub:
	moveq	#4, d0
	moveq	#27, d1
	lea	STR_HOLD_SS_TO_RESET, a0
	DSUB	print_xy_string_clear

.loop_ss_not_pressed:
	WATCHDOG
	moveq	#3, d0
	and.b	REG_STATUS_B, d0
	bne	.loop_ss_not_pressed		; loop until P1 start+select both held down

	moveq	#4, d0
	moveq	#27, d1
	lea	STR_RELEASE_SS, a0
	DSUB	print_xy_string_clear

.loop_ss_pressed:
	WATCHDOG
	moveq	#3, d0
	and.b	REG_STATUS_B, d0
	cmp.b	#3, d0
	bne	.loop_ss_pressed		; loop until P1 start+select are released

	reset
	stop	#$2700

; check if P1 is pressing start+select, if they are loop until
; they release and reset, else just return
check_reset_request:
	move.w	d0, -(a7)
	moveq	#3, d0
	and.b	REG_STATUS_B, d0

	bne	.ss_not_pressed			; P1 start+select not pressed, exit out

	moveq	#4, d0
	moveq	#27, d1
	lea	STR_RELEASE_SS, a0
	RSUB	print_xy_string_clear

.loop_ss_pressed:
	WATCHDOG
	moveq	#3, d0
	and.b	REG_STATUS_B, d0
	cmp.b	#3, d0
	bne	.loop_ss_pressed		; wait for P1 start+select to be released, before reset

	reset
	stop	#$2700

.ss_not_pressed:
	move.w	(a7)+, d0
	rts

print_hold_ss_to_reset:
	moveq	#4, d0
	moveq	#27, d1
	lea	STR_HOLD_SS_TO_RESET, a0
	RSUB	print_xy_string_clear
	rts

; prints headers
; NEO DIAGNOSTICS v0.19aXX - BY SMKDAN
; ---------------------------------
print_header_dsub:
	moveq	#0, d0
	moveq	#4, d1
	moveq	#1, d2
	moveq	#$16, d3
	moveq	#40, d4
	DSUB	print_char_repeat			; $116 which is an overscore line

	moveq	#2, d0
	moveq	#3, d1
	lea	STR_VERSION_HEADER, a0
	DSUB	print_xy_string_clear
	DSUB_RETURN

; prints the z80 related communication error
; params:
;  d0 = expected response
;  a0 = xy_string_struct address for main error
z80_print_comm_error:
	move.w	d0, -(a7)

	RSUB	print_xy_string_struct_clear

	moveq	#4, d0
	moveq	#8, d1
	lea	STR_EXPECTED, a0
	RSUB	print_xy_string_clear

	moveq	#4, d0
	moveq	#10, d1
	lea	STR_ACTUAL, a0
	RSUB	print_xy_string_clear

	lea	XY_STR_Z80_SKIP_TEST, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_Z80_PRESS_D_RESET, a0
	RSUB	print_xy_string_struct_clear

	move.w	(a7)+, d2
	moveq	#14, d0
	moveq	#8, d1
	RSUB	print_hex_byte				; expected value

	move.b	REG_SOUND, d2
	moveq	#14, d0
	moveq	#10, d1
	RSUB	print_hex_byte				; actual value

	lea	XY_STR_Z80_MAKE_SURE, a0
	RSUB	print_xy_string_struct_clear

	lea	XY_STR_Z80_CART_CLEAN, a0
	RSUB	print_xy_string_struct_clear

	bsr	z80_check_error
	bra	loop_reset_check

; ack an error sent to us by the z80 by sending
; it back, and then waiting for the z80 to ack
; our ack.
; params:
;  d0 = error code z80 sent us
;  d1 = number of loops waiting for the response
z80_ack_error:
	move.b	d0, REG_SOUND
	not.b	d0			; z80's ack back should be !d0
.loop_try_again:
	WATCHDOG
	cmp.b	REG_SOUND, d0
	beq	.command_success
	subq.l	#1, d1
	bne	.loop_try_again
	moveq	#-1, d0
.command_success:
	rts

; Display the error code on player1/2 credit leds.  Player 1 led contains
; the upper 2 digits, and player 2 the lower 2 digits.  The neogeo
; doesn't seem to allow having the left digit as 0 and instead it
; will be empty
;
; Examples:
; EC_VRAM_2K_DEAD_OUTPUT_LOWER = 0x6a = 106
; Led: p1:  1, p2:  6
;
; EC_WRAM_UNWRITABLE_LOWER = 0x70 = 112
; Led: p1:  1, p2: 12
;
; EC_Z80_RAM_DATA_00 = 0x04 = 4
; Led: p1:  0, p2:  4
;
; params:
;  d0 = error code
error_to_credit_leds_dsub:
	moveq	#3, d2
	moveq	#0, d3
	moveq	#0, d4

; convert error code to bcd
.loop_next_digit:
	divu.w	#10, d0
	swap	d0
	move.b	d0, d3
	and.l	d3, d3
	or.w	d3, d4
	clr.w	d0
	swap	d0
	ror.w	#4, d4
	dbra	d2, .loop_next_digit

	not.w	d4				; inverted per dev wiki

	; player 2 led
	move.b	#LED_NO_LATCH, REG_LEDLATCHES
	move.w	#$10, d0
	DSUB	delay				; 40us

	move.b	d4, REG_LEDDATA

	move.b	#LED_P2_LATCH, REG_LEDLATCHES
	move.w	#$10, d0
	DSUB	delay

	move.b	#LED_NO_LATCH, REG_LEDLATCHES
	move.w	#$10, d0
	DSUB	delay

	; player 1 led
	lsr.w	#8, d4
	move.b	d4, REG_LEDDATA

	move.b	#LED_P1_LATCH, REG_LEDLATCHES
	move.w	#$10, d0
	DSUB	delay

	move.b	#LED_P1_LATCH, REG_LEDLATCHES

	DSUB_RETURN

; backup palette ram to PALETTE_RAM_BACKUP_LOCATION (wram $10001c)
palette_ram_backup:
	movem.l	d0/a0-a1, -(a7)
	lea	PALETTE_RAM_START.l, a0
	lea	PALETTE_RAM_BACKUP_LOCATION.l, a1
	move.w	#$2000, d0
	bsr	copy_memory
	movem.l	(a7)+, d0/a0-a1
	rts

; restore palette ram from PALETTE_RAM_BACKUP_LOCATION (wram $10001c)
palette_ram_restore:
	movem.l	d0/a0-a1, -(a7)
	lea	PALETTE_RAM_BACKUP_LOCATION.l, a0
	lea	PALETTE_RAM_START.l, a1
	move.w	#$2000, d0
	bsr	copy_memory
	movem.l	(a7)+, d0/a0-a1
	rts

; params:
;  a0 = source address
;  a1 = dest address
;  d0 = length
copy_memory:
	swap	d0
	clr.w	d0
	swap	d0
	lea	(-$20,a0,d0.l), a0
	lea	(a1,d0.l), a1
	lsr.w	#5, d0
	subq.w	#1, d0
	movem.l	d1-d7/a2, -(a7)
.loop_next_address:
	movem.l	(a0), d1-d7/a2
	movem.l	d1-d7/a2, -(a1)
	lea	(-$20,a0), a0
	dbra	d0, .loop_next_address
	movem.l	(a7)+, d1-d7/a2

	WATCHDOG
	rts


; params:
;  d0 = inverse byte mask for player1 inputs we care about
wait_p1_input:
	WATCHDOG
	move.b	REG_P1CNT, d1
	and.b	d0, d1
	cmp.b	d0, d1
	bne	wait_p1_input
	bsr	wait_frame
	bsr	wait_frame
	rts

; wait for a full frame
wait_frame:
	move.w	d0, -(a7)

.loop_bottom_border:
	WATCHDOG
	move.w	(4,a6), d0
	and.w	#$ff80, d0
	cmp.w	#$f800, d0
	beq	.loop_bottom_border		; loop until we arent at bottom border

.loop_not_bottom_border:
	WATCHDOG
	move.w	(4,a6), d0
	and.w	#$ff80, d0
	cmp.w	#$f800, d0
	bne	.loop_not_bottom_border		; loop until we see the bottom border

	move.w	(a7)+, d0
	rts

; d0 = scanline to wait for
wait_scanline:
	WATCHDOG
	move.w	(4,a6), d1
	lsr.w	#$7, d1
	cmp.w	d0, d1
	bne	wait_scanline
	rts

p1p2_input_update:
	bsr	p1_input_update
	bra	p2_input_update

p1_input_update:
	move.b	REG_P1CNT, d0
	not.b	d0
	move.b	p1_input, d1
	eor.b	d0, d1
	and.b	d0, d1
	move.b	d1, p1_input_edge
	move.b	d0, p1_input
	move.b	REG_STATUS_B, d0
	not.b	d0
	move.b	p1_input_aux, d1
	eor.b	d0, d1
	and.b	d0, d1
	move.b	d1, p1_input_aux_edge
	move.b	d0, p1_input_aux
	rts

p2_input_update:
	move.b	REG_P2CNT, d0
	not.b	d0
	move.b	p2_input, d1
	eor.b	d0, d1
	and.b	d0, d1
	move.b	d1, p2_input_edge
	move.b	d0, p2_input
	move.b	REG_STATUS_B, d0
	lsr.b	#2, d0
	not.b	d0
	move.b	p2_input_aux, d1
	eor.b	d0, d1
	and.b	d0, d1
	move.b	d1, p2_input_aux_edge
	move.b	d0, p2_input_aux
	rts

; params:
;  d0 = send lower 3 bits to both p1/p2 ports
send_p1p2_controller:
	move.w	d1, -(a7)
	move.b	d0, d1
	lsl.b	#3, d1
	or.b	d1, d0
	move.b	d0, REG_POUTPUT
	move.l	#$1f4, d0		; 1250us / 1.25ms
	RSUB	delay
	move.w	(a7)+, d1
	rts

manual_tests:
.loop_forever:
	bsr	main_menu_draw
	bsr	main_menu_loop
	bra	.loop_forever


main_menu_draw:
	RSUB	print_header
	lea	MAIN_MENU_ITEMS_START, a1
	moveq	#((MAIN_MENU_ITEMS_END - MAIN_MENU_ITEMS_START) / 10 - 1), d4
	moveq	#5, d5					; row to start drawing menu items at

.loop_next_entry:
	movea.l	(a1)+, a0
	addq.l	#4, a1
	moveq	#0, d2
	move.w	(a1)+, d0
	cmp	#0, d0
	beq	.print_entry				; if flags == 0, print entry on both systems (mvs/aes)

	tst.b	REG_STATUS_B
	bpl	.system_aes

	cmp.w	#1, d0
	beq	.print_entry
	moveq	#$10, d2				; if flag is not 1, adjust palette
	bra	.print_entry

.system_aes:
	cmp.w	#2, d0
	beq	.print_entry
	moveq	#$10, d2					; if flag is not 2, adjust palette

.print_entry:
	moveq	#6, d0
	move.b	d5, d1
	RSUB	print_xy_string
	addq.b	#1, d3
	addq.b	#1, d5
	dbra	d4, .loop_next_entry
	bsr	print_hold_ss_to_reset
	rts


main_menu_loop:
	moveq	#-$10, d0
	bsr	wait_p1_input
	bsr	wait_frame

.loop_run_menu:

	bsr	check_reset_request
	bsr	p1p2_input_update

	moveq	#4, d0
	moveq	#5, d1
	add.b	main_menu_cursor, d1
	moveq	#$11, d2
	RSUB	print_xy_char				; draw arrow

	move.b	main_menu_cursor, d1
	move.b	p1_input_edge, d0
	btst	#UP, d0					; see if p1 up pressed
	beq	.up_not_pressed

	subq.b	#1, d1
	bpl	.update_arrow
	moveq	#((MAIN_MENU_ITEMS_END - MAIN_MENU_ITEMS_START) / 10) - 1, d1
	bra	.update_arrow

.up_not_pressed:					; up wasnt pressed, see if down was
	btst	#DOWN, d0
	beq	.check_a_pressed			; down not pressed either, see if 'a' is pressed

	addq.b	#1, d1
	cmp.b	#((MAIN_MENU_ITEMS_END - MAIN_MENU_ITEMS_START) / 10), d1
	bne	.update_arrow
	moveq	#0, d1

.update_arrow:						; up or down was pressed, update the arrow location
	move.w	d1, -(a7)
	moveq	#4, d0
	moveq	#5, d1
	add.b	main_menu_cursor, d1
	move.b	(1,a7), main_menu_cursor
	moveq	#$20, d2
	RSUB	print_xy_char				; replace existing arrow with space

	moveq	#4, d0
	moveq	#5, d1
	add.w	(a7)+, d1
	moveq	#$11, d2
	RSUB	print_xy_char				; draw arrow at new location

.check_a_pressed:
	btst	#A_BUTTON, p1_input_edge		; 'a' pressed?
	bne	.a_pressed
	bsr	wait_frame
	bra	.loop_run_menu

.a_pressed:						; 'a' was pressed, do stuff
	clr.w	d0
	move.b	main_menu_cursor, d0
	mulu.w	#$a, d0					; find the offset within the main_menu_items array
	lea	(MAIN_MENU_ITEMS_START,PC,d0.w), a1

	moveq	#1, d0					; setup d0 to contain 1 for AES, 2 for MVS
	tst.b	REG_STATUS_B
	bpl	.system_aes
	moveq	#2, d0

.system_aes:
	cmp.w	($8,a1), d0
	beq	.loop_run_menu				; flags saw its not valid for this system, ignore and loop again

	SSA3	fix_clear

	movea.l	(a1)+, a0
	moveq	#4, d0
	moveq	#5, d1
	RSUB	print_xy_string

	movea.l	(a1), a0
	jsr	(a0)					; call the test function
	SSA3	fix_clear
	rts


; array of main menu items
; struct {
;  long string_address,
;  long function_address,
;  word flags,  // 0 = valid for both, 1 = aes disabled, 2 = mvs disable
; }
MAIN_MENU_ITEMS_START:
	MAIN_MENU_ITEM STR_CALENDAR_IO, manual_calendar_tests, 1
	MAIN_MENU_ITEM STR_COLOR_BARS_BASIC, manual_color_bars_basic_test, 0
	MAIN_MENU_ITEM STR_COLOR_BARS_SMPTE, manual_color_bars_smpte_test, 0
	MAIN_MENU_ITEM STR_VIDEO_DAC_TESTS, manual_video_dac_tests, 0
	MAIN_MENU_ITEM STR_CONTROLLER_TESTS, manual_controller_tests, 0
	MAIN_MENU_ITEM STR_MM_WBRAM_TEST_LOOP, manual_wbram_test_loop, 0
	MAIN_MENU_ITEM STR_MM_PAL_RAM_TEST_LOOP, manual_palette_ram_test_loop, 0
	MAIN_MENU_ITEM STR_MM_VRAM_TEST_LOOP_32K, manual_vram_32k_test_loop, 0
	MAIN_MENU_ITEM STR_MM_VRAM_TEST_LOOP_2K, manual_vram_2k_test_loop, 0
	MAIN_MENU_ITEM STR_MM_MISC_INPUT_TEST, manual_misc_input_tests, 0
	MAIN_MENU_ITEM STR_MEMCARD_TESTS, manual_memcard_tests, 0
MAIN_MENU_ITEMS_END:


vblank_interrupt:
	WATCHDOG
	move.w	#$4, REG_IRQACK
	tst.b	$100000.l		; this seems like dead code since nothing
	beq	.exit_interrupt		; else touches $10000(0|2) as a variable..
	movem.l	d0-d7/a0-a6, -(a7)
	addq.w	#1, $100002.l
	movem.l	(a7)+, d0-d7/a0-a6
	clr.b	$100000.l
.exit_interrupt:
	rte

timer_interrupt:
	addq.w	#$1, timer_count
	move.w	#$2, ($a,a6)		; ack int
	rte

; The bios code is only 32k ($8000).  3 copies/mirrors
; of it are used to fill the entire 128k of the bios rom.
; At offset $7ffb of each mirror is a byte that contains
; the mirror number.  The running bios is $00, first
; mirror is $01, 2nd mirror $02, and 3th mirror $03.
; This test checks each of these to verify they are correct.
; If they end up being wrong it will trigger the "BIOS ADDRESS (A14-A15)"
; error.
; on error:
;  d1 = actual value
;  d2 = expected value
auto_bios_mirror_test_dsub:
	lea	$bffffb, a0
	moveq	#3, d0
	moveq	#-1, d2
.loop_next_offset:
	addq.b	#1, d2
	adda.l	#$8000, a0
	move.b	(a0), d1
	cmp.b	d2, d1
	dbne	d0, .loop_next_offset
	bne	.test_failed

	moveq	#$0, d0
	DSUB_RETURN

.test_failed:
	moveq	#EC_BIOS_MIRROR, d0
	DSUB_RETURN

; verifies the bios crc is correct.  The expected crc32 value
; are the 4 bytes located at $7ffc ($c07ffc) of the bios.
; on error:
;  d1 = actual crc32
auto_bios_crc32_test_dsub:
	move.l	#$7ffb, d0			; length
	lea	$c00000.l, a0			; start address
	move.b	d0, REG_SWPROM			; use carts vector table?
	DSUB	calc_crc32

	move.b	d0, REG_SWPBIOS			; use bios vector table
	cmp.l	$c07ffc.l, d0
	beq	.test_passed

	move.l	d0, d1
	moveq	#EC_BIOS_CRC32, d0
	DSUB_RETURN

.test_passed:
	moveq	#0, d0
	DSUB_RETURN

; calculate the crc32 value
; params:
;  d0 = length
;  a0 = start address
; returns:
;  d0 = crc value
calc_crc32_dsub:
	subq.l	#1, d0
	move.w	d0, d3
	swap	d0
	move.w	d0, d4
	lea	REG_WATCHDOG, a1
	move.l	#$edb88320, d5			; P
	moveq	#-1, d0
.loop_outter:
	move.b	d0, (a1)			; WATCHDOG
	moveq	#7, d2
	move.b	(a0)+, d1
	eor.b	d1, d0
.loop_inner:
	lsr.l	#1, d0
	bcc	.no_carry
	eor.l	d5, d0
.no_carry:
	dbra	d2, .loop_inner
	dbra	d3, .loop_outter
	dbra	d4, .loop_outter
	not.l	d0
	DSUB_RETURN

auto_ram_oe_tests_dsub:
	lea	WORK_RAM_START.l, a0		; wram upper
	moveq	#0, d0
	DSUB	check_ram_oe
	tst.b	d0
	bne	.test_failed_wram_upper

	moveq	#1, d0				; wram lower
	DSUB	check_ram_oe
	tst.b	d0
	bne	.test_failed_wram_lower

	tst.b	REG_STATUS_B			; skip bram test on AES unless C is pressed
	bmi	.do_bram_test
	btst	#6, REG_P1CNT
	bne	.test_passed

.do_bram_test:
	lea	BACKUP_RAM_START.l, a0		; bram upper
	moveq	#0, d0
	DSUB	check_ram_oe
	tst.b	d0
	bne	.test_failed_bram_upper

	moveq	#1, d0				; bram lower
	DSUB	check_ram_oe
	tst.b	d0
	bne	.test_failed_bram_lower

.test_passed:
	moveq	#0, d0
	DSUB_RETURN

.test_failed_wram_upper:
	moveq	#EC_WRAM_DEAD_OUTPUT_UPPER, d0
	DSUB_RETURN
.test_failed_wram_lower:
	moveq	#EC_WRAM_DEAD_OUTPUT_LOWER, d0
	DSUB_RETURN
.test_failed_bram_upper:
	moveq	#EC_BRAM_DEAD_OUTPUT_UPPER, d0
	DSUB_RETURN
.test_failed_bram_lower:
	moveq	#EC_BRAM_DEAD_OUTPUT_LOWER, d0
	DSUB_RETURN

; Attempts to read from ram.  If the chip never gets enabled
; d1 will be filled with the last data on the data bus,
; which would be part of the preceding move.b instruction.
; The "move.b (a0), d1" instruction translates to $1210 in
; machine code.  When doing an upper ram test if d1 contains
; $12 its assumed the ram read didnt happen, likewise for
; lower if d1 contains $10 for lower.
; params:
;  a0 = address
;  d0 = 0 (upper chip) or 1 (lower chip)
; return:
;  d0 = $00 (pass) or $ff (fail)
check_ram_oe_dsub:
	adda.w	d0, a0
	moveq	#$31, d2

.loop_test_again:
	move.b	(a0), d1
	cmp.b	*(PC,d0.w), d1
	bne	.test_passed

	move.b	(a0), d1
	nop
	cmp.b	*-2(PC,d0.w), d1
	bne	.test_passed

	move.b	(a0), d1
	add.w	#0, d0
	cmp.b	*-4(PC,d0.w), d1

.test_passed:
	dbeq	d2, .loop_test_again
	seq	d0
	DSUB_RETURN

auto_bram_tests:
	tst.b	REG_STATUS_B			; do test if MVS
	bmi	.do_bram_tests
	btst	#$6, REG_P1CNT			; do test if AES and C pressed
	beq	.do_bram_tests
	moveq	#0, d0
	rts

.do_bram_tests:
	move.b	d0, REG_SRAMUNLOCK		; unlock bram
	RSUB	bram_data_tests
	tst.b	d0
	bne	.test_failed
	RSUB	bram_address_tests

.test_failed:
	move.b	d0, REG_SRAMLOCK		; lock bram
	rts

auto_palette_ram_tests:
	lea	PALETTE_RAM_START.l, a0
	lea	PALETTE_RAM_BACKUP_LOCATION.l, a1
	move.w	#$2000, d0
	bsr	copy_memory			; backup palette ram, unclean why palette_ram_backup function wasnt used

	bsr	palette_ram_output_tests
	bne	.test_failed_abort

	bsr	palette_ram_we_tests
	bne	.test_failed_abort

	bsr	palette_ram_data_tests
	bne	.test_failed_abort

	bsr	palette_ram_address_tests

.test_failed_abort:
	move.b	d0, REG_PALBANK0

	movem.l	d0-d2/a0, -(a7)			; restore palette ram
	lea	PALETTE_RAM_BACKUP_LOCATION.l, a0
	lea	PALETTE_RAM_START.l, a1
	move.w	#$2000, d0
	bsr	copy_memory
	movem.l	(a7)+, d0-d2/a0
	rts


palette_ram_we_tests:
	lea	PALETTE_RAM_START.l, a0
	move.w	#$ff, d0
	RSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_lower
	moveq	#EC_PAL_UNWRITABLE_LOWER, d0
	rts

.test_passed_lower:
	lea	PALETTE_RAM_START.l, a0
	move.w	#$ff00, d0
	RSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_upper
	moveq	#EC_PAL_UNWRITABLE_UPPER, d0
	rts

.test_passed_upper:
	moveq	#0, d0
	rts

auto_ram_we_tests_dsub:
	lea	WORK_RAM_START.l, a0
	move.w	#$ff, d0
	DSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_wram_lower
	moveq	#EC_WRAM_UNWRITABLE_LOWER, d0
	DSUB_RETURN

.test_passed_wram_lower:
	lea	WORK_RAM_START.l, a0
	move.w	#$ff00, d0
	DSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_wram_upper
	moveq	#EC_WRAM_UNWRITABLE_UPPER, d0
	DSUB_RETURN

.test_passed_wram_upper:
	tst.b	REG_STATUS_B
	bmi	.do_bram_test				; if MVS jump to bram test
	btst	#6, REG_P1CNT				; dead code? checking if C is pressed, then nop
	nop						; maybe nop should be 'bne .do_bram_test' to allow forced bram test on aes?
	moveq	#0, d0
	DSUB_RETURN

.do_bram_test:
	move.b	d0, REG_SRAMUNLOCK			; unlock bram

	lea	BACKUP_RAM_START.l, a0
	move.w	#$ff, d0
	DSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_bram_lower

	moveq	#EC_BRAM_UNWRITABLE_LOWER, d0
	DSUB_RETURN

.test_passed_bram_lower:
	lea	BACKUP_RAM_START.l, a0
	move.w	#$ff00, d0
	DSUB	check_ram_we
	tst.b	d0
	beq	.test_passed_bram_upper

	moveq	#EC_BRAM_UNWRITABLE_UPPER, d0
	DSUB_RETURN

.test_passed_bram_upper:
	move.b	d0, REG_SRAMLOCK			; lock bram
	moveq	#0, d0
	DSUB_RETURN

; params:
;  a0 = address
;  d0 = bitmask
check_ram_we_dsub:
	move.w	(a0), d1
	and.w	d0, d1
	moveq	#0, d2
	move.w	#$101, d5		; incr amount for each loop
	move.w	#$ff, d3		; loop $ff times

.loop_next_address
	move.w	d2, (a0)
	add.w	d5, d2
	move.w	(a0), d4
	and.w	d0, d4
	cmp.w	d1, d4			; check if write and re-read values match
	dbne	d3, .loop_next_address
	beq	.test_failed

	moveq	#0, d0
	DSUB_RETURN

.test_failed:
	moveq	#-1, d0
	DSUB_RETURN

MEMORY_DATA_TEST_PATTERNS:
	dc.w	$0000, $5555, $aaaa, $ffff
MEMORY_DATA_TEST_PATTERNS_END:


auto_wram_data_tests_dsub:
	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d3

.loop_next_pattern:
	lea	WORK_RAM_START, a0
	move.w	#$8000, d1
	move.w	(a1)+, d0
	DSUB	check_ram_data
	tst.b	d0
	bne	.test_failed
	dbra	d3, .loop_next_pattern
	DSUB_RETURN

.test_failed:
	subq.b	#1, d0
	add.b	#EC_WRAM_DATA_LOWER, d0
	DSUB_RETURN


bram_data_tests_dsub:
	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d3

.loop_next_pattern:
	lea	BACKUP_RAM_START, a0
	move.w	#$8000, d1
	move.w	(a1)+, d0
	DSUB	check_ram_data
	tst.b	d0
	bne	.test_failed
	dbra	d3, .loop_next_pattern
	DSUB_RETURN

.test_failed:
	subq.b	#1, d0
	add.b	#EC_BRAM_DATA_LOWER, d0
	DSUB_RETURN


palette_ram_data_tests:
	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d3

.loop_next_pattern_bank0:
	lea	PALETTE_RAM_START, a0
	move.w	#$1000, d1
	move.w	(a1)+, d0
	DSUB	check_ram_data
	tst.b	d0
	bne	.test_failed_bank0
	dbra	d3, .loop_next_pattern_bank0
	bra	.test_passed_bank0

.test_passed_bank0:
	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d3

.loop_next_pattern_bank1:
	lea	PALETTE_RAM_START, a0
	move.w	#$1000, d1
	move.w	(a1)+, d0
	DSUB	check_ram_data
	tst.b	d0
	bne	.test_failed_bank1
	dbra	d3, .loop_next_pattern_bank1

	move.b	d0, REG_PALBANK0
	moveq	#0, d0
	rts

.test_failed_bank0:
	subq.b	#1, d0
	add.b	#EC_PAL_BANK0_DATA_LOWER, d0
	rts

.test_failed_bank1:
	subq.b	#1, d0
	add.b	#EC_PAL_BANK1_DATA_LOWER, d0
	rts

; Does a full write/read test
; params:
;  a0 = start address
;  d0 = value
;  d1 = length
; returns:
;  d0 = 0 (pass), 1 (lower bad), 2 (upper bad), 3 (both bad)
;  a0 = failed address
;  d1 = wrote value
;  d2 = read (bad) value
check_ram_data_dsub:
	subq.w	#1, d1

.loop_next_address:
	move.w	d0, (a0)
	move.w	(a0)+, d2
	cmp.w	d0, d2
	dbne	d1, .loop_next_address
	bne	.test_failed

	WATCHDOG
	moveq	#0, d0
	DSUB_RETURN

.test_failed:
	subq.l	#2, a0
	move.w	d0, d1
	WATCHDOG

	; set error code based on which byte(s) were bad
	moveq	#0, d0

	cmp.b	d1, d2
	beq	.check_upper
	or.b	#1, d0

.check_upper:
	ror.l	#8, d1
	ror.l	#8, d2
	cmp.b	d1, d2
	beq	.check_done
	or.b	#2, d0

.check_done:
	rol.l	#8, d1
	rol.l	#8, d2
	DSUB_RETURN


auto_wram_address_tests_dsub:
	lea	WORK_RAM_START.l, a0
	moveq	#2, d0
	move.w	#$100, d1
	DSUB	check_ram_address
	tst.b	d0
	beq	.test_passed_a0_a7
	moveq	#EC_WRAM_ADDRESS_A0_A7, d0
	DSUB_RETURN

.test_passed_a0_a7:
	lea	WORK_RAM_START.l, a0
	move.w	#$200, d0
	move.w	#$80, d1
	DSUB	check_ram_address
	tst.b	d0
	beq	.test_passed_a8_a14
	moveq	#EC_WRAM_ADDRESS_A8_A14, d0
	DSUB_RETURN

.test_passed_a8_a14:
	moveq	#0, d0
	DSUB_RETURN

bram_address_tests_dsub:
	lea	BACKUP_RAM_START.l, a0
	moveq	#$2, d0
	move.w	#$100, d1
	DSUB	check_ram_address

	tst.b	d0
	beq	.test_passed_a0_a7
	moveq	#EC_BRAM_ADDRESS_A0_A7, d0
	DSUB_RETURN

.test_passed_a0_a7:
	lea	BACKUP_RAM_START.l, a0
	move.w	#$200, d0
	move.w	#$80, d1
	DSUB	check_ram_address

	tst.b	d0
	beq	.test_passed_a8_a14
	moveq	#EC_BRAM_ADDRESS_A8_A14, d0
	DSUB_RETURN

.test_passed_a8_a14:
	moveq	#0, d0
	DSUB_RETURN

; params:
;  a0 = address start
;  d0 = increment
;  d1 = iterations
; returns:
; d0 = 0 (pass), $ff (fail)
; d1 = expected value
; d2 = actual value
check_ram_address_dsub:
	subq.w	#1, d1
	move.w	d1, d2
	moveq	#0, d3

.loop_write_next_address:
	move.w	d3, (a0)			; write memory locations based on increment and iterations
	add.w	#$101, d3			; each location gets $0101 more then the previous
	adda.w	d0, a0
	dbra	d2, .loop_write_next_address

	move.l	a0, d3
	and.l	#$f00000, d3			; reset the $0101 counter
	movea.l	d3, a0

	moveq	#0, d3
	bra	.loop_start_address_read

.loop_read_next_address:
	add.w	#$101, d3
	adda.w	d0, a0
.loop_start_address_read:
	move.w	(a0), d2			; now re-read the same locations and make they match
	cmp.w	d2, d3
	dbne	d1, .loop_read_next_address
	bne	.test_failed
	WATCHDOG
	moveq	#0, d0
	DSUB_RETURN

.test_failed:
	move.w	d3, d1
	WATCHDOG
	moveq	#-1, d0
	DSUB_RETURN


palette_ram_address_tests:
	lea	PALETTE_RAM_START.l, a0
	moveq	#2, d0
	move.w	#$100, d1
	bsr	check_palette_ram_address
	beq	.test_passed_a0_a7
	moveq	#EC_PAL_ADDRESS_A0_A7, d0
	rts

.test_passed_a0_a7:
	lea	PALETTE_RAM_START.l, a0
	move.w	#$200, d0
	moveq	#$20, d1
	bsr	check_palette_ram_address
	beq	.test_passed_a8_a12
	moveq	#EC_PAL_ADDRESS_A0_A12, d0
	rts

.test_passed_a8_a12:
	moveq	#0, d0
	rts

; params:
;  d0 = increment amount
;  d1 = number of increments
check_palette_ram_address:
	lea	PALETTE_RAM_START.l, a0
	lea	PALETTE_RAM_MIRROR_START.l, a1
	subq.w	#1, d1
	move.w	d1, d2
	moveq	#0, d3

.loop_write_next_address:
	move.w	d3, (a0)
	add.w	#$101, d3
	adda.w	d0, a0				; write to palette ram
	cmpa.l	a0, a1				; continue until a0 == PALETTE_RAM_MIRROR
	bne	.skip_bank_switch_write

	move.b	d0, REG_PALBANK1
	lea	PALETTE_RAM_START.l, a0
.skip_bank_switch_write:
	dbra	d2, .loop_write_next_address

	move.b	d0, REG_PALBANK0
	lea	PALETTE_RAM_START.l, a0
	moveq	#0, d3
	bra	.loop_start_address_read


.loop_read_next_address:
	add.w	#$101, d3
	adda.w	d0, a0
	cmpa.l	a0, a1
	bne	.loop_start_address_read	; aka .skip_bank_switch_read

	move.b	d0, REG_PALBANK1
	lea	PALETTE_RAM_START.l, a0

.loop_start_address_read:
	move.w	(a0), d2
	cmp.w	d2, d3
	dbne	d1, .loop_read_next_address

	bne	.test_failed
	move.b	d0, REG_PALBANK0
	WATCHDOG
	moveq	#0, d0
	rts

.test_failed:
	move.w	d3, d1
	move.b	d0, REG_PALBANK0
	WATCHDOG
	moveq	#-1, d0
	rts

; Depending on motherboard model there will either be 2x245s or a NEO-G0
; sitting between the palette memory and the 68k data bus.
; The first 2 tests are checking for output from the IC's, while the last 2
; tests are checking for output on the palette memory chips
palette_ram_output_tests:
	moveq	#1, d0
	lea	PALETTE_RAM_START, a0
	RSUB	check_ram_oe
	tst.b	d0
	beq	.test_passed_memory_output_lower
	moveq	#EC_PAL_245_DEAD_OUTPUT_LOWER, d0
	rts

.test_passed_memory_output_lower:
	moveq	#0, d0
	lea	PALETTE_RAM_START, a0
	RSUB	check_ram_oe
	tst.b	d0
	beq	.test_passed_memory_output_upper
	moveq	#EC_PAL_245_DEAD_OUTPUT_UPPER, d0
	rts

.test_passed_memory_output_upper:
	move.w	#$ff, d0
	bsr	check_palette_ram_to_245_output
	beq	.test_passed_palette_ram_to_245_output_lower
	moveq	#EC_PAL_DEAD_OUTPUT_LOWER, d0
	rts

.test_passed_palette_ram_to_245_output_lower:
	move.w	#$ff00, d0
	bsr	check_palette_ram_to_245_output
	beq	.test_passed_palette_ram_to_245_output_upper
	moveq	#EC_PAL_DEAD_OUTPUT_UPPER, d0
	rts

.test_passed_palette_ram_to_245_output_upper:
	moveq	#0, d0
	rts

; palette ram and have 2x245s or a NEO-G0 between
; them and the 68k data bus.  This function attempts
; to check for dead output between the memory chip and
; the 245s/NEO-G0.
;
; params
;  d0 = compare mask
; return
;  d0 = 0 is passed, -1 = failed
check_palette_ram_to_245_output:
	lea	PALETTE_RAM_START.l, a0
	move.w	#$ff, d2
	moveq	#0, d3
	move.w	#$101, d5

.loop_next_address
	move.w	d3, (a0)
	move.w	#$7fff, d4

.loop_delay:
	WATCHDOG
	dbra	d4, .loop_delay

	move.w	(a0), d1
	add.w	d5, d3
	and.w	d0, d1

	; note this is comparing the mask with the read data,
	; dead output from the chip will cause $ff
	cmp.w	d0, d1
	dbne	d2, .loop_next_address

	beq	.test_failed
	moveq	#0, d0
	rts

.test_failed:
	moveq	#-1, d0
	rts

auto_vram_tests:
	bsr	fix_backup

	bsr	vram_oe_tests
	bne	.test_failed_abort

	bsr	vram_we_tests
	bne	.test_failed_abort

	bsr	vram_data_tests
	bne	.test_failed_abort

	bsr	vram_address_tests

.test_failed_abort:
	move.w	d0, -(a7)
	bsr	fix_restore
	move.w	(a7)+, d0
	rts

vram_oe_tests:
	moveq	#0, d0
	move.w	#$ff, d1
	bsr	check_vram_oe
	beq	.test_passed_32k_lower
	moveq	#EC_VRAM_32K_DEAD_OUTPUT_LOWER, d0
	rts

.test_passed_32k_lower:
	moveq	#0, d0
	move.w	#$ff00, d1
	bsr	check_vram_oe
	beq	.test_passed_32k_upper
	moveq	#EC_VRAM_32K_DEAD_OUTPUT_UPPER, d0
	rts

.test_passed_32k_upper:
	move.w	#$8000, d0
	move.w	#$ff, d1
	bsr	check_vram_oe
	beq	.test_passed_2k_lower
	moveq	#EC_VRAM_2K_DEAD_OUTPUT_LOWER, d0
	rts

.test_passed_2k_lower:
	move.w	#$8000, d0
	move.w	#$ff00, d1
	bsr	check_vram_oe
	beq	.test_passed_2k_upper
	moveq	#EC_VRAM_2K_DEAD_OUTPUT_UPPER, d0
	rts

.test_passed_2k_upper:
	moveq	#0, d0
	rts

; params:
;  d0 = start vram address
;  d1 = mask
check_vram_oe:
	clr.w	(2,a6)
	move.w	d0, (-2,a6)
	move.w	#$ff, d2
	moveq	#0, d3
	move.w	#$101, d4

.loop_next_address:
	move.w	d3, (a6)
	nop
	nop
	nop
	nop
	move.w	(a6), d5
	add.w	d4, d3
	and.w	d1, d5
	cmp.w	d1, d5
	dbne	d2, .loop_next_address
	beq	.test_failed

	moveq	#0, d0
	rts

.test_failed:
	moveq	#-1, d0
	rts


vram_we_tests:
	moveq	#0, d0
	move.w	#$ff, d1
	bsr	check_vram_we
	beq	.test_passed_32k_lower
	moveq	#EC_VRAM_32K_UNWRITABLE_LOWER, d0
	rts

.test_passed_32k_lower:
	moveq	#$0, d0
	move.w	#$ff00, d1
	bsr	check_vram_we
	beq	.test_passed_32k_upper
	moveq	#EC_VRAM_32K_UNWRITABLE_UPPER, d0
	rts

.test_passed_32k_upper:
	move.w	#$8000, d0
	move.w	#$ff, d1
	bsr	check_vram_we
	beq	.test_passed_2k_lower
	moveq	#EC_VRAM_2K_UNWRITABLE_LOWER, d0
	rts

.test_passed_2k_lower:
	move.w	#$8000, d0
	move.w	#$ff00, d1
	bsr	check_vram_we
	beq	.test_passed_2k_upper
	moveq	#EC_VRAM_2K_UNWRITABLE_UPPER, d0
	rts

.test_passed_2k_upper:
	moveq	#0, d0
	rts


; params:
;  d0 = start vram address
;  d1 = mask
check_vram_we:
	move.w	d0, (-2,a6)
	clr.w	(2,a6)
	move.w	(a6), d0
	and.w	d1, d0
	moveq	#0, d2
	move.w	#$101, d5
	move.w	#$ff, d3
	lea	REG_WATCHDOG, a0

.loop_next_address:
	move.w	d2, (a6)
	move.b	d0, (a0)			; WATCHDOG
	add.w	d5, d2
	move.w	(a6), d4
	and.w	d1, d4
	cmp.w	d0, d4
	dbne	d3, .loop_next_address
	beq	.test_failed

	moveq	#0, d0
	rts

.test_failed:
	moveq	#-1, d0
	rts


vram_data_tests:
	bsr	vram_32k_data_tests
	bne	.test_failed_abort
	bsr	vram_2k_data_tests

.test_failed_abort:
	rts

vram_32k_data_tests:

	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d5

.loop_next_pattern:
	move.w	(a1)+, d0
	moveq	#0, d1
	move.w	#$8000, d2
	bsr	check_vram_data
	tst.b	d0
	bne	.test_failed
	dbra	d5, .loop_next_pattern
	rts

.test_failed:
	subq.b	#1, d0
	add.b	#EC_VRAM_32K_DATA_LOWER, d0
	rts

; 2k (words) vram tests (data and address) only look at the
; first 1536 (0x600) words, since the remaining 512 words
; are used by the LSPC for buffers per dev wiki
vram_2k_data_tests:

	lea	MEMORY_DATA_TEST_PATTERNS, a1
	moveq	#((MEMORY_DATA_TEST_PATTERNS_END - MEMORY_DATA_TEST_PATTERNS)/2 - 1), d5

.loop_next_pattern:
	move.w	(a1)+, d0
	move.w	#$8000, d1
	move.w	#$600, d2
	bsr	check_vram_data
	tst.b	d0
	bne	.test_failed
	dbra	d5, .loop_next_pattern
	rts

.test_failed:
	subq.b	#1, d0
	add.b	#EC_VRAM_2K_DATA_LOWER, d0
	rts

; params:
;  d0 = pattern
;  d1 = vram start address
;  d2 = length in words
; returns:
;  d0 = 0 (pass), 1 (lower bad), 2 (upper bad), 3 (both bad)
;  a0 = fail address
;  d1 = expected value
;  d2 = actual value
check_vram_data:
	move.w	#1, (2,a6)
	move.w	d1, (-2,a6)
	subq.w	#1, d2
	move.w	d2, d3

.loop_write_next_address:
	move.w	d0, (a6)			; write pattern
	dbra	d2, .loop_write_next_address

	move.w	d1, (-2,a6)
	lea	REG_WATCHDOG, a0
	move.w	d3, d2

.loop_read_next_address:
	move.b	d0, (a0)			; WATCHDOG
	move.w	(a6), d4			; read value
	move.w	d4, (a6)			; rewrite (to force address to increase)
	cmp.w	d0, d4
	dbne	d2, .loop_read_next_address
	bne	.test_failed

	moveq	#0, d0
	rts

.test_failed:
	add.w	d3, d1				; setup error data
	sub.w	d2, d1
	swap	d1
	clr.w	d1
	swap	d1
	movea.l	d1, a0
	move.w	d0, d1
	move.w	d4, d2

	; set error code based on which byte(s) were bad
	moveq	#0, d0

	cmp.b	d1, d2
	beq	.check_upper
	or.b	#1, d0

.check_upper:
	ror.l	#8, d1
	ror.l	#8, d2
	cmp.b	d1, d2
	beq	.check_done
	or.b	#2, d0

.check_done:
	rol.l	#8, d1
	rol.l	#8, d2
	rts


vram_address_tests:
	bsr	vram_32k_address_tests
	bne	.test_failed_abort
	bsr	vram_2k_address_tests

.test_failed_abort:
	rts

vram_32k_address_tests:
	clr.w	d1
	move.w	#$100, d2
	moveq	#1, d0
	bsr	check_vram_address
	beq	.test_passed_a0_a7
	moveq	#EC_VRAM_32K_ADDRESS_A0_A7, d0
	rts

.test_passed_a0_a7:
	clr.w	d1
	move.w	#$80, d2
	move.w	#$100, d0
	bsr	check_vram_address
	beq	.test_passed_a8_a14
	moveq	#EC_VRAM_32K_ADDRESS_A8_A14, d0
	rts

.test_passed_a8_a14:
	rts


vram_2k_address_tests:
	move.w	#$8000, d1
	move.w	#$100, d2
	moveq	#1, d0
	bsr	check_vram_address
	beq	.test_passed_a0_a7
	moveq	#EC_VRAM_2K_ADDRESS_A0_A7, d0
	rts

.test_passed_a0_a7:
	move.w	#$8000, d1
	move.w	#$6, d2
	move.w	#$100, d0
	bsr	check_vram_address
	beq	.test_passed_a8_a14
	moveq	#EC_VRAM_2K_ADDRESS_A8_A10, d0
	rts

.test_passed_a8_a14:
	rts

; params:
;  d0 = modulo/incr amount
;  d1 = start vram address
;  d2 = interation amount
; returns:
;  d0 = 0 (pass) / $ff (fail)
;  a0 = address (vram)
;  d1 = expected value
;  d2 = actual value
check_vram_address:
	move.w	d0, (2,a6)
	move.w	d1, (-2,a6)
	subq.w	#1, d2
	move.w	d2, d3
	moveq	#0, d0
	move.w	#$101, d5

.loop_write_next_address:
	move.w	d0, (a6)
	add.w	d5, d0
	dbra	d2, .loop_write_next_address

	move.w	d1, (-2,a6)
	moveq	#0, d0
	move.w	d3, d2
	lea	REG_WATCHDOG, a0
	bra	.loop_start_read_next_address

.loop_read_next_address:
	move.b	d0, (a0)			; WATCHDOG
	add.w	d5, d0

.loop_start_read_next_address:
	move.w	(a6), d4
	move.w	d4, (a6)
	cmp.w	d0, d4
	dbne	d2, .loop_read_next_address
	bne	.test_failed
	moveq	#0, d0
	rts

.test_failed:
	mulu.w	(2,a6), d3			; figure out the bad address based on
	add.w	d3, d1				; modulo and start address
	mulu.w	(2,a6), d2
	sub.w	d2, d1
	swap	d1
	clr.w	d1
	swap	d1
	movea.l	d1, a0
	move.w	d0, d1
	move.w	d4, d2
	moveq	#-1, d0
	rts


fix_backup:
	movem.l	d0/a0, -(a7)
	lea	FIXMAP_BACKUP_LOCATION.l, a0
	move.w	#FIXMAP, (-2,a6)
	move.w	#1, (2,a6)
	move.w	#$7ff, d0

.loop_next_address:
	nop
	nop
	move.w	(a6), (a0)+
	move.w	d0, (a6)
	dbra	d0, .loop_next_address
	movem.l	(a7)+, d0/a0
	rts

fix_restore:
	movem.l	d0/a0, -(a7)
	lea	FIXMAP_BACKUP_LOCATION.l, a0
	move.w	#FIXMAP, (-2,a6)
	move.w	#1, (2,a6)
	move.w	#$7ff, d0

.loop_next_address:
	move.w	(a0)+, (a6)
	dbra	d0, .loop_next_address
	movem.l	(a7)+, d0/a0
	rts


auto_mmio_tests:
	bsr	check_mmio_oe
	bne	.test_failed_abort
	bsr	check_mmio_reg_vramrw_oe

.test_failed_abort:
	rts


; does OE test against all the registers in the
; MMIO_ADDRESSES_TABLE_START table
check_mmio_oe:
	lea	MMIO_ADDRESSES_TABLE_START, a1
	moveq	#((MMIO_ADDRESSES_TABLE_END - MMIO_ADDRESSES_TABLE_START)/4 - 1), d6

.loop_next_test:
	movea.l	(a1)+, a0
	move.w	a0, d0

	lsr.b	#1, d0
	bcc	.system_both

	tst.b	REG_STATUS_B			; skip registers with bit 1 set on AES systems
	bpl	.system_aes

.system_both:
	bsr	check_mmio_oe_byte
	beq	.test_failed

.system_aes:
	dbra	d6, .loop_next_test

	moveq	#0, d0
	rts

.test_failed:
	moveq	#EC_MMIO_DEAD_OUTPUT, d0
	rts

MMIO_ADDRESSES_TABLE_START:
	dc.l REG_DIPSW
	dc.l REG_SYSTYPE
	dc.l REG_STATUS_A
	dc.l REG_P1CNT
	dc.l REG_SOUND
	dc.l REG_P2CNT
	dc.l REG_STATUS_B
MMIO_ADDRESSES_TABLE_END:

check_mmio_reg_vramrw_oe:
	movea.l	a6, a0
	bsr	check_mmio_oe_word
	beq	.test_failed

	moveq	#0, d0
	rts

.test_failed:
	moveq	#EC_MMIO_DEAD_OUTPUT, d0
	rts

; check for output enable of a byte at a0
; params:
;  a0 = address
check_mmio_oe_byte:
	moveq	#-1, d0
	move.w	a0, d0
	moveq	#$31, d2

.loop_test_again:
	move.b	(a0), d1
	cmp.b	*(PC,d0.w), d1
	bne	.test_passed

	move.b	(a0), d1
	nop
	cmp.b	*-2(PC,d0.w), d1
	bne	.test_passed

	move.b	(a0), d1
	add.w	#0, d0
	cmp.b	*-4(PC,d0.w), d1

.test_passed:
	dbeq	d2, .loop_test_again
	rts

; check for output enable of a word at a0
; params:
;  a0 = address
check_mmio_oe_word:
	moveq	#$31, d2

.loop_test_again:
	move.w	(a0), d1
	cmp.w	*(PC), d1
	bne	.test_passed

	move.w	(a0), d1
	nop
	cmp.w	*-2(PC), d1
	bne	.test_passed

	move.w	(a0), d1
	add.w	#0, d0
	cmp.w	*-4(PC), d1
.test_passed:
	dbeq	d2, .loop_test_again
	rts

manual_wbram_test_loop:
	lea	XY_STR_WBRAM_PASSES,a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_WBRAM_HOLD_ABCD, a0
	RSUB	print_xy_string_struct_clear

	moveq	#$0, d6
	tst.b	REG_STATUS_B
	bmi	.system_mvs
	bset	#$1f, d6
	lea	XY_STR_WBRAM_WRAM_AES_ONLY, a0
	RSUB	print_xy_string_struct_clear

.system_mvs:
	moveq	#DSUB_INIT_PSEUDO, d7		; init dsub for pseudo subroutines
	bra	.loop_start_run_test

.loop_run_test:
	WATCHDOG
	PSUB	auto_wram_data_tests
	tst.b	d0
	bne	.test_failed_abort

	PSUB	auto_wram_address_tests
	tst.b	d0
	bne	.test_failed_abort

	tst.l	d6
	bmi	.system_aes			; skip bram on aes
	move.b	d0, REG_SRAMUNLOCK

	PSUB	bram_data_tests
	tst.b	d0
	bne	.test_failed_abort

	PSUB	bram_address_tests
	move.b	d0, REG_SRAMLOCK
	tst.b	d0
	bne	.test_failed_abort

.system_aes:

	addq.l	#1, d6

.loop_start_run_test:

	moveq	#$e, d0
	moveq	#$e, d1
	move.l	d6, d2
	bclr	#$1f, d2
	PSUB	print_hex_3_bytes

	moveq	#-$10, d0
	and.b	REG_P1CNT, d0
	bne	.loop_run_test			; if a+b+c+d not pressed keep running test

	SSA3	fix_clear

	; re-init stuff and return to menu
	move.b	#4, main_menu_cursor
	movea.l	$0, a7				; re-init SP
	moveq	#DSUB_INIT_REAL, d7		; init dsub for real subroutines
	bra	manual_tests

.test_failed_abort:
	PSUB	print_error
	bra	loop_reset_check_dsub



manual_palette_ram_test_loop:
	lea	XY_STR_PAL_PASSES, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_PAL_A_TO_RESUME, a0
	RSUB	print_xy_string_struct_clear
	lea	XY_STR_PAL_HOLD_ABCD, a0
	RSUB	print_xy_string_struct_clear

	bsr	palette_ram_backup

	moveq	#0, d6					; init pass count to 0
	bra	.loop_start_run_test

.loop_run_test:
	WATCHDOG

	bsr	palette_ram_data_tests
	bne	.test_failed_abort

	bsr	palette_ram_address_tests
	bne	.test_failed_abort

	addq.l	#1, d6

.loop_start_run_test:
	moveq	#$e, d0
	moveq	#$e, d1
	move.w	d6, d2
	RSUB	print_hex_3_bytes			; print the number of passes in hex

	btst	#$4, REG_P1CNT				; check for 'a' being presses
	bne	.loop_run_test				; 'a' not pressed, loop and do another test

	bsr	palette_ram_restore

.loop_wait_a_release
	WATCHDOG
	moveq	#-$10, d0
	and.b	REG_P1CNT, d0				; a+b+c+d pressed? exit
	beq	.test_exit
	btst	#$4, REG_P1CNT				; only 'a' pressed
	beq	.loop_wait_a_release			; loop until either 'a' not pressed or 'a+b+c+d' pressed

	bsr	palette_ram_backup
	bra	.loop_run_test

.test_failed_abort					; error occured, print info
	move.b	d0, REG_PALBANK0
	bsr	palette_ram_restore

	RSUB	print_error

	moveq	#$19, d0
	SSA3	fix_clear_line
	bra	loop_reset_check

.test_exit:
	rts


manual_vram_32k_test_loop:
	lea	XY_STR_VRAM_32K_A_TO_RESUME, a0
	RSUB	print_xy_string_struct_clear

	lea	XY_STR_PASSES.l, a0
	RSUB	print_xy_string_struct

	lea	STR_VRAM_HOLD_ABCD.l, a0
	moveq	#$4, d0
	moveq	#$19, d1
	RSUB	print_xy_string

	bsr	fix_backup

	moveq	#$0, d6
	bra	.loop_start_run_test

.loop_run_test
	WATCHDOG
	bsr	vram_32k_data_tests
	bne	.test_failed_abort
	bsr	vram_32k_address_tests
	bne	.test_failed_abort
	addq.l	#1, d6

.loop_start_run_test:
	btst	#$4, REG_P1CNT
	bne	.loop_run_test			; loop until 'a' is pressed

	bsr	fix_restore

	moveq	#$e, d0
	moveq	#$e, d1
	move.l	d6, d2
	bclr	#$1f, d2			; make sure signed bit is 0
	RSUB	print_hex_3_bytes		; print pass number

.loop_wait_a_release:
	WATCHDOG

	moveq	#-$10, d0
	and.b	REG_P1CNT, d0
	beq	.test_exit			; if a+b+c+d stop the test, return to main menu
	btst	#$4, REG_P1CNT
	beq	.loop_wait_a_release		; loop until either 'a' not pressed or 'a+b+c+d' pressed

	bsr	fix_backup
	bra	.loop_run_test

.test_failed_abort:
	bsr	fix_restore

	movem.l	d0-d2, -(a7)
	moveq	#$e, d0
	moveq	#$e, d1
	move.l	d6, d2
	bclr	#$1f, d2
	RSUB	print_hex_3_bytes		; print pass number
	movem.l	(a7)+, d0-d2

	RSUB	print_error

	moveq	#$19, d0
	SSA3	fix_clear_line

	bra	loop_reset_check

.test_exit:
	rts


manual_vram_2k_test_loop:
	lea	STR_VRAM_HOLD_ABCD, a0
	moveq	#$4, d0
	moveq	#$1b, d1
	RSUB	print_xy_string_clear

	lea	XY_STR_PASSES.l, a0
	RSUB	print_xy_string_struct

	moveq	#$0, d6
	bra	.loop_start_run_test

.loop_run_test
	WATCHDOG
	bsr	vram_2k_data_tests
	bne	.test_failed_abort

	bsr	vram_2k_address_tests
	bne	.test_failed_abort

	moveq	#$e, d0
	moveq	#$e, d1
	move.l	d6, d2
	RSUB	print_hex_3_bytes

	addq.l	#1, d6

.loop_start_run_test:
	moveq	#-$10, d0
	and.b	REG_P1CNT, d0
	beq	.test_exit			; if a+b+c+d pressed, exit test
	bra	.loop_run_test

.test_failed_abort:
	RSUB	print_error

	moveq	#$19, d0
	SSA3	fix_clear_line

	bra	loop_reset_check

.test_exit:
	rts

manual_misc_input_tests:
	lea	XY_STR_D_MAIN_MENU, a0
	RSUB	print_xy_string_struct_clear
	bsr	misc_input_print_static
.loop_run_test
	bsr	p1p2_input_update
	bsr	misc_input_update_dynamic
	bsr	wait_frame
	btst	#D_BUTTON, p1_input_edge
	beq	.loop_run_test			; if d pressed, exit test
	rts

misc_input_print_static:
	lea	XY_STR_MI_MEMORY_CARD, a0
	RSUB	print_xy_string_struct_clear

	lea	MI_ITEM_CD1, a0
	moveq	#$9, d0
	moveq	#$3, d1
	bsr	misc_input_print_static_items

	lea	XY_STR_MI_SYSTEM_TYPE, a0
	RSUB	print_xy_string_struct_clear

	lea	MI_ITEM_TYPE, a0
	moveq	#$e, d0
	moveq	#$1, d1
	bsr	misc_input_print_static_items

	tst.b	REG_STATUS_B
	bpl	.system_aes

	lea	MI_ITEM_CFG_A, a0
	moveq	#$f, d0
	moveq	#$2, d1
	bsr	misc_input_print_static_items

.system_aes:
	rts


misc_input_update_dynamic:
	lea	MI_ITEM_CD1,a0
	moveq	#$9, d0
	moveq	#$3, d1
	bsr	misc_input_print_dynamic_items

	lea	MI_ITEM_TYPE, a0
	moveq	#$e, d0
	moveq	#$1, d1
	bsr	misc_input_print_dynamic_items

	tst.b	REG_STATUS_B
	bpl	.system_aes

	lea	MI_ITEM_CFG_A, a0
	moveq	#$f, d0
	moveq	#$2, d1
	bsr	misc_input_print_dynamic_items

	lea	STR_SYSTEM_CONFIG_AS, a0
	moveq	#$4, d0
	moveq	#$12, d1
	RSUB	print_xy_string

	btst	#$6, REG_SYSTYPE
	bne	.system_4_or_6_slots
	lea	STR_12SLOT, a0
	bra	.system_type_print

.system_4_or_6_slots:
	btst	#$5, REG_STATUS_A
	bne	.system_6_slot
	lea	STR_4SLOT, a0
	bra	.system_type_print

.system_6_slot:
	lea	STR_6SLOT, a0

.system_type_print:
	moveq	#$19, d0
	moveq	#$12, d1
	RSUB	print_xy_string
.system_aes:
	rts


; struct misc_input {
;  byte test_bit;                ; bit to test on mmio address
;  byte mmio_address[3];         ; minus top byte
;  long bit_name_string_address;
;  long bit_disabled_string_address;
;  long bit_enabled_string_address;
;}
MI_ITEM_CD1:	MISC_INPUT_ITEM $04, $38, $00, $00, STR_MI_CD1, STR_MI_CARD1_DETECTED, STR_MI_CARD1_EMPTY
MI_ITEM_CD2:	MISC_INPUT_ITEM $05, $38, $00, $00, STR_MI_CD2, STR_MI_CARD2_DETECTED, STR_MI_CARD2_EMPTY
MI_ITEM_WP:	MISC_INPUT_ITEM $06, $38, $00, $00, STR_MI_WP, STR_MI_CARD_WP_OFF, STR_MI_CARD_WP_ON
MI_ITEM_TYPE:	MISC_INPUT_ITEM $07, $38, $00, $00, STR_MI_TYPE, STR_MI_TYPE_AES, STR_MI_TYPE_MVS
MI_ITEM_CFG_A:	MISC_INPUT_ITEM $05, $32, $00, $01, STR_MI_CFG_A, STR_MI_CFG_A_LOW, STR_MI_CFG_A_HIGH
MI_ITEM_CFG_B:	MISC_INPUT_ITEM $06, $30, $00, $81, STR_MI_CFG_B, STR_MI_CFG_B_LOW, STR_MI_CFG_B_HIGH

STR_SYSTEM_CONFIG_AS:	STRING "SYSTEM CONFIGURED AS "
STR_12SLOT:		STRING "1SLOT/2SLOT"
STR_4SLOT:		STRING "4SLOT      ";
STR_6SLOT:		STRING "6SLOT      ";


; d0 = start row
; d1 = numer of misc_input structs to process
; a0 = address of first misc_input struct
misc_input_print_dynamic_items:
	movea.l	a0, a1
	move.b	d0, d5
	moveq	#$7f, d6
	and.w	d1, d6
	subq.w	#1, d6

.loop_next_entry:
	movea.l	(a1), a2
	move.b	(a1), d0			; test_bit
	movea.l	($8,a1), a0			; bit_disabled_string_address
	moveq	#$30, d2
	btst	d0, (a2)
	beq	.print_description

	movea.l	($c,a1), a0			; bit_enabled_string_address
	moveq	#$31, d2

.print_description:
	moveq	#$d, d0
	move.b	d5, d1
	RSUB	print_xy_char

	moveq	#$15, d0
	move.b	d5, d1
	moveq	#$0, d2
	moveq	#$20, d3
	moveq	#$13, d4
	RSUB	print_char_repeat		; empty out part of the line stuff

	moveq	#$15, d0
	move.b	d5, d1
	RSUB	print_xy_string

	lea	($10,a1), a1			; load up next struct
	addq.b	#1, d5
	dbra	d6, .loop_next_entry
	rts

; d0 = start row
; d1 = numer of misc_input structs to process
; a0 = address of first misc_input struct
misc_input_print_static_items:
	movea.l	a0, a1
	move.b	d0, d3
	moveq	#$7f, d6
	and.w	d1, d6
	subq.w	#1, d6

.loop_next_entry:
	move.l	(a1)+, d2			; load the test_bit and mmio_address
	moveq	#$4, d0
	move.b	d3, d1
	RSUB	print_hex_3_bytes		; print the mmio_address

	moveq	#$2e, d2
	moveq	#$a, d0
	move.b	d3, d1
	RSUB	print_xy_char

	move.b	(-$4,a1), d2			; reload test_bit
	moveq	#$b, d0
	move.b	d3, d1
	RSUB	print_hex_nibble

	moveq	#$3d, d2
	moveq	#$c, d0
	move.b	d3, d1
	RSUB	print_xy_char

	movea.l	(a1)+, a0			; load bit_name_string_address
	moveq	#$f, d0
	move.b	d3, d1
	RSUB	print_xy_string

	addq.l	#8, a1				; skip over bit_(disabled|enabled)_string_address
	addq.b	#1, d3
	dbra	d6, .loop_next_entry
	rts

STR_ACTUAL:			STRING "ACTUAL:"
STR_EXPECTED:			STRING "EXPECTED:"
STR_ADDRESS:			STRING "ADDRESS:"
STR_COLON_SPACE:		STRING ": "
STR_HOLD_SS_TO_RESET:		STRING "HOLD START/SELECT TO SOFT RESET"
STR_RELEASE_SS:			STRING "RELEASE START/SELECT"
STR_VERSION_HEADER:		STRING "NEO DIAGNOSTICS v0.19a00 - BY SMKDAN"
XY_STR_D_MAIN_MENU:		XY_STRING  4, 27, "D: Return to menu"

XY_STR_PASSES:			XY_STRING  4, 14, "PASSES:"
XY_STR_Z80_WAITING:		XY_STRING  4,  5, "WAITING FOR Z80 TO FINISH TESTS..."
XY_STR_ALL_TESTS_PASSED:	XY_STRING  4,  5, "ALL TESTS PASSED"
XY_STR_ABCD_MAIN_MENU:		XY_STRING  4, 21, "PRESS ABCD FOR MAIN MENU"
XY_STR_Z80_TESTS_SKIPPED:	XY_STRING  4, 23, "NOTE: Z80 TESTING WAS SKIPPED. TO"
XY_STR_Z80_HOLD_D_AND_SOFT:	XY_STRING  4, 24, "TEST Z80, HOLD BUTTON D AND SOFT"
XY_STR_Z80_RESET_WITH_CART:	XY_STRING  4, 25, "RESET WITH TEST CART INSERTED."

XY_STR_WATCHDOG_DELAY:		XY_STRING  4,  5, "WATCHDOG DELAY..."
XY_STR_WATCHDOG_TEXT_REMAINS:	XY_STRING  4,  8, "IF THIS TEXT REMAINS HERE..."
XY_STR_WATCHDOG_STUCK:		XY_STRING  4, 10, "THEN SYSTEM IS STUCK IN WATCHDOG"

STR_TESTING_BIOS_MIRROR:	STRING "TESTING BIOS MIRRORING..."
STR_TESTING_BIOS_CRC32:		STRING "TESTING BIOS CRC32..."
STR_TESTING_RAM_OE:		STRING "TESTING RAM /OE..."
STR_TESTING_RAM_WE:		STRING "TESTING RAM /WE..."
STR_TESTING_WRAM_DATA:		STRING "TESTING WRAM DATA..."
STR_TESTING_WRAM_ADDRESS:	STRING "TESTING WRAM ADDRESS..."
STR_TESTING_BRAM:		STRING "TESTING BRAM..."
STR_TESTING_PALETTE_RAM:	STRING "TESTING PALETTE RAM..."
STR_TESTING_VRAM:		STRING "TESTING VRAM..."
STR_TESTING_MMIO:		STRING "TESTING MMIO..."

XY_STR_Z80_SWITCHING_M1:	XY_STRING  4,  5, "SWITCHING TO CART M1..."
XY_STR_Z80_IGNORED_SM1:		XY_STRING  4,  5, "Z80 SLOT SWITCH IGNORED (SM1)"
XY_STR_Z80_SM1_UNRESPONSIVE:	XY_STRING  4,  7, "SM1 OTHERWISE LOOKS UNRESPONSIVE"
XY_STR_Z80_MV1BC_HOLD_B:	XY_STRING  4, 10, "IF MV-1B/1C: SOFT RESET & HOLD B"
XY_STR_Z80_PRESS_START:		XY_STRING  4, 12, "PRESS START TO CONTINUE"
XY_STR_Z80_TESTING_COMM_PORT:	XY_STRING  4,  5, "TESTING Z80 COMM. PORT..."
XY_STR_Z80_COMM_NO_HELLO:	XY_STRING  4,  5, "Z80->68k COMM ISSUE (HELLO)"
XY_STR_Z80_COMM_NO_ACK:		XY_STRING  4,  5, "Z80->68k COMM ISSUE (ACK)"
XY_STR_Z80_SKIP_TEST:		XY_STRING  4, 24, "TO SKIP Z80 TESTING, RELEASE"
XY_STR_Z80_PRESS_D_RESET:	XY_STRING  4, 25, "D BUTTON AND SOFT RESET."
XY_STR_Z80_MAKE_SURE:		XY_STRING  4, 21, "FOR Z80 TESTING, MAKE SURE TEST"
XY_STR_Z80_CART_CLEAN:		XY_STRING  4, 22, "CART IS CLEAN AND FUNCTIONAL."
XY_STR_Z80_M1_ENABLED:		XY_STRING 34,  4, "[M1]"
XY_STR_Z80_SLOT_SWITCH_NUM:	XY_STRING 29,  4, "[SS ]"
XY_STR_Z80_SM1_TESTS:		XY_STRING 24,  4, "[SM1]"

; main menu items
STR_MM_WBRAM_TEST_LOOP:		STRING "WRAM/BRAM TEST LOOP"
STR_MM_PAL_RAM_TEST_LOOP:	STRING "PALETTE RAM TEST LOOP"
STR_MM_VRAM_TEST_LOOP_32K:	STRING "VRAM TEST LOOP (32K)"
STR_MM_VRAM_TEST_LOOP_2K:	STRING "VRAM TEST LOOP (2K)"
STR_MM_MISC_INPUT_TEST:		STRING "MISC. INPUT TEST"

; strings wram/bram test screens
XY_STR_WBRAM_PASSES:		XY_STRING  4, 14, "PASSES:"
XY_STR_WBRAM_HOLD_ABCD:		XY_STRING  4, 27, "HOLD ABCD TO STOP"
XY_STR_WBRAM_WRAM_AES_ONLY:	XY_STRING  4, 16, "WRAM TEST ONLY (AES)"

; strings for palette test screen
XY_STR_PAL_PASSES:		XY_STRING  4, 14, "PASSES:"
XY_STR_PAL_A_TO_RESUME:		XY_STRING  4, 27, "RELEASE A TO RESUME"
XY_STR_PAL_HOLD_ABCD:		XY_STRING  4, 25, "HOLD ABCD TO STOP"

; strings for vram test screens
XY_STR_VRAM_32K_A_TO_RESUME:	XY_STRING  4, 27, "RELEASE A TO RESUME"
STR_VRAM_HOLD_ABCD:		STRING "HOLD ABCD TO STOP"

; strings for misc input screen
XY_STR_MI_MEMORY_CARD:		XY_STRING  4,  8, "MEMORY CARD:"
XY_STR_MI_SYSTEM_TYPE:		XY_STRING  4, 13, "SYSTEM TYPE:"
STR_MI_CD1:			STRING "/CD1"
STR_MI_CARD1_DETECTED:		STRING "(CARD DETECTED)"
STR_MI_CARD1_EMPTY:		STRING "(CARD SLOT EMPTY)"
STR_MI_CD2:			STRING "/CD2"
STR_MI_CARD2_DETECTED:		STRING "(CARD DETECTED)"
STR_MI_CARD2_EMPTY:		STRING "(CARD SLOT EMPTY)"
STR_MI_WP:			STRING "/WP"
STR_MI_CARD_WP_OFF:		STRING "(CARD WP OFF)"
STR_MI_CARD_WP_ON:		STRING "(CARD WP ON)"
STR_MI_TYPE:			STRING "TYPE"
STR_MI_TYPE_AES:		STRING "(SYSTEM IS AES)"
STR_MI_TYPE_MVS:		STRING "(SYSTEM IS MVS)"
STR_MI_CFG_A:			STRING "CFG-A"
STR_MI_CFG_A_LOW:		STRING "(CFG-A LOW)"
STR_MI_CFG_A_HIGH:		STRING "(CFG-A HIGH)"
STR_MI_CFG_B:			STRING "CFG-B"
STR_MI_CFG_B_LOW:		STRING "(CFG-B LOW)"
STR_MI_CFG_B_HIGH:		STRING "(CFG-B HIGH)"
