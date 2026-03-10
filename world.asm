DEF SHADOW_MAP_WIDTH EQU 32
DEF SHADOW_MAP_HEIGHT EQU 32
DEF SHADOW_MAP_BUFFER_SIZE EQU SHADOW_MAP_WIDTH * SHADOW_MAP_HEIGHT

SECTION "ShadowMapBuffer", WRAM0
wShadowMapBuffer:    ds  SHADOW_MAP_BUFFER_SIZE

SECTION "WorldCode", ROM0
;@param [wCamMoveDelta]     - in which direction have we moved? low bits: DOWN|UP|RIGHT|LEFT
;@param [wCamTileDirty]     - did we swap tiles?
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

    ld  a, [wCamMoveDelta]
    and a, %0000_0001
    jr  z, .not_moved_right
    ld  a, SHADOW_MAP_WIDTH  ; add shadow map width
    jr  .x_delta_is_set

.not_moved_right:
    ld  a, [wCamMoveDelta]
    and a, %0000_0010
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
    ld  l, a
    ld  h, 0                    ; hl now has the delta
    add hl, bc                  ; hl now has new tile position

    bit 7, h                    ; if negative, col to load is the last one
    jr  z, .column_to_load_is_not_the_last
    ld  a, 31                   ;
    jr  .column_to_load_set
.column_to_load_is_not_the_last:
    ld  a, l
    and a, %0001_1111           ; modulo 32
.column_to_load_set:
                                ; column-to-load is now in a; so let's find out which
                                ; row is the first one to load

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
    rl  b   ; rotate left through carry

    sla c   ; shift left arithmatically = mul by 2, set carry           ; mul by 4
    rl  b   ; rotate left through carry

    sla c   ; mul by 8
    rl  b   ;

    sla c   ; mul by 16
    rl  b   

    sla c   ; mul by 32
    rl  b

    ld  h, b
    ld  l, c    ; hl = bc
    ld  c, d    ; c = column-to-load
    ld  b, 0
    add hl, bc  ; hl = column-to-load + (row-to-load * 32)
    ld  b, h
    ld  c, l    ; bc = column-to-load + (row-to-load * 32) == offset

    ; let's find the starting address
    ld  hl, wShadowMapBuffer
    add hl, bc                  ; hl is now pointing to the start of the
                                ; column we need to load

    ; We'll need to use bc for incrementing hl, so let's keep track of the loop
    ; in d

    ld  b, 0
    ld  c, 32       ; bc is now 32
    ld  d, 0        ; we'll use d as a counter

.column_copy_loop:
    ; tile to load x = [wCamTilePosX] 
    ; tile to load y = [wCamTilePosY + d]
    ld  [hl], a     ; load tile data into shadow map
    add hl, bc      ; jump to the next tile
                    ; except with this we could have jumped out of
                    ; the valid range, so we need to clamp it ffs

    inc d           ; increment the counter
    ld  a, 32       ; check if d == 32
    cp  d
    jr  nz, .column_copy_loop



.not_moved_along_x: */
    ret


