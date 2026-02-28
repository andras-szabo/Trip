SECTION "Utilities", ROM0

; de: source
; hl: target address
; bc: count
MemCopy:
	ld 	a, b
	or 	a, c
	ret	z

	ld 	a, [de]
	ld 	[hli], a
	inc de
	dec bc
	jr 	MemCopy

MemClear:
	ld	a, b
	or	a, c
	ret	z

	xor	a
	ld	[hli], a
	dec	bc
	jr	MemClear

;Store some value (bc) into the thing
;pointed to by hl.
;
;@param bc: the value
;@param hl: the address of the variable
StoreWord:
	ld	[hl], c
	inc	hl
	ld	[hl], b
	ret

;Load some value from the thing pointed
;to by hl into bc. 
;
;@param hl: the address of the variable
;@return bc: the value
LoadWord:
	ld	c, [hl]
	inc	hl
	ld	b, [hl]
	ret

;@param hl: address of value to cap
;@param a: maximum absolute value
CapAbsoluteValue:
	ld	b, a		; save value

	ld	a, [hl]
	bit	7, a
	jr	z, .CapToPositive

	add	b	
	bit	7, a
	ret	z

	ld	a, b
	cpl
	inc a
	ld	[hl], a
	ret

.CapToPositive:
	cp	b
	ret	c
	ld	a, b
	ld	[hl], a
	ret

; GetTileByPixel
; Converts a pixel position to a tilemap address
; hl = $9800 + X + Y * 32
; @param b: X (in pixels)
; @param c: Y (in pixels)
; @return hl: tile address
GetTileByPixel:
	; To convert pixels to tile positions, we need to divide by 8,
	; as each tile is 8x8 pixels.
	; Then we need to multiply the Y (tile) position by 32, because
	; in the tile map, one row consists of 32 columns.
	; Dividing by 8 (and ignoring the remainder) is shifting right 3x,
	; multiplying by 32 is shifting left 2x. So this is practically
	; shifting left 2x, such that 3 lowest bits are zeroed out (because
	; these would be shifted out with the division, and shifting left
	; would introduce zeroes).

	ld	a, c			; a now contains y (in pixels)
	and	a, %11111000	; zeroing out the lowest 3 bits

	ld	l, a			; multiplying 32 can yield a number higher than
	ld	h, 0			; 256 (the tile map contains 32x32 = 1024 pixels),
						; so we need to load the pixel coordinates into hl.
						; But it's also true that at this point, a < 256,
						; so it's safe to load into l. So hl now contains
						; the position divided by 8, then multiplied by 8;
						; now we shift it left twice more.

						; Unfortunately there doesn't seem to exist a left
						; shift operation that would work with 16 bit numbers,
						; so we need to add.
	add	hl, hl			; hl now contains (tile pos * 8 * 2)
	add	hl, hl			; hl now contains (tile pos * 8 * 2 * 2) = tile pos * 32

	ld	a, b			; a now contains x (in pixels), which we'll need to
						; divide by 8 to get the tile position
	srl	a				; Shift Right Logically
	srl	a
	srl	a

	; a now contains x / 8, so the tile X position; which we'll need to add to hl
	add	a, l			; add to a the low byte of hl; may overflow which will set the
						; carry flag
	ld	l, a			; load this back to l
	adc	a, h			; add the value of h, plus the carry flag, to a
	sub	a, l			; subtract l. So this is basically:
						; add the low bytes together, remember if there's an overflow,	
						; and store them in l. Then add to this h and the carry flag,
						; then subtract l; so practically this is: let a = h + the carry flag,
	ld	h, a			; if I understand it correctly. Then load this into h.
						; So at this point, hl contains an offset, in bytes, that points to
						; a tile in the tile map. To calculate the tile's address,
						; we have to add the offset to the tile map start
	ld	bc, $9800
	add	hl, bc
	ret
	
