INCLUDE "hardware.inc"
INCLUDE "utility.inc"
INCLUDE "input.inc"

INCLUDE "camera.asm"
INCLUDE "world.asm"

DEF SUBPIXELS_PER_PIXEL EQU 16
DEF MAX_TRACER_SPEED_SPF EQU 64
DEF DEFAULT_ACCELERATION EQU 8
DEF DEFAULT_FRICTION EQU 8
DEF DEFAULT_JUMP_STRENGTH EQU 64
DEF DEFAULT_GRAVITY EQU 0				; for testing

DEF WALL_TILE EQU 1

SECTION "Header", ROM0[$100]
	jp EntryPoint
	ds $150 - @, 0

EntryPoint:
	call Init

;---------------------------------------------------------------------------------
PreMain:
	; Wait until we're not in VBlank
	ld	a, [rLY]
	cp	144
	jr	nc, PreMain

Main:
	;call WaitForVBlank

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

	; CheckWallCollisions works with OAM data;
	; so we can't use that during PPU update.
	; might we get around by storing it in shadowOAM?
	; I think we should.
	;call CheckWallCollisions	; d and e now contain _updated_ horizontal position delta

	; Update world positions
	call UpdateWorldPosition

	; Update camera position

	ld	a, [wWorldPosY]
	ld	e, a
	ld	a, [wWorldPosY + 1]
	ld	d, a

	ld	a, [wWorldPosX]
	ld	c, a
	ld	a, [wWorldPosX + 1]
	ld	b, a
	
	call Camera_Update
	call WaitForVBlank
	call TileMap_Update

	; Actually update OAM -------------------------------------------------------
	;	 -- this should just consist of copying the data into OAM quick snap.
	call UpdateOAMFromWorldPosition

	jp 	Main

;---------------------------------------------------------------------------------
; Not sure if this should go here, or Camera, or somewhere else

TileMap_Update:
	; First order of business: calculate new tile coordinates
	; 						   and calculate scroll delta,
	;						   based on wCamPosX and wCamPosXPrev
	
	; Calculate and adjust scroll delta
	ld	a, [wCamPosXPrev]
	cpl	a							; flip a
	inc	a							; and add 1
	ld	c, a
	ld	a, [wCamPosXPrev + 1]
	cpl	a							; flip a
	adc	0							; add 0 + the carry flag
	ld	b, a						; bc: wCamPosXPrev negated (2's complement)

	ld	a, [wCamPosX]
	ld	l, a
	ld	a, [wCamPosX + 1]
	ld	h, a						; load wCamPosX into hl
	
	add	hl, bc						; add (the now inverted) bc to hl
									; hl should now contain the horizontal scroll delta.
									; let's assume that it's ... not a whole lot,
									; so we can ignore the high byte

	ld	a, [$FF43]
	ld	b, a
	ld	a, l
	add	b
	ld	[$FF43], a					; update the horizontal scroll register

	; TODO: only write column into tile map if we actually
	; 		moved to a new tile

	ld	a, [wCamTileDirty]
	or	a
	ret	z  ; if not dirty - feel free to ignore

	ld	hl, wCamTilePosX
	ld	c, [hl]
	inc	hl
	ld	b, [hl]

	ld	hl, wCamTilePosY
	ld	e, [hl]
	inc	hl
	ld	d, [hl]

	call WriteColumnIntoTileMap
	ret

;@param bc: new tile x
;@param de: current tile y
WriteColumnIntoTileMap:
	ld	a, 20					; screen width
	ld	l, a
	xor a
	ld	h, a
	add	hl, bc						; hl = new_tile_x + 20
	ld	a, l
	and	a, %0011_1111			; a = (new_tile_x + 20) % 32

	ld	b, a					; b: target column (0 - 31)

	; calc target column
	; calc target row (first)
	; calc offset (just once)
	; then we can just increment the offset by 32 to get the next tile

	; Calculate first target row (de % 32):
	ld	a, e
	and	a, %0001_1111			; a = new_tile_y % 31

	ld	l, a
	xor	a
	ld	h, a					

	sla l
	sla	l
	sla	l
	sla	l				; at this point, we have to shift the carry up to h
	rla					; rotate a through the carry flag
	sla	l
	rla					; and again; and then

	ld	h, a			; hl = (ty & 31) << 5

	push bc

	ld	a, b			; a = target column (tx)
	and	a, %0001_1111	; a = tx & 31
	ld	c, a
	ld	b, $98			; bc = $9800 + (tx & 31)

	add	hl, bc			; hl = $9800 + ((ty & 31) << 5) + (tx & 31)

	pop	bc

	ld	c, 18					; 1 column = 18 rows
.fill_column_loop:

	call GetTileID				; get tile ID in a

	ld	[hl], a					; write the tile data
	push bc
	ld	bc, 32
	add	hl, bc
	pop bc

	inc	de
	dec c
	jr	nz, .fill_column_loop
	ret

;@param bc: world coordinate x in tiles
;@param de: world coordinate y in tiles
;@return a: tile ID
GetTileID:
	; TODO actually do this
	ld	a, 2	
	ret

;@param a: target row (ty)
;@param b: target column (tx)
;@param d: tile ID
;@uses hl
;@uses a
;@uses bc
WriteTileToVRAM:			; TODO clean up
	; return 0x9800 + ((ty & 31) << 5) + (tx & 31);
	and	a, %0001_1111
	ld	l, a
	xor	a	
	ld	h, a

	sla l
	sla	l
	sla	l
	sla	l				; at this point, we have to shift the carry up to h
	rla					; rotate a through the carry flag
	sla	l
	rla					; and again; and then

	ld	h, a			; hl = (ty & 31) << 5

	ld	a, b
	and	a, %0001_1111

	ld	c, a
	ld	b, 0
	add	hl, bc			; hl = ((ty & 31) << 5) + (tx & 31)
	ld	b, h
	ld	c, l
	ld	hl, $9800

	add	hl, bc			; hl = $9800 + ((ty & 31) << 5) + (tx & 31)
	ld	a, d			; tile ID into a

	ld	[hl], a
	ret

;---------------------------------------------------------------------------------

;@param hl: address of a 16-bit variable
;@param bc: delta to add
AddWord:
	; Load the word into de
	ld	e, [hl]
	inc	hl
	ld	d, [hl]

	dec hl
	push hl

	ld	h, d
	ld	l, e
	add	hl, bc
	ld	b, h
	ld	c, l
	pop	hl

	ld	[hl], c
	inc	hl
	ld	[hl], b

	ret

;@param d: horizontal position delta, pixels
;@param e: vertical position delta, pixels
UpdateWorldPosition:
	ld	hl, wWorldPosX
	ld	c, d				; load "d" into bc, sign extended
	ld	b, 0				; this will come in handy later
	bit 7, c
	jr	z, .load_01_done
	
	; If d is negative, we need to clamp things to make sure
	; we don't go below 0.
	ld	a, [wWorldPosX + 1]	; load the high byte
	or	a					; if the high byte is not zero, we're good
	jr	nz, .tmp_jmp_01

	ld	a, d				; negate delta
	cpl
	inc	a
	ld	b, a				; b = -d

	ld	a, [wWorldPosX]		; compare it to wWorldPosX
	cp	b
	jr	nc, .tmp_jmp_01		; if b smaller, no carry, we're good
	jr	z, .tmp_jmp_01		; if equal, we're still good
	
	; Otherwise, we'll have to clamp d
	ld	c, b				; c = -b	(which is now positive)
	ld	b, a				; b = [wWorldPosX]
	ld	a, c				; a = -b	(which is now positive)
	sub	b					; a = -b - [wWorldPosX]
	add	d
	jr	z, .skip_x_add

	ld	d, a	; stick it into d and c
	ld	c, a	; bc should have the almost correct thing now

.tmp_jmp_01:
	ld	b, $FF					

.load_01_done:
	push de
	call AddWord
	pop	 de

.skip_x_add:
	ld	hl, wWorldPosY		; same thing for "e"
	ld	c, e
	ld	b, 0
	bit	7, c
	jr	z, .load_02_done

	; If e is negative, we need to clamp it ot make sure we keep
	; it nonnegative
	ld	a, [wWorldPosY + 1]	; load the high byte
	or	a					; if the high byte is not zero, we're good
	jr	nz, .tmp_jmp_02

	ld	a, e
	cpl
	inc	a
	ld	b, a				; b = -e

	ld	a, [wWorldPosY]
	cp	b
	jr	nc, .tmp_jmp_02
	jr	z, .tmp_jmp_02

	ld	c, b	; swap b and a with the help of c
	ld	b, a
	ld	a, c
	sub	b
	add	e
	ret	z

	ld	e, a
	ld	c, a

.tmp_jmp_02:
	ld	b, $FF

.load_02_done:
	call AddWord
	ret

UpdateOAMFromWorldPosition:
	; I think that if we can guarantee that the player will always be
	; on screen, and thus the difference between her and the camera
	; will always be fewer than 160 / 144 pixels, then we can actually
	; ignore the high byte. But maybe it's an optimization.

	
	ld	a, [wWorldPosX]
	ld	e, a
	ld	a, [wWorldPosX + 1]
	ld	d, a					; world pos X is now in de

	ld	a, [wCamPosX]
	ld	c, a
	ld	a, [wCamPosX + 1]
	ld	b, a

	; DE = DE - BC?

	ld	a, e
	sub	c			;	a = e - c
	ld	e, a		;	e = e - c	

	ld	a, d
	sbc	b			;	a = d - b
	ld	d, a		;	d = d - b


	; de now contains the pixel position of the player, we now just have to add 8,
	; so we have something to store in the OAM.

	ld	a, e	; let's just ignore "d"
	add 8
	ld	[STARTOF(OAM) + 0 + 1], a		; Top sprite, x position
	ld	[STARTOF(OAM) + 4 + 1], a		; Bottom sprite, x position

	ld	a, [wWorldPosY]
	ld	e, a
	ld	a, [wWorldPosY + 1]
	ld	d, a

	ld	a, [wCamPosY]
	ld	c, a
	ld	a, [wCamPosY + 1]
	ld	b, a

	; DE = DE - BC again
	ld	a, e
	sub	c
	ld	e, a

	ld	a, d
	sbc	b
	ld	d, a

	; de now contains the pixel position of the player
	ld	a, e	; ignoring the high byte
	add 16
	ld	[STARTOF(OAM) + 0 + 0], a		; Top sprite, y
	add 8
	ld	[STARTOF(OAM) + 4 + 0], a		; Bottom sprite, y

	ret

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
	; TODO clean this up
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

	; ... and we should update this so it can work w/ 16-bit
	; positional values.

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
	xor	a
	ld	hl, STARTOF(OAM)	; expecting Tracer's top sprite data to be at the start of OAM
	ld	[hli], a
	ld	[hli], a
	ld	[hli], a
	ld	[hli], a

	; Bottom half
	ld	[hli], a
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

	; Consider using macros instead

	ld	bc, 16
	ld	hl, wWorldPosX
	call StoreWord

	ld	bc, 120
	ld	hl, wWorldPosY
	call StoreWord

	ld	bc, 0
	ld	de, 0
	call Camera_Init_Position

	; So we have a 160 x 144 pixel screen;
	; or 20 x 18 tiles
	; let's use the following borders: ("frame" or "camera dead zone")
	; top: 8 tiles = 64 pixels
	; bottom: 1 tiles = 8 pixels
	; left: 4 tiles = 32 pixels
	; right: 4 tiles = 32 pixels     - just to get started

	ld	b, 32				; frame left delta
	ld	c, 32				; frame right delta
	ld	d, 64				; frame top delta
	ld	e, 8				; frame bottom delta
	call Camera_Init_Deadzone

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

wWorldPosX:			dw
wWorldPosY:			dw

wAcceleration:		db
wJumpStrength:		db		; starting vertical acceleration, sp/frame
wFriction:			db		; reducing lateral movement speed, sp/frame
wGravity:			db		; sp/frame, to be applied on the y axis

SECTION "Foo", HRAM[$FF80]
wCurrentAccX:		db
wCurrentAccY:		db
wCurrentPosDeltaX:	db
wCurrentPosDeltaY:	db

wAF:				dw		; hi ram shadow registers,
wBC:				dw		; so we can save temp copies
wDE:				dw		; without going thru the
wHL:				dw		; stack

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

