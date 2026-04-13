SECTION "Globals", WRAM0
wSpeedPerFrameX:	db		; in subpixels (16 subpixels = 1 pixel)
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

wA:					db		; hi ram shadow registers,
wB:					db		; so we can save temp copies
wC:					db		; without going thru the
wD:					db		; stack
wE:					db
wH:					db
wL:					db

wColumnToLoad:		db

wCurrentPixelOffset:    db  ; used for collision checking
wTotalPixels:           db
wTilesMoved:            db

wTilePosX:          db
wTilePosY:          db
wTileData:          db

SECTION "Input variables", WRAM0
wCurKeys:	db
wNewKeys:	db