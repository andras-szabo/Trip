SECTION "CameraVariables", WRAM0
    wCamPosX: dw            ; World coordinates (in pixels)
    wCamPosY: dw            ; World coordinates (in pixels)

    wCamPosXPrev: dw         ; Previous frame's camera position (world coords)
    wCamPosYPrev: dw         ; Previous frame's camera position (world coords)

    wDesiredPosX: dw        ; The position the camera is trying to reach (world coords)
    wDesiredPosY: dw        ; The position the camera is trying to reach (world coords)

    wCamTilePosX: dw        ; Camera position in tiles, for convenience
    wCamTilePosY: dw

    wCamTileDirty:  db      ; Did the camera move to a new tile, horizontally or vertically
                            ; (or both)?
    wCamMoveDelta:  db      ; In which direction did the camera move in the previous frame?
                            ; treat it as a bitfield:
                            ; bit 0: moved left
                            ; bit 1: moved right
                            ; bit 2: moved up
                            ; bit 3: moved down

    wFrameLeftDelta: db     ; Distance from cam pos to the left of the frame
    wFrameRightDelta: db    ; Distance from the right side of the screen to the right side of the frame; must fit into 1 byte!
    wDeadZoneWidth: dw       ; horizontal deadzone can technically be 160 pixels; vertical 144, so...

    wFrameTopDelta: db      ; Distance from cam pos to the top of the frame
    wFrameBottomDelta: db   ; Distance from cam pos to the bottom of the frame
    wDeadZoneHeight: dw      ; The ideal height of the frame; this should not change even temporarily

SECTION "CameraCode", ROM0

; Compare two signed 16-bit values and set flags like CP:
; carry if left < right, zero if left == right, else left > right.
; Clobbers: a
MACRO SIGNED_CMP16
    ld  a, \1
    xor \3
    bit 7, a
    jr  z, .sameSign\@

    ; If signs differ, sign bit alone determines ordering.
    bit 7, \1
    jr  z, .leftPositive\@

    ; left negative, right positive => left < right (set carry)
    ld  a, 0
    cp  1
    jr  .done\@

.leftPositive\@:
    ; left positive, right negative => left > right (clear carry, clear zero)
    ld  a, 1
    cp  0
    jr  .done\@

.sameSign\@:
    ; Same sign: regular unsigned bytewise compare is valid.
    ld  a, \1
    cp  \3
    jr  nz, .done\@
    ld  a, \2
    cp  \4

.done\@:
ENDM

;@param bc: Camera's initial position X
;@param de: Camera's initial position Y
Camera_Init_Position:
    ; Clamp X
    bit 7, b
    jr  z, .x_non_negative
    ld  bc, 0

.x_non_negative:
    ; Clamp Y
    bit 7, d
    jr z, .y_non_negative
    ld  de, 0

.y_non_negative:

    ld  hl, wCamPosX
    ld  [hl], c         ; lower byte first
    inc hl
    ld  [hl], b         ; high byte second

    ld  hl, wCamPosXPrev
    ld  [hl], c
    inc hl
    ld  [hl], b
    
    ld  hl, wCamPosY
    ld  [hl], e
    inc hl
    ld  [hl], d

    ld  hl, wCamPosYPrev
    ld  [hl], e
    inc hl
    ld  [hl], d

    call UpdateCamTilePos

    ret

;@param bc: wCamPosX
;@param de: wCamPosY
;@uses a
;@uses hl
;@This will modify and invalidate both bc and de.
;@It will set [wCamTileDirty] as well.
UpdateCamTilePos:
    ; Clear wCamTileDirty
    xor a
    ld  [wCamTileDirty], a

    ; First, divide bc by 8
    sra b           ; shift right arithmetically
    rr  c           ; rotate 1 right, using carry
    sra b           
    rr  c
    sra b
    rr  c

    ; Compare with existing, update if needed
    ld  hl, wCamTilePosX
    ld  a, [hl]
    cp  c
    jr  nz, .x_is_dirty
    inc hl
    ld  a, [hl]
    cp  b
    jr  nz, .x_is_dirty
    jr  .check_y

.x_is_dirty:
    ; Store tile position x
    ld  a, c
    ld  [wCamTilePosX], a
    ld  a, b
    ld  [wCamTilePosX + 1], a
    
    ld  a, 1
    ld  [wCamTileDirty], a

.check_y:
    ; Then divide de by 8
    sra d
    rr  e
    sra d
    rr  e
    sra d
    rr  e

    ; Compare with existing, update if needed
    ld  hl, wCamTilePosY
    ld  a, [hl]
    cp  e
    jr  nz, .y_is_dirty
    inc hl
    ld  a, [hl]
    cp  d
    jr  nz, .y_is_dirty
    jr  .done

.y_is_dirty:
    ; Store tile position y
    ld  a, e
    ld  [wCamTilePosY], a
    ld  a, d
    ld  [wCamTilePosY + 1], a

    ld  a, 1
    ld  [wCamTileDirty], a

.done:
    ret

;@param b: frameLeftDelta
;@param c: frameRightDelta 
;@param d: frameTopDelta
;@param e: frameBottomDelta
Camera_Init_Deadzone:
    
    ; Init wFrameLeftDelta, wFrameRightDelta 
    ld  hl, wFrameLeftDelta
    ld  [hl], b
    ld  hl, wFrameRightDelta
    ld  [hl], c

    ; wDeadZoneWidth = 160 - wFrameLeftDelta - wFrameRightDelta
    ld  hl, 160
    ld  a, [wFrameLeftDelta]
    cpl
    inc a
    ld  c, a
    ld  b, $FF  ; sign extend
    add hl, bc  ; hl = 160 - wFrameLeftDelta

    ld  a, [wFrameRightDelta]
    cpl
    inc a
    ld  c, a
    ld  b, $FF  ; sign extend
    add hl, bc  ; hl = 160 - wFrameLeftDelta - wFrameRightDelta

    ld  b, h
    ld  c, l

    ld  hl, wDeadZoneWidth
    ld  [hl], c
    inc hl
    ld  [hl], b

    ; Init wFrameTopDelta, wFrameBottomDelta
    ld  hl, wFrameTopDelta
    ld  [hl], d
    ld  hl, wFrameBottomDelta
    ld  [hl], e

    ; vertical deadzone = 144 - wFramwTopDelta - wFrameBottomDelta
    ld  hl, 144
    ld  a, [wFrameTopDelta]
    cpl
    inc a
    ld  c, a
    ld  b, $FF
    add hl, bc  ; hl = 144 - wFrameTopDelta

    ld  a, [wFrameBottomDelta]
    cpl
    inc a
    ld  c, a
    ld  b, $FF
    add hl, bc

    ld  b, h
    ld  c, l

    ld  hl, wDeadZoneHeight
    ld  [hl], c
    inc hl
    ld  [hl], b

    ret

;@param bc: Player's world position X (in pixels)
;@param de: Player's world position Y (in pixels)
Camera_Update:
    ; Update the camera's position based on the player's position and the defined dead zone.
    ; The camera will try to keep the player within the dead zone, but will not move if the player is within it.
    ; The "dead zone" is referred to as the "frame". The idea is:
    ; if the player is to the left of the left side of the frame, then move the frame to the left.
    ; if the player is to the right of the right side of the frame, then move the frame to the right.
    ; 
    ; Apply the same offsets vertically.


    ; Save previous camera position
    ld hl, wCamPosX
    ld a, [hli]
    ld [wCamPosXPrev], a
    ld a, [hl]
    ld [wCamPosXPrev + 1], a

    ld hl, wCamPosY
    ld a, [hli]
    ld [wCamPosYPrev], a
    ld a, [hl]
    ld [wCamPosYPrev + 1], a

    ; Clear wCamMoveDelta
    xor a
    ld  [wCamMoveDelta], a

    ; Calculate desired camera position based on player position and dead zone

    ; Calculate frame left using current camera position + offset
    ;           check if the player's position is smaller; if it is,
    ;           we'll need to adjust the camera position.
    
    push bc                     ; save previous bc

    ld  a, [wFrameLeftDelta]
    ld  c, a
    ld  b, 0
    ld  a, [wCamPosX]           ; low byte into l
    ld  l, a
    ld  a, [wCamPosX + 1]       ; high byte into h
    ld  h, a
    add hl, bc                  ; hl now has cam pos + left offset

    pop bc                      ; bc now again has player's world position X

    ; Signed 16-bit compare: frame-left (hl) vs player X (bc)
    SIGNED_CMP16 h, l, b, c
    jr  c, .FrameLeftOK         ; if b's high byte is larger, the frame's left side is in the correct place.
    jr  nz, .AdjustToFrameLeft  ; if b's high byte is smaller, (so the player is to the left of the left frame, we'll need to adjust)
    jr  z, .FrameLeftOK         ; if the low byte is the same, player is just on the left frame boundary, let's say that's OK
                                ; otherwise (high bytes are equal, but low bytes, player's world pos X is smaller than c:
.AdjustToFrameLeft:
    ld  h, b
    ld  l, c                    ; hl now has player's world position X
    ld  a, [wFrameLeftDelta]
    cpl                         ; negate a
    inc a

    push bc

    ld  c, a                    ; load "a" into the low byte of bc
    ld  b, $00                  ; assume positive result
    bit 7, c                    ; check if bit 7 is set (negative)
    jr  z, .signExtendLeft      ; if clear, b = $00 is correct
    ld  b, $FF                  ; if set, sign extend with $FF
.signExtendLeft:
    add hl, bc                  ; subtract [wFrameLeftDelta] minus player's world position X to find the new cam pos.

    ; hl now contains the new camera position, so set it
    ; we'll need hl for the addressing, so use bc as temp storage

    ld  b, h
    ld  c, l

    ; ... but clamp it to non-negative
    bit 7, b
    jr  z, .tmp_jmp_01
    ld  bc, 0

.tmp_jmp_01:
    ld  hl, wCamPosX
    ld  [hl], c                 ; store low byte first

    ld  a, c
    ldh [wBC], a                ; also store into wBC

    inc hl
    ld  [hl], b                 ; store high byte second

    ld  a, b
    ld  [wBC + 1], a            ; also store into wBC
   
    pop bc

    ld  a, %0000_0001           ; if we're adjusting to frame left, then we must have
    ld  [wCamMoveDelta], a      ; moved to the left

    jr  .AdjustVerticalPosition

.FrameLeftOK:                   ; if frame left is OK, let's check if frame right is OK too
    push bc                     ; save "player's position X as bc" 

    ; right offset = left frame delta + deadzoneWidth
    ld  a, [wCamPosX]
    ld  l, a
    ld  a, [wCamPosX + 1]
    ld  h, a                   ; hl = wCamPosX

    ld  a, [wFrameLeftDelta]
    ld  c, a
    ld  b, 0

    add hl, bc      ; hl = wCamPosX + wFrameLeftDelta

    ld  a, [wDeadZoneWidth]
    ld  c, a
    ld  a, [wDeadZoneWidth + 1]
    ld  b, a        ; bc = deadZoneWidth

    add hl, bc      ; hl = wCamPosX + wFrameLeftDelta + wDeadZoneWidth

    pop bc

    ; Signed 16-bit compare: frame-right (hl) vs player X (bc)
    SIGNED_CMP16 h, l, b, c
    jr  c, .AdjustToFrameRight  ; if carry, we need to adjust to the frame right
    jr  .FrameRightOK

.AdjustToFrameRight:
    ld  h, b
    ld  l, c                    ; hl now has player's world position X

    ld  a, [wFrameRightDelta]
    ld  c, a
    ld  b, 0                    ; bc = wFrameRightDelta

    add hl, bc                  ; hl = player's world pos X + wFrameRightDelta (= this is where the screen shall end)

    ; ok, so 160 in binary is 128 + 32 = %1010_0000
    ; in 2's complement, this is:
    ;                       %1111_1111 %0101_1111 + 1      
    ;                       %1111_1111 %0110 0000         
    ;                       $F    F    6     0              
    push bc
    ld  bc, $FF60           ; bc = -160
    add hl, bc              ; hl = playerPosX + wFrameRightDelta - 160

    ld  b, h
    ld  c, l

    bit 7, b
    jr  z, .tmp_jmp_02
    ld  bc, 0

.tmp_jmp_02:
    ld  hl, wCamPosX
    ld  [hl], c                 ; store low byte first

    inc hl
    ld  [hl], b                 ; then store high byte

    ld  a, %0000_0010           ; we moved to the right
    ld  [wCamMoveDelta], a

    pop bc
.FrameRightOK:
.AdjustVerticalPosition:
    ; Check frame top using current camera position + top offset.
    ; If player is above the top boundary, move camera up.
    push de

    ld  a, [wFrameTopDelta]
    ld  e, a
    ld  d, 0

    ld  a, [wCamPosY]
    ld  l, a
    ld  a, [wCamPosY + 1]
    ld  h, a

    add hl, de                  ; hl now has cam pos + top offset

    pop de                      ; de now again has player's world position Y
    ; Signed 16-bit compare: frame-top (hl) vs player Y (de)
    SIGNED_CMP16 h, l, d, e
    jr  c, .FrameTopOK          ; frame top < player Y -> player is below top boundary
    jr  nz, .AdjustToFrameTop   ; frame top > player Y -> player is above top boundary
    jr  z, .FrameTopOK          ; exactly on boundary is also OK

.AdjustToFrameTop:
    ld  h, d
    ld  l, e                    ; hl now has player's world position Y
    ld  a, [wFrameTopDelta]
    cpl
    inc a

    push de

    ld  e, a                    ; low byte of -(top delta)
    ld  d, $00                  ; assume positive result
    bit 7, e                    ; check if bit 7 is set (negative)
    jr  z, .signExtendTop       ; if clear, d = $00 is correct
    ld  d, $FF                  ; if set, sign extend with $FF
.signExtendTop:
    add hl, de                  ; hl = player Y - top delta

    pop de

    push bc
    
    ld  b, h
    ld  c, l

    bit 7, b
    jr  .tmp_jmp_03
    ld  bc, 0

.tmp_jmp_03:
    ld  hl, wCamPosY
    ld  [hl], c
    inc hl
    ld  [hl], b

    ld  a, [wCamMoveDelta]
    or  a, %0000_0100           ; we moved up
    ld  [wCamMoveDelta], a

    pop bc

    jr  .VerticalDone

.FrameTopOK:
    ; Check frame bottom using current camera position + bottom offset.
    ; If player is below the bottom boundary, move camera down.
    push de

    ld  a, [wCamPosY]
    ld  l, a
    ld  a, [wCamPosY + 1]
    ld  h, a                    ; hl = wCamPosY

    ld  a, [wFrameTopDelta]
    ld  c, a
    ld  b, 0
    add hl, bc                  ; hl = wCamPosY + wFrameTopDelta

    ld  a, [wDeadZoneHeight]
    ld  c, a
    ld  a, [wDeadZoneHeight + 1]
    ld  b, a                    ; bc = wDeadZoneHeight
    add hl, bc                  ; hl = wCamPosY + wFrameTopDelta + wDeadZoneHeight

    pop de
    ; Signed 16-bit compare: frame-bottom (hl) vs player Y (de)
    SIGNED_CMP16 h, l, d, e
    jr  c, .AdjustToFrameBottom ; frame bottom < player Y -> player is below bottom boundary
    jr  .VerticalDone

.AdjustToFrameBottom:
    ; wCamPosY = playerPosY + wFrameBottomDelta - 144
    ld  h, d
    ld  l, e                    ; hl = player pos Y

    ld  a, [wFrameBottomDelta]
    ld  c, a
    ld  b, 0
    add hl, bc                  ; hl = player Pos Y + wFrameBottomDelta

    ; -144 is:
    ;               128 + 16 = %1001_0000
    ;                          %0110_1111 + 1 
    ;                          %0111_0000
    ;              %1111_1111  %0111_0000
    ;              $F    F     $7 0 
    ld bc, $FF70
    add hl, bc

    ld  b, h
    ld  c, l

    bit 7, b
    jr  z, .tmp_jmp_04
    ld  bc, 0

.tmp_jmp_04:    
    ld  hl, wCamPosY
    ld  [hl], c
    inc hl
    ld  [hl], b

    ld  a, [wCamMoveDelta]
    or  a, %0000_1000       ; we moved down
    ld  [wCamMoveDelta], a

.VerticalDone:
    
    ; Load into bx [wCamPosX], into de [wCamPosY], and calculate new
    ; camera tile positions
    ld  hl, wCamPosX
    ld  c, [hl]
    inc hl
    ld  b, [hl]

    ld  hl, wCamPosY
    ld  e, [hl]
    inc hl
    ld  d, [hl]
    call UpdateCamTilePos

    ret