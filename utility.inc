SECTION "Utilities", ROM0

; de: source
; hl: target address
; bc: count
MemCopy:
	ld 	a, b
	or 	a, c
	jr 	z, MemCopyEnd

	ld 	a, [de]
	ld 	[hli], a
	inc de
	dec bc
	jr 	MemCopy
MemCopyEnd:
	ret

MemClear:
	ld	a, b
	or	a, c
	jr	z, MemClearEnd

	xor	a
	ld	[hli], a
	dec	bc
	jr	MemClear
MemClearEnd:
	ret
