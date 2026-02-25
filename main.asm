INCLUDE "hardware.inc"
INCLUDE "utility.inc"
INCLUDE "input.inc"

DEF SUBPIXELS_PER_PIXEL EQU 16
DEF MAX_TRACER_SPEED_SPF EQU 48
DEF DEFAULT_ACCELERATION EQU 12
DEF DEFAULT_FRICTION EQU 8
DEF DEFAULT_JUMP_STRENGTH EQU 12

DEF WALL_TILE EQU 1

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
	call UpdateHorizontalAcceleration
	call UpdateVerticalAcceleration

	call MoveTracer				; d now contains horizontal position delta
	call MoveTracerVertical		; and e now contains vertical positional delta

	call CheckWallCollisions	; d now contains _updated_ horizontal position delta

	; OK so MoveTracer puts into d new positional delta, but also we have
	; set current subpixel. So, what do do about collisions?
	;
	; - Check new position.
	;	- If it's a blocking tile
	;		- find previous position & subpixelposition
	;		- calculate new position delta

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
	; Expects in "e" the vertical position delta, in pixels

	ld	a, [STARTOF(OAM) + 0]
	add	e
	ld	[STARTOF(OAM) + 0 + 0], a			; Top sprite, y coord
	add 8
	ld	[STARTOF(OAM) + 4 + 0], a			; Bottom sprite, y coord

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

UpdateVerticalAcceleration:
	; Puts into "e" the desired vertical acceleration, in subpixels
	; per frame

	xor	a
	ld	e, a

	; Check if "a" is pressed
	ld	a, [wCurKeys]
	ld	b, a
	ld	a, [wNewKeys]
	or	b

	and	a, PAD_A

	; For now, let's just return if not pressed
	ret	z

	ld	a, [wJumpStrength]
	cpl
	inc	a
	ld	e, a
	ret

UpdateHorizontalAcceleration:
	; Puts into "d" the desired horizontal acceleration, in subpixels
	; per frame.

	; Check if left is pressed

	xor	a
	ld	d, a

	ld	a, [wCurKeys]
	ld	b, a
	ld	a, [wNewKeys]
	or	b

	and	a, PAD_LEFT
	jr	z, .CheckRight

	; If left is pressed, set the current acceleration to whatever
	; it is defined as

	ld	a, [wAcceleration]
	cpl						; a = ~a
	inc	a					; a += 1, for 2s complement
	ld	d, a

.CheckRight:
	ld	a, [wCurKeys]
	ld	b, a
	ld	a, [wNewKeys]
	or	b
	
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

	ld	a, b				; otherwise, let d = -a
	cpl
	inc	a
	ld	d, a

	ret

;---------------------------------------------------------------------------------
; @param a: tileID
; @return z: set if the tile is a wall
IsWallTile:
	cp	a, WALL_TILE
	ret

CheckWallCollisions:
	; Expects "d" to contain position delta, to be applied to the sprite
	; Returns in "d" (potentially) updated position delta

	ld	a, [STARTOF(OAM) + 4 + 0]				; y coordinate of bottom sprite
	sub a, 16 
	ld	c, a

	ld	a, [STARTOF(OAM) + 0 + 1]	; x coordinate of top sprite
									; but (8, 16) in OAM coordinates is
									; (0, 0) on screen.
	; Assume we're moving left. In this case, the pixel we'll want to check for 
	; the collision is the OAM X coordinate, minus 8, minus 1, plus "d" (which
	; is a negative number. Hence the "sub a, 9".
	sub	a, 9
	ld	b, a

	; If we're actually moving right, then the previous offset of 9 must be counter
	; balanced by 8 + 1, and we need to also add an additional +1, to check the next
	; pixel, to the right of the sprite. Hence "add a, 10".
	bit	7, d
	jr	nz, .SkipWallCheckOnRight

	; Check wall on the right
	add	a, 10 
	ld	b, a

.SkipWallCheckOnRight:
	ld	a, d		; a now contains the X position delta
	add	a, b

	call GetTileByPixel		; hl now has the address of the tile we'd move to
	ld	a, [hl]		

	call IsWallTile			; z set if the tile is a wall
	ret	nz					; if not a wall, return

	xor	a
	ld	d, a				; clear d; TODO - this will have to be better,
							; and accounting for the fact that we can potentially
							; move quicker than 1 tile / frame

	ret

;---------------------------------------------------------------------------------
MoveTracerVertical:
	; Applies current acceleration to speed, and calculates vertical position
	; delta (in pixels) to apply.
	; 
	; Expects "e" to contain the current vertical acceleration in subpixels;
	; returns in "e" the vertical position delta.

	; Update current speed
	ld	a, [wSpeedPerFrameY]
	add	a, e
	ld	[wSpeedPerFrameY], a
	
	and	a
	jr	nz, .ContinueWithNonZeroSpeed
	ld	e, a
	ret

.ContinueWithNonZeroSpeed:
	; Cap current speed
	bit 7, a
	jr	z, .CapToPositive

	; If we're here, we have to check if [wSpeedPerFrameY], also in a, is higher
	; than the allowed max negative (vertical) speed
	add	a, MAX_TRACER_SPEED_SPF
	bit	7, a
	jr	z, .DoMove

	; ... it is, so we need to clamp it:
	ld	a, MAX_TRACER_SPEED_SPF
	cpl
	inc	a
	ld	[wSpeedPerFrameY], a
	jr	.DoMove

.CapToPositive:
	cp	MAX_TRACER_SPEED_SPF
	jr	c, .DoMove
	ld	a, MAX_TRACER_SPEED_SPF
	ld	[wSpeedPerFrameY], a

.DoMove:
	xor a
	ld	c, a			; c will contain the number of full pixels to move
	ld	e, a			; e will be either -1 or 1, to show the direction of the move

	; Calculate new subpixel

	ld	a, [wSpeedPerFrameY]
	ld	b, a
	ld	a, [wCurrentSubPixelY]
	add	b

	; a now contains the current subpixel; so count how many pixels we need to
	; move, so that a ends up being between 0 and 15 (incl).

	bit	7, a
	jr	z, .SubPixelLoopRight

	; If we're here - new subpixel is negative -,then for sure we have to step
	; one pixel in the negative direction.

	dec	e

.SubPixelLoopLeft:
	bit	7, a				; is subpixel non-negative already?
	jr	z, .MoveNext		; this really is a horrible name
	inc	c
	add	SUBPIXELS_PER_PIXEL
	jr	.SubPixelLoopLeft

.SubPixelLoopRight:
	inc	e					; If there's any pixel to move, it will be in the positive direction
.SubPixelLoopRight2:
	cp	SUBPIXELS_PER_PIXEL
	jr	c, .MoveNext
	inc	c
	sub	SUBPIXELS_PER_PIXEL
	jr	.SubPixelLoopRight2

.MoveNext:
	ld	[wCurrentSubPixelY], a
	ld	a, c
	and	a
	jr	nz, .CalculatePositionDelta
	xor	a
	ld	e, a
	ret

.CalculatePositionDelta:
	xor	a
.CalculatePositionDeltaLoop:
	add	e
	dec	c
	jr	nz, .CalculatePositionDeltaLoop
	ld	e, a
	ret

MoveTracer:
	; Applies current acceleration to speed, and calculates position delta
	; (in pixels) to apply.

	; Expects "d" to contain current horizontal acceleration in subpixels;
	; returns in "d" horizontal position delta
	
	; Update current speed

	ld	a, [wSpeedPerFrameX]
	add	a, d
	ld	[wSpeedPerFrameX], a

	and	a
	jr	nz, .ContinueWithNonZeroSpeed
	ld	d, a
	ret

.ContinueWithNonZeroSpeed:
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

.CapToPositive:
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
	; If a is positive:
	;	divide current subpixel by 16 to see how many pixels we need to
	;	advance to the right; use the remainder as the new current subpixel
	;
	; If a is negative:
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
	jr	nz, .CalculatePositionDelta
	xor	a
	ld	d, a
	ret	

.CalculatePositionDelta:
	xor	a					; accumulate position delta in "a"
.CalculatePositionDeltaLoop:
	add	d
	dec	c
	jr	nz, .CalculatePositionDeltaLoop 
	ld	d, a
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

	ld	a, DEFAULT_JUMP_STRENGTH
	ld	[wJumpStrength], a

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
wJumpStrength:		db		; starting vertical acceleration, sp/frame
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

	dw	`11111111		; Tile 1; wall.
	dw	`12222221
	dw	`12311321
	dw	`12133121
	dw	`12133121
	dw	`12311321
	dw	`12222221
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

