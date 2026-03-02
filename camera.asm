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

;@param bc: Player's world position X (in pixels)
;@param de: Player's world position Y (in pixels)
Camera_Update:
    ; Update the camera's position based on the player's position and the defined dead zone.
    ; The camera will try to keep the player within the dead zone, but will not move if the player is within it.

    ; Save previous camera position
    ld hl, wCamPosX
    ld a, [hl]
    ld [wCamPosXPrev], a
    inc hl
    ld a, [hl]
    ld [wCamPosXPrev + 1], a

    ld hl, wCamPosY
    ld a, [hl]
    ld [wCamPosYPrev], a
    inc hl
    ld a, [hl]
    ld [wCamPosYPrev + 1], a

    ; Calculate desired camera position based on player position and dead zone
    
    ; Calculate player's position relative to camera
    ; check if the relative position is inside the dead zone.
    ;   calculate new "left" position by adding cam pos + wFrameLeftDelta
    ;   check if player position is less than this
    ;   calculate new "right" position by adding cam pos + wFrameRightDelta
    ;   check if player position is more than this
    


    ; Move camera towards desired position (this would involve more code to smoothly move the camera towards the desired position)

    ret