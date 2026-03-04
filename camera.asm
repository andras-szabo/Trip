SECTION "CameraVariables", WRAM0
    wCamPosX: dw            ; World coordinates (in pixels)
    wCamPosY: dw            ; World coordinates (in pixels)

    wCamPosXPrev: dw         ; Previous frame's camera position (world coords)
    wCamPosYPrev: dw         ; Previous frame's camera position (world coords)

    wDesiredPosX: dw        ; The position the camera is trying to reach (world coords)
    wDesiredPosY: dw        ; The position the camera is trying to reach (world coords)

    wFrameLeftDelta: db     ; Distance from cam pos to the left of the frame
    wFrameRightDelta: db    ; Distance from cam pos to the right of the frame
    deadZoneWidth: db       ; The ideal width of the frame; this should not change even temporarily

    wFrameTopDelta: db      ; Distance from cam pos to the top of the frame
    wFrameBottomDelta: db   ; Distance from cam pos to the bottom of the frame
    deadZoneHeight: db      ; The ideal height of the frame; this should not change even temporarily

SECTION "CameraCode", ROM0

;@param bc: Camera's initial position X
;@param de: Camera's initial position Y
Camera_Init_Position:
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

    ret

;@param b: frameLeftDelta
;@param c: deadzone width
;@param d: frameTopDelta
;@param e: deadzone height
Camera_Init_Deadzone:
    ld  hl, wFrameLeftDelta
    ld  [hl], b
    ld  hl, deadZoneWidth
    ld  [hl], c

    ld  a, [wFrameLeftDelta]
    ld  b, a
    ld  a, [deadZoneWidth]
    add b
    ld  hl, wFrameRightDelta
    ld  [hl], a

    ld  hl, wFrameTopDelta
    ld  [hl], d
    ld  hl, deadZoneHeight
    ld  [hl], e

    ld  a, [wFrameTopDelta]
    ld  b, a
    ld  a, [deadZoneHeight]
    add b
    ld  hl, wFrameBottomDelta
    ld  [hl], a

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

    ; Is there a way we can do this comparison without jumps?
    ; eg:   - compare high bytes
    ;           - if b larger           -> finish, we're good.
    ;           - if b smaller (nz)     -> we'll need to adjust
    ;           - otherwise, chek low byte
    ;               - if c larger       -> finish, we're good
    ;               - if b smaller (nz) -> we'll need to adjust
    ;       
    ;       .We'll need to adjust based on left
    ;           - adjust (desired) cam position x to be player position - left delta
    ;
    ;       .We're good:
    ;           - check frame right 
    ;      

    pop bc                      ; bc now again has player's world position X
    ld  a, h                    ; first check the high byte
    cp  b                       ; set c, if player's world position X is larger than the frame left border (high byte)
    jr  c, .FrameLeftOK         ; if b's high byte is larger, the frame's left side is in the correct place.
    jr  nz, .AdjustToFrameLeft  ; if b's high byte is smaller, (so the player is to the left of the left frame, we'll need to adjust)
    ld  a, l                    ; if undecided, let's look at the low byte
    cp  c
    jr  c, .FrameLeftOK         ; if b's low byte is larger -> that's fine, b/c we know the high byte is the same.
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

    ld  hl, wCamPosX
    ld  [hl], c                 ; store low byte first
    inc hl
    ld  [hl], b                 ; store high byte second
    
    pop bc
    jr  .AdjustVerticalPosition

.FrameLeftOK:                   ; if frame left is OK, let's check if frame right is OK too
    push bc                     ; save "player's position X as bc" 

    ld  a, [wFrameRightDelta]
    ld  c, a
    ld  b, 0

    ld  a, [wCamPosX]
    ld  l, a
    ld  a, [wCamPosX + 1]
    ld  h, a

    add hl, bc                  ; hl now has cam pos + right offset

    pop bc

    ld  a, h                    ; first check the high byte
    cp  b                       ; set c, if the player's world position X is larger than the frame right border (high byte)
    jr  c, .AdjustToFrameRight  ; if carry, we need to adjust to the frame right
    jr  nz, .FrameRightOK       ; if not carry, and not Z, then c must be smaller, so we're good, so far as the right side is concerned
    ld  a, l                    ; otherwise, let's look at the low byte
    cp  c
    jr  c, .AdjustToFrameRight  ; if the player position is larger, we'll have to adjust
    jr  z, .FrameRightOK        ; if the same, we'll accept it as OK; otherwise we'll have to adjust

.AdjustToFrameRight:
    ld  h, b
    ld  l, c                    ; hl now has player's world position X
    ld  a, [wFrameRightDelta]
    cpl
    inc a
    push bc
    ld  c, a
    ld  b, $00                  ; assume positive result
    bit 7, c                    ; check if bit 7 is set (negative)
    jr  z, .signExtendRight     ; if clear, b = $00 is correct
    ld  b, $FF                  ; if set, sign extend with $FF
.signExtendRight:
    add hl, bc                  ; hl now has player's world position X - right delta
    pop bc

.FrameRightOK:
    push bc

    ld  b, h
    ld  c, l
    ld  hl, wCamPosX
    ld  [hl], c                 ; store low byte first
    inc hl
    ld  [hl], b                 ; then store high byte

    pop bc

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
    ld  a, h                    ; first check the high byte
    cp  d                       ; compare frame top (h) with player Y high (d)
    jr  c, .FrameTopOK          ; frame top < player Y -> player is below top boundary
    jr  nz, .AdjustToFrameTop   ; frame top > player Y -> player is above top boundary
    ld  a, l                    ; if equal, compare low bytes
    cp  e
    jr  c, .FrameTopOK          ; frame top low < player low -> player is below top boundary
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

    ld  hl, wCamPosY
    ld  [hl], c
    inc hl
    ld  [hl], b

    pop bc

    jr  .VerticalDone

.FrameTopOK:
    ; Check frame bottom using current camera position + bottom offset.
    ; If player is below the bottom boundary, move camera down.
    push de

    ld  a, [wFrameBottomDelta]
    ld  e, a
    ld  d, 0

    ld  a, [wCamPosY]
    ld  l, a
    ld  a, [wCamPosY + 1]
    ld  h, a

    add hl, de                  ; hl now has cam pos + bottom offset

    pop de
    ld  a, h                    ; compare frame bottom high with player high
    cp  d
    jr  c, .AdjustToFrameBottom ; frame bottom < player Y -> player is below bottom boundary
    jr  nz, .VerticalDone       ; frame bottom > player Y -> inside boundary
    ld  a, l                    ; high bytes are equal, compare low bytes
    cp  e
    jr  c, .AdjustToFrameBottom ; frame bottom low < player low -> below boundary
    jr  z, .VerticalDone        ; exactly on boundary is OK

.AdjustToFrameBottom:
    ld  h, d
    ld  l, e                    ; hl now has player's world position Y
    ld  a, [wFrameBottomDelta]
    cpl
    inc a

    push de
    ld  e, a
    ld  d, $00                  ; assume positive result
    bit 7, e                    ; check if bit 7 is set (negative)
    jr  z, .signExtendBottom    ; if clear, d = $00 is correct
    ld  d, $FF                  ; if set, sign extend with $FF
.signExtendBottom:
    add hl, de                  ; hl = player Y - bottom delta
    pop de

    push bc
    ld  b, h
    ld  c, l

    ld  hl, wCamPosY
    ld  [hl], c
    inc hl
    ld  [hl], b

    pop bc

.VerticalDone:

    ret