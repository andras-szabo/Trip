DEF WORLD_BUFFER_WIDTH  EQU 22
DEF WORLD_BUFFER_HEIGHT EQU 20
DEF WORLD_BUFFER_SIZE   EQU WORLD_BUFFER_WIDTH * WORLD_BUFFER_HEIGHT

SECTION "WorldBuffer", WRAM0
wWorldMapBuffer:    ds  WORLD_BUFFER_SIZE

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
    dw  WORLD_BUFFER_wIDTH * 2 * 8
    dw  WORLD_BUFFER_wIDTH * 2 * 9
    dw  WORLD_BUFFER_wIDTH * 2 * 10
    dw  WORLD_BUFFER_wIDTH * 2 * 11
    dw  WORLD_BUFFER_wIDTH * 2 * 12
    dw  WORLD_BUFFER_wIDTH * 2 * 13
    dw  WORLD_BUFFER_wIDTH * 2 * 14
    dw  WORLD_BUFFER_wIDTH * 2 * 15
    dw  WORLD_BUFFER_wIDTH * 2 * 16
    dw  WORLD_BUFFER_wIDTH * 2 * 17
    dw  WORLD_BUFFER_wIDTH * 2 * 18
    dw  WORLD_BUFFER_wIDTH * 2 * 19
    dw  WORLD_BUFFER_wIDTH * 2 * 20
    dw  WORLD_BUFFER_wIDTH * 2 * 21
    dw  WORLD_BUFFER_wIDTH * 2 * 22
.End:

