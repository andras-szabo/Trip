INCLUDE "hardware.inc"
INCLUDE "utility.inc"
INCLUDE "input.inc"

DEF SUBPIXELS_PER_PIXEL EQU 16
DEF MAX_TRACER_SPEED_SPF EQU 32
DEF DEFAULT_ACCELERATION EQU 8
DEF DEFAULT_FRICTION EQU 2

SECTION "Header", ROM0[$100]
	jp EntryPoint
	ds $150 - @, 0

EntryPoint:
	call Init

;---------------------------------------------------------------------------------
Main:
	; Wait until we're not in VBlank
	ld	a, [rLY]
	cp	144
	jr	nc, Main

	call WaitForVBlank

	call UpdateInput
	call UpdateAcceleration
	call MoveTracer				; d now contains horizontal position delta
	call UpdateOAM

	; Ideally, what should happen here?
	; call UpdateInput			
	; call UpdateAcceleration	; yields desired velocity
	; call UpdateGravity		; modifies desired velocity
	; call MoveTracer			; calculate new position values, don't write to OAM yet
	; call CheckCollisions		; modify position values
	; call UpdateOAM			; now update OAM

	jp 	Main

;---------------------------------------------------------------------------------
UpdateOAM:
	; Expects in "d" the horizontal position delta, in pixels

	ld	a, [STARTOF(OAM) + 1]
	add	d
	ld	[STARTOF(OAM) + 0 + 1], a			; Top sprite, x coord
	ld	[STARTOF(OAM) + 4 + 1], a			; Bottom sprite, x coord
	ret

;---------------------------------------------------------------------------------

UpdateInput:
	ld	a, [wCurKeys]
	ld	d, a
	ld	a, [wNewKeys]
	ld	e, a
	call UpdateKeys
	ld	a, d
	ld	[wCurKeys], a
	ld	a, e
	ld	[wNewKeys], a
	ret

UpdateAcceleration:
	; Puts into "d" the desired horizontal acceleration, in subpixels
	; per frame.

	; Check if left is pressed

	xor	a
	ld	d, a

	ld	a, [wCurKeys]
	and	a, PAD_LEFT
	jr	z, .CheckRight

	; If left is pressed, set the current acceleration to whatever
	; it is defined as

	ld	a, [wAcceleration]
	cpl						; a = ~a
	inc	a					; a += 1, for 2s complement
	ld	d, a

.CheckRight:
	; For testing, we'll pretend this is always pressed
	ld	a, [wCurKeys]
	and	a, PAD_RIGHT
	jp	z, .ApplyFriction

	; If right is pressed, set the current acceleration to whatever
	; it is defined as, but in the positive direction this time.
	; I'm also adding 'd', just in case an emulator reports that both
	; left and right are pressed.

	ld	a, [wAcceleration]
	add	d
	ld	d, a

.ApplyFriction:
	
	; If the player is not pressing any button, let's try to apply
	; deceleration due to friction. If the player is already standing
	; still, return early.

	ld	a, d
	and	a
	ret	nz
	
	ld	a, [wSpeedPerFrameX]
	and	a
	ret	z

	ld	b, a		; b now contains "old speed"

	; At this point, we don't have a button pressed, but are in movement,
	; so we should apply friction. Friction always acts against the current
	; movement direction, so let's check the sign of the current velocity

	bit	7, a					; a still contains [wSpeedPerFrameX]
	jr	z, .ApplyNegativeFriction

	; The sign bit of current speed per frame is 1, so we are moving to the
	; left; in this case, we apply wFriction as it is (assuming it's positive)

	ld	a, [wFriction]
	ld	d, a
	jr	.CheckForOvershoot

.ApplyNegativeFriction:
	ld	a, [wFriction]
	cpl
	inc	a
	ld	d, a

.CheckForOvershoot:
	ld	a, b				; a now contains "old speed"
	add	d					; a now contains "new speed"
	xor	a, b				; a = new speed XOR old speed
	bit	7, a
	ret	z					; if signs match, all good, return d as it is

	ld	a, [wSpeedPerFrameX]	; otherwise, let d = -a
	cpl
	inc	a
	ld	d, a

	ret

;---------------------------------------------------------------------------------

MoveTracer:
	; Applies current acceleration to speed, and moves her into a new position.
	; ? Where will this return the new position? Let's try to pack it into a
	; a register

	; Expects "d" to contain current horizontal acceleration in subpixels;
	; returns in "d" horizontal position delta
	
	; Update current speed

	ld	a, [wSpeedPerFrameX]
	add	a, d
	ld	[wSpeedPerFrameX], a

	and	a
	ret	z

	; Cap current speed
	bit	7, a
	jr	z, .CapToPositive

	; If we're here, we have to check if [wSpeedPerFrameX], also in "a", is higher
	; than the allowed max negative speed

	add	a, MAX_TRACER_SPEED_SPF
	bit	7, a
	jr	z, .DoMove

	ld	a, MAX_TRACER_SPEED_SPF
	cpl
	inc	a
	ld	[wSpeedPerFrameX], a
	jr	.DoMove

.CapToPositive
	cp	MAX_TRACER_SPEED_SPF
	jr	c, .DoMove
	ld	a, MAX_TRACER_SPEED_SPF
	ld	[wSpeedPerFrameX], a

.DoMove:
	xor	a	
	ld	c, a	; c will contain the number of full pixels to move
	ld	d, a	; d will be either -1 or 1, to show the direction of
				; the full pixel move

	; Calculate new subpixel

	ld	a, [wSpeedPerFrameX]
	ld	b, a
	ld	a, [wCurrentSubPixelX]
	add	b

	; "a" now contains the current subpixel; what next?
	; If [wCurrentSubPixelX] is positive:
	;	divide current subpixel by 16 to see how many pixels we need to
	;	advance to the right; use the remainder as the new current subpixel
	;
	; If [wCurrentSubPixelX] is negative:
	;	divide by -16, use the remainder as the new current subpixel

	bit	7, a
	jr	z, .SubPixelLoopRight

	; If we're here (new subpixel is negative), then for sure we have to
	; step a pixel to the left.

	dec	d

.SubPixelLoopLeft:
	bit	7, a			; OK, are we positive already?
	jr	z, .MoveNext	; this is a horrible name
	inc	c
	add	SUBPIXELS_PER_PIXEL
	jr	.SubPixelLoopLeft

.SubPixelLoopRight:
	inc	d				; If there's any pixel to move, it will be to the right
.SubPixelLoopRight2:
	cp	SUBPIXELS_PER_PIXEL
	jr	c, .MoveNext
	inc	c
	sub SUBPIXELS_PER_PIXEL
	jr .SubPixelLoopRight2

.MoveNext:
	ld	[wCurrentSubPixelX], a
	ld	a, c
	and a
	ret	z

.CalculatePositionDelta:
	dec	c
	ret	z
	ld	a, d
	add	d
	ld	d, a
	jr	.CalculatePositionDelta

	ret

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

InitGlobals:
	xor	a
	ld	[wSpeedPerFrameX], a
	ld	[wSpeedPerFrameY], a
	ld	[wCurrentSubPixelX], a
	ld	[wCurrentSubPixelY], a

	ld	a, DEFAULT_ACCELERATION
	ld	[wAcceleration], a

	ld	a, DEFAULT_FRICTION
	ld	[wFriction], a

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
	call InitGlobals
	call TurnOnLCD
	ret

SECTION "Globals", WRAM0
wSpeedPerFrameX:	db		; in subpixels (16 subpixel = 1 pixel)
wSpeedPerFrameY:	db
wCurrentSubPixelX:	db
wCurrentSubPixelY:	db

wAcceleration:		db
wFriction:			db		; reducing lateral movement speed, sp/frame
wGravity:			db		; sp/frame, to be applied on the y axis

SECTION "Input variables", WRAM0
wCurKeys:	db
wNewKeys:	db

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

