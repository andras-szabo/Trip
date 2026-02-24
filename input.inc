INCLUDE "hardware.inc"

SECTION "Input", ROM0

	; expect D to contain current keys
	;		 E to contain new keys
UpdateKeys:
	; Poll half the controller
	ld	a, JOYP_GET_BUTTONS
	call .oneNibble
	ld	b, a			; B7-4 = 1, B3-0 = unpressed buttons

	; Poll the other half
	ld	a, JOYP_GET_CTRL_PAD
	call .oneNibble

	swap a				; A7-4 = unpressed directions, A3-0 = 1
	xor	a, b			; A = pressed buttons + directions
	ld	b, a			; B = pressed buttons + directions

	; And release the controller
	ld	a, JOYP_GET_NONE
	ldh	[rJOYP], a

	; combine w/ previous wCurKeys to make wNewKeys
	ld	a, d			; ld a, [wCurKeys]
	xor	a, b			; a = keys that changed state
	and	a, b			; a = keys that changed to pressed
	ld	e, a			; ld [wNewKeys], a
	ld	a, b
	ld	d, a			; ld [wCurKeys], a
	ret

.oneNibble
	ldh	[rJOYP], a		; switch the key matrix
	call .knownret		; burn 10 cycles calling known ret
	ldh	a, [rJOYP]		; ignore while waiting for the key matrix to settle
	ldh	a, [rJOYP]
	ldh	a, [rJOYP]		; this read counts
	or	a, $F0			; A7-4 = 1, A3-0 = unpressed keys
.knownret
	ret
