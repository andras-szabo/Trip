INCLUDE "hardware.inc"
INCLUDE "utility.inc"
INCLUDE "input.inc"

DEF SUBPIXELS_PER_PIXEL EQU 16
DEF MAX_TRACER_SPEED_SPF EQU 112
DEF DEFAULT_ACCELERATION EQU 12
DEF DEFAULT_FRICTION EQU 8
DEF DEFAULT_JUMP_STRENGTH EQU 64
DEF DEFAULT_GRAVITY EQU 16

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
	ld	a, d
	ldh	[wCurrentAccX], a

	call UpdateVerticalAcceleration
	ld	a, e
	ldh	[wCurrentAccY], a

	; Integrate horizontal acceleration	---------------------------------------

	ldh	a, [wCurrentAccX]
	ld	hl, wSpeedPerFrameX
	ld	de, wCurrentSubPixelX
	call IntegrateAcceleration
	ld	a, d
	ldh	[wCurrentPosDeltaX], a

	; Integrate vertical acceleration -----------------------------------------

	ldh	a, [wCurrentAccY]
	ld	hl, wSpeedPerFrameY
	ld	de, wCurrentSubPixelY
	call IntegrateAcceleration
	ld	a, d
	ldh	[wCurrentPosDeltaY], a

	; Check for collisions ----------------------------------------------------
	ldh	a, [wCurrentPosDeltaX]
	ld	d, a
	ldh a, [wCurrentPosDeltaY]
	ld	e, a
	call CheckWallCollisions	; d now contains _updated_ horizontal position delta

	; Actually update OAM -------------------------------------------------------
	call UpdateOAM

	jp 	Main

;---------------------------------------------------------------------------------
;@param d: horizontal position delta, in pixels
;@param e: vertical position delta, in pixels
UpdateOAM:
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
	ld	a, 0;[wCurKeys]
	ld	b, a
	ld	a, [wNewKeys]
	or	b

	and	a, PAD_A

	; For now, let's just return if not pressed
	ld	a, [wGravity]
	ld	e, a
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

;@param d: horizontal position delta
;@param e: vertical position delta
;@return d: updated horizontal position delta
;@return e: updated vertical position delta
CheckWallCollisions:

	; TODO: This should not actually read from STARTOF(OAM),
	; 		but instead use the WRAM copies

	; Let's do vertical checks first.
	; Check for bottom
	ld	a, [STARTOF(OAM) + 0 + 1]				; x coordinate of sprites
	sub	4										; we'll use the centre point for now
	ld	b, a									; b contains the x coord to check

	; First, let's assume we're falling
	ld	a, [STARTOF(OAM) + 4 + 0]				; y coordinate of bottom sprite
	sub 7										; we'll look a pixel down.
												; How does it work?
					; OAM contains object's vertical position on screen + 16.
					; To get the object's top position, we need to subtract
					; 16. But we're actually interested in the bottom position,
					; that would be y - 8; and actually 1 pixel below _that_,
					; so hence -7.

	ld	c, a

	bit	7, e
	jr	nz, .SkipWallCheckOnBottom

	; Check wall on the bottom
	call GetTileByPixel
	ld	a, [hl]
	call IsWallTile				; set z if the tile is a wall
	jr	nz, .CheckHorizontal
	xor	a
	ld	e, a
	ld	[wSpeedPerFrameY], a
	jr	.CheckHorizontal

.SkipWallCheckOnBottom:
	ld	a, c
	sub	a, 8 + 8 + 2
	ld	c, a

	; Check wall on top
	call GetTileByPixel
	ld	a, [hl]
	call IsWallTile
	jr	nz, .CheckHorizontal
	xor	a
	ld	e, a
	ld	[wSpeedPerFrameY], a

.CheckHorizontal:
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
	ld	[wSpeedPerFrameX], a

	ret

;---------------------------------------------------------------------------------
;@param a: current acceleration (subpixels/frame)
;@param hl: address of current speed (subpixels/frame)
;@param de: address of current subpixel
;@return d: position delta (pixels), as a result of current acceleration.
IntegrateAcceleration:
	; Applies current acceleration (subpixels/frame) to current speed,
	; and calculates the position delta, clamped, that the current speed
	; will result in.

	ld	b, a		; save current acceleration into d

	; Update current speed
	ld	a, [hl]
	add	b
	ld	[hl], a

	; If current speed is 0, just return with a positional delta of 0.
	and	a
	jr	nz, .ContinueWithNonZeroSpeed
	ld	d, a
	ret

.ContinueWithNonZeroSpeed:
	ld	a, MAX_TRACER_SPEED_SPF	
	call CapAbsoluteValue

	xor a
	ld	c, a			; c will contain the number of full pixels to move
						; later on, d will be set to contain -1 or 1, to
						; indicate the direction

	; Calculate new subpixel

	ld	a, [hl]
	ld	b, a
	ld	a, [de]			; load into a the value of current subpixel
	add	b

	ld	b, c			; clear "b". it will be used as a temp register,
						; to keep track of the positional delta.

	; a now contains the current subpixel; so count how many pixels we need to
	; move, so that a ends up being between 0 and 15 (incl).

	bit	7, a
	jr	z, .SubPixelLoopRight

	; If we're here - new subpixel is negative -,then for sure we have to step
	; one pixel in the negative direction.

	dec	b

.SubPixelLoopLeft:
	bit	7, a				; is subpixel non-negative already?
	jr	z, .MoveNext		; this really is a horrible name
	inc	c
	add	SUBPIXELS_PER_PIXEL
	jr	.SubPixelLoopLeft

.SubPixelLoopRight:
	inc	b					; If there's any pixel to move, it will be in the positive direction
.SubPixelLoopRight2:
	cp	SUBPIXELS_PER_PIXEL
	jr	c, .MoveNext
	inc	c
	sub	SUBPIXELS_PER_PIXEL
	jr	.SubPixelLoopRight2

.MoveNext:
	ld	[de], a
	ld	a, c
	and	a
	jr	nz, .CalculatePositionDelta
	xor	a
	ld	d, a				; Putting 0 into the return value 
	ret

.CalculatePositionDelta:
	xor	a
.CalculatePositionDeltaLoop:
	add	b
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

	; Let's put some platforms down as well
	ld	hl, $9800 + (32 * 8) + 5
	ld	c, 8
.MiddlePlatformLoop:
	ld	a, 1
	ld	[hli], a
	dec c
	jr	nz, .MiddlePlatformLoop

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

	ld	a, DEFAULT_GRAVITY
	ld	[wGravity], a

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

SECTION "Foo", HRAM[$FF80]
wCurrentAccX:		db
wCurrentAccY:		db
wCurrentPosDeltaX:	db
wCurrentPosDeltaY:	db

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

