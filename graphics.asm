SECTION "Shadow OAM", WRAM0[$C100], ALIGN[8]

wShadowOAM:		ds	40 * 4			;  10 sprites, 4 bytes of data each

SECTION "DMA routine", ROM0

CopyDmaRoutineToHRam:
	ld	hl, DmaRoutine
	ld	b, DmaRoutineEnd - DmaRoutine;
	ld	c, LOW(hOAMDMA)						; low byte of the destination address
.copy:
	ld	a, [hli]
	ldh	[c], a		; copy the value in register a into the byte at address $FF00 + c
	inc	c
	dec	b
	jr	nz, .copy
	ret

DmaRoutine:
	; Load the shadow OAM address' high byte into the DMA register at $FF46
	ld	a, $C1
	ld	[rDMA], a
	
	; DMA transfer begins; we now need to wait 160 microseconds while it
	; is doing work. The following loop should last exactly that long.
	ld	a, 40
.loop:
	dec	a
	jr	nz, .loop
	ret
DmaRoutineEnd:


SECTION "OAM DMA", HRAM
hOAMDMA:		ds DmaRoutineEnd - DmaRoutine

