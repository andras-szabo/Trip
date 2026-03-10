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

    ; switch (wCamMoveDelta)
    ;   case LEFT: deltaX = -1; break;
    ;   case RIGHT: deltaX = 1; break;
    ;   case UP: deltaY = -1;   break;
    ;   case DOWN: deltaY = 1;  break;
    
    ; FFS. We have world tile position of the player;
    ; that position % 22 shows where the player is right now.
    ; whenever we move to the right, we need to add 22, so we
    ; and take the modulo; that's the number of the column
    ; that we have to fill in.
    
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

    ; let's find the starting address
    ld  c, a
    ld  b, 0
    ld  hl, wShadowMapBuffer
    add hl, bc                  ; hl is now pointing to the start of the column
                                ; we'll need to load

    ; We'll need to use bc for incrementing hl, so let's keep track of the loop
    ; in d

    ld  c, 32       ; bc is now 32
    ld  d, 0        ; we'll use d as a counter

.column_copy_loop:
    ; tile to load x = [wCamTilePosX] 
    ; tile to load y = [wCamTilePosY + d]
    ld  [hl], a     ; load tile data into shadow map
    add hl, bc      ; jump to the next tile
    inc d           ; increment the counter
    ld  a, 32       ; check if d == 32
    cp  d
    jr  nz, .column_copy_loop



.not_moved_along_x:
    ret


