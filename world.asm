DEF WORLD_BUFFER_WIDTH  EQU 22
DEF WORLD_BUFFER_HEIGHT EQU 20
DEF WORLD_BUFFER_SIZE   EQU WORLD_BUFFER_WIDTH * WORLD_BUFFER_HEIGHT

SECTION "WorldBuffer", WRAM0
wWorldMapBuffer:    ds  WORLD_BUFFER_SIZE

SECTION "WorldCode", ROM0
;@param [wCamMoveDelta]     - in which direction have we moved? low bits: DOWN|UP|RIGHT|LEFT
;@param [wCamTileDirty]     - did we swap tiles?
;@param [wCamTilePosX]      - cam tile pos x
;@param [wCamTilePosY]      - cam tile pos y, indeed. a ver.
UpdateShadowMap:
    ; Let's assume that [wCamTileDirty] != 0
    ; Then the question is, in which direction have we moved. This is how we'd write it in a
    ; sane programming language:

    ; switch (wCamMoveDelta)
    ;   case LEFT: deltaX = -2; break;
    ;   case RIGHT: deltaX = 2; break;
    ;   case UP: deltaY = -2;   break;
    ;   case DOWN: deltaY = 2;  break;
    ;
    ; tile_column_to_load = wCamTilePosX + deltaX   ; because we have a margin of 2 tiles, right?
    ;                                               ; hence the 22x20 world (shadow) map
    ;
    ; if we moved right, tile_column_to_load += screen width
    ;
    ; if tile_column_to_load is negative, flip it, and add 22
    ; if it's positive, modulo 22.
    ld  a, [wCamMoveDelta]
    and a, %0000_0001
    jr  z, .not_moved_right
    ld  a, 2
    jr  .x_delta_is_set

.not_moved_right:
    ld  a, [wCamMoveDelta]
    and a, %0000_0010
    jr  z, .x_delta_is_set
    ; -2 in 2's complement: 
    ;       1111_1101  +1 =
    ;       1111_1110
    ld  a, $FE                  ; a is now -2

.x_delta_is_set:
    or  a
    jr  z, .not_moved_along_x

    ; TBC
    ; We need to think about how the shadow map maps to camera position,
    ; like, do we just subtract 2?
    ;

.not_moved_along_x:
    ret

; Lookup table of 20 pointers, each pointing
; to the start of the next row in the world buffer
SECTION "WorldBufferLUT", ROM0
wWorldMap_Rows:
    dw  0
    dw  WORLD_BUFFER_WIDTH * 2
    dw  WORLD_BUFFER_WIDTH * 2 * 2
    dw  WORLD_BUFFER_WIDTH * 2 * 3
    dw  WORLD_BUFFER_WIDTH * 2 * 4
    dw  WORLD_BUFFER_WIDTH * 2 * 5
    dw  WORLD_BUFFER_WIDTH * 2 * 6
    dw  WORLD_BUFFER_WIDTH * 2 * 7
    dw  WORLD_BUFFER_WIDTH * 2 * 8
    dw  WORLD_BUFFER_WIDTH * 2 * 9
    dw  WORLD_BUFFER_WIDTH * 2 * 10
    dw  WORLD_BUFFER_WIDTH * 2 * 11
    dw  WORLD_BUFFER_WIDTH * 2 * 12
    dw  WORLD_BUFFER_WIDTH * 2 * 13
    dw  WORLD_BUFFER_WIDTH * 2 * 14
    dw  WORLD_BUFFER_WIDTH * 2 * 15
    dw  WORLD_BUFFER_WIDTH * 2 * 16
    dw  WORLD_BUFFER_WIDTH * 2 * 17
    dw  WORLD_BUFFER_WIDTH * 2 * 18
    dw  WORLD_BUFFER_WIDTH * 2 * 19
    dw  WORLD_BUFFER_WIDTH * 2 * 20
    dw  WORLD_BUFFER_WIDTH * 2 * 21
    dw  WORLD_BUFFER_WIDTH * 2 * 22
.End:

