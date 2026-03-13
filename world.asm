DEF SHADOW_MAP_WIDTH EQU 32
DEF SHADOW_MAP_HEIGHT EQU 32
DEF SHADOW_MAP_BUFFER_SIZE EQU SHADOW_MAP_WIDTH * SHADOW_MAP_HEIGHT

SECTION "ShadowMapBuffer", WRAM0
wShadowMapBuffer:    ds  SHADOW_MAP_BUFFER_SIZE

SECTION "WorldCode", ROM0
;@param [wCamMoveDelta]     - in which direction have we moved? low bits: DOWN|UP|RIGHT|LEFT
;@param [wCamTileDirty]     - did we move to a new tile?
;@param [wCamTilePosX]      - cam tile pos x
;@param [wCamTilePosY]      - cam tile pos y, indeed. a ver.
UpdateShadowMap:
    ; Let's assume that [wCamTileDirty] != 0
    ; Then the question is, in which direction have we moved. This is how we'd write it in a
    ; sane programming language:

    ; Because of how the tile map wraps around, we need to keep track of the camera's
    ; current x and y tile _in_the_shadow_map; which is [wCamTilePosX] % 32, and [wCamTilePosY] % 32.
    ; these are the starting tiles.
    ;
    ; Then, check in which direction we moved.
    ; If along x, we have to load a new column; if along y, we have to load a new row, d'uh.

    xor a
    ldh [wColumnToLoad], a

    ld  a, [wCamMoveDelta]
    and a, %0000_0010
    jr  z, .not_moved_right
    ld  a, 20; add screen width
    jr  .x_delta_is_set

.not_moved_right:
    ld  a, [wCamMoveDelta]
    and a, %0000_0001
    jr  z, .x_delta_is_set
    ; -1 in 2's complement: 
    ;       1111_1110  +1 =
    ;       1111_1111
    ld  a, $FF                  ; a is now -1

.x_delta_is_set:
    or  a
    jr  z, .not_moved_along_x

    ld  d, a                    
    ld  a, [wCamTilePosX]
    ld  c, a
    ld  a, [wCamTilePosX + 1]
    ld  b, a                    ; bc now has wCamTilePosX

    ld  l, d
    ld  h, 0                    ; hl now has the delta
    bit 7, d                    ; except we have to sign extend
    jr  z, .skip_sign_extend_hl
    ld  h, $FF

.skip_sign_extend_hl:
    add hl, bc                  ; hl now has new tile position
    ld  a, l
    and a, %0001_1111           ; modulo 32, I think this should work even if l was negative
                                
                                ; column-to-load is now in a; so let's find out which
                                ; row is the first one to load

    ldh [wColumnToLoad], a
    ld  d, a                    ; d = column-to-load

    ld  a, [wCamTilePosY]
    and a, %0001_1111           ; modulo 32
    ld  e, a                    ; store this in e
                                ; de now has column and row to start loading at.

    ; TODO - use the logic in WriteTileToVRAM

    ; Starting address is:
    ; [column_to_load] + [row_to_load * 32]
    ld  c, e                    ; c = row_to_load
    ld  b, 0                    ; bc = row_to_load

    ; Maybe instead of these we could actually use a lookup table:
    ; lut_start + row_to_load * 2
    sla c   ; shift left arithmetically = multiply by 2, set carry      ; mul by 2
    ;rl  b  ; rotate left through carry -> technically this should not be needed,
            ; because the number we're starting with is < 32, so at most the 32
            ; bit is now 1; with the next rotation, 64, then 128, and only THEN
            ; do we have to worry about carry

    sla c   ; shift left arithmatically = mul by 2, set carry           ; mul by 4
    ;rl  b  ; rotate left through carry (see above, at most bit 6 (64) is now set)

    sla c   ; mul by 8
    ;rl  b  ; at most bit 7 (128) is set

    sla c   ; mul by 16
    rl  b   ; now we do have to rotate through carry

    sla c   ; mul by 32
    rl  b

    ld  h, b
    ld  l, c    ; hl = bc
    ld  c, d    ; c = column-to-load
    ld  b, 0
    add hl, bc  ; hl = column-to-load + (row-to-load * 32)
    ld  b, h
    ld  c, l    ; bc = column-to-load + (row-to-load * 32) == offset

    ld  d, 0                    ; this will keep track of the loop
    ; let's find the address to load to


.column_copy_loop:
    ld  hl, wShadowMapBuffer
    add hl, bc                  ; hl is now pointing to the memory
                                ; address where we have to start loading

    ; tile to load x = [wCamTilePosX] 
    ; tile to load y = [wCamTilePosY + d]

    ;-----------------------------------------------------------------------
    ; TODO: load into a the tile from real world
    ;-----------------------------------------------------------------------
    ; For now, let's just load ([wCamTilePosX] / 8) % 4
    ; ... and just for fun, add d

    ldh a, [wColumnToLoad]
    add d  

    sra a   ; div by 2
    sra a   ; div by 4
    sra a   ; div by 8

    and a, %0000_0011   ; mod 4 just in case
    ;-----------------------------------------------------------------------
    ; TODO: load into a the tile from real world
    ;-----------------------------------------------------------------------

    ld  [hl], a     ; load tile data into shadow map
                    
    ld  a, c        ; move on to the next tile: increment the offset by 32
    add 32
    ld  c, a
    jr  nc, .skip_offset_carry
    inc b           ; if carry, increment b
.skip_offset_carry:
                    ; bc now has the new offset; but we have to clamp it
                    ; to a valid region of 32x32 = 1024 bytes. I think we
                    ; can achieve that by leaving c as it is, and discarding
                    ; high bits of b
    ld  a, b
    and a, %0000_0011   ; taking bits 256 and 512
    ld  b, a

    inc d           ; increment the counter
    ld  a, 32       ; check if d == 32
    cp  d
    jr  nz, .column_copy_loop

.not_moved_along_x:
    ret


;@param a: column to copy
;@uses a, bc, d, hl
CopyColumnToTileMap:
    ld  d, 0        ; loop counter

    ld  c, a            
    ld  b, 0        ; bc: column to load, 0 <= a <= 31; this will also be
                    ; the starting offset
    
.next_row:
    ld  hl, wShadowMapBuffer
    add hl, bc
    ld  a, [hl]     ; a now contains the value in the shadow map buffer

    ld  hl, $9800
    add hl, bc      ; hl now has the target
    ld  [hl], a

    ld  a, c
    add 32
    ld  c, a
    jr  nc, .skip_carry
    inc b

.skip_carry:
    inc d
    ld  a, d
    cp  32
    jr  nz, .next_row

    ret

; Load a striped pattern for now
InitShadowMap:
    xor a
    ld  d, a
    ld  hl, wShadowMapBuffer
    ld  bc, 32 * 32

.next_tile:
    ld  a, d

    sra a
    sra a
    sra a
    and a, %0000_0011

    inc d

    ld  [hli], a
    dec bc
    ld  a, b
    or  c
    jr  nz, .next_tile

    ret