INCLUDE "hardware.inc"
INCLUDE "utility.inc"

SECTION "Header", ROM0[$100]
	jp EntryPoint
	ds $150 - @, 0

EntryPoint:
	call Init

Main:
	jp Main

;---------------------------------------------------------------------------------

CopyTileDataIntoVRAM:
	ld	de, Tiles
	ld	hl,	$9000
	ld	bc, Tiles.End - Tiles
	call MemCopy
	ret

CopySpriteDataIntoVRAM:
	ld	de, TracerSpriteTiles
	ld	hl,	$8000
	ld	bc, TracerSpriteTiles.End - TracerSpriteTiles
	call MemCopy
	ret

ClearOAM:
	ld	bc, 160
	ld	hl, STARTOF(OAM)
	call MemClear
	ret

InitTracerSprite:
	; Top half
	ld	hl, STARTOF(OAM)	; expecting Tracer's top sprite data to be at the start of OAM
	ld	a, 120 + 16			; y coordinate
	ld	[hli], a
	ld	a, 16 + 8			; x coordinate
	ld	[hli], a
	xor	a					; tile ID
	ld	[hli], a
	ld	[hli], a

	; Bottom half
	ld	a, 120 + 16 + 8
	ld	[hli], a
	ld	a, 16 + 8
	ld	[hli], a
	ld	a, 1
	ld	[hli], a
	xor	a
	ld	[hli], a
	ret

SetupTileMap:
	; Clear tile map
	ld	hl, $9800
	ld	bc, 32 * 32
.ClearLoop:
	xor	a
	ld	[hli], a
	dec bc
	ld	a, b
	or	c
	jr	nz, .ClearLoop

	; Set the top and bottom row full of tile 1
	; 1 row = 20 tiles
	ld	hl, $9800
	ld	bc, 20
.TopLoop:
	ld	a, 1
	ld	[hli], a		
	dec bc
	ld	a, b
	or	c
	jr	nz, .TopLoop

	ld	hl, $9800 + (32 * 17)
	ld	bc, 20
.BottomLoop:
	ld	a, 1
	ld	[hli], a
	dec bc
	ld	a, b
	or	c
	jr	nz, .BottomLoop

	ld	hl, $9800
	ld	bc, 18
	ld	de, 32
.LeftLoop:
	ld	a, 1
	ld	[hl], a
	add	hl, de	
	dec bc
	ld	a, b
	or	c
	jr	nz, .LeftLoop

	ld	hl, $9813		; rightmost column
	ld	bc, 18
.RightLoop:
	ld	a, 1
	ld	[hl], a
	add	hl, de
	dec	bc
	ld	a, b
	or	c
	jr	nz, .RightLoop

	ret

WaitForVBlank:
	ld	a, [rLY]
	cp	144
	jr	c, WaitForVBlank
	ret

ShutdownAudio:
	xor	a
	ld	[rNR52], a
	ret

TurnOnLCD:
	ld	a, LCDC_ON | LCDC_BG_ON | LCDC_OBJ_ON
	ld	[rLCDC], a
	ld	a, %11100100
	ld	[rBGP], a
	ld	a, %11100100
	ld	[rOBP0], a
	ret

TurnOffLCD:
	xor	a
	ld	[rLCDC], a
	ret

Init:
	call ShutdownAudio
	call WaitForVBlank
	call TurnOffLCD
	call CopyTileDataIntoVRAM
	call SetupTileMap
	call CopySpriteDataIntoVRAM
	call ClearOAM
	call InitTracerSprite
	call TurnOnLCD
	ret

SECTION "Tile data", ROM0

Tiles:
	dw	`00000000		; Tile 0, empty
	dw	`00000000
	dw	`00000000
	dw	`00000000
	dw	`00000000
	dw	`00000000
	dw	`00000000
	dw	`00000000

	dw	`11111111		; Tile 1, of color 1
	dw	`11111111
	dw	`11011011
	dw	`11100111
	dw	`11100111
	dw	`11011011
	dw	`11111111
	dw	`11111111

	dw	`22222222		; Tile 2, of color 2
	dw	`22222222
	dw	`22000022
	dw	`22022022
	dw	`22022022
	dw	`22000022
	dw	`22222222
	dw	`22222222

	dw	`33333333		; Tile 3, of color 3
	dw	`30333303
	dw	`33300333
	dw	`33033033
	dw	`33033033
	dw	`33300333
	dw	`30333303
	dw	`33333333
.End:

TracerSpriteTiles:
	dw	`22222222
	dw	`20000002
	dw	`20000002
	dw	`20000002
	dw	`20000002
	dw	`20000002
	dw	`20000002
	dw	`22222222

	dw	`31111113
	dw	`30000003
	dw	`30000003
	dw	`30000003
	dw	`30000003
	dw	`30000003
	dw	`30000003
	dw	`33333333

.End:

