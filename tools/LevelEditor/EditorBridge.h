#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Minimal constants mirrored from playfield.h
#define TILENUM_MASK       0x07ff
#define TILE_SIZE          32
#define TILE_SIZE_SH       5
#define TILE_PRIORITY_MASK  0x8000
#define TILE_PRIORITY_MASK2 0x4000

// Alt tile types (mirrored from playfield.h)
enum
{
    ALT_TILE_NONE,
    ALT_TILE_DIR_UP,
    ALT_TILE_DIR_UP_RIGHT,
    ALT_TILE_DIR_RIGHT,
    ALT_TILE_DIR_DOWN_RIGHT,
    ALT_TILE_DIR_DOWN,
    ALT_TILE_DIR_DOWN_LEFT,
    ALT_TILE_DIR_LEFT,
    ALT_TILE_DIR_LEFT_UP,
    ALT_TILE_DIR_STOP,
    ALT_TILE_DIR_LOOP
};

#define ITEM_IN_USE        0x8000
#define ITEM_MEMORY        0x6000
#define ITEM_NUM           0x0fff


// Palette
const uint32_t* EB_GetPaletteRGBA32(void);

// Tileset
int EB_GetNumTiles(void);
const uint8_t* EB_GetTilePixels(int tileIndex);
const uint8_t* EB_GetPriorityColorMask(void);

// Map access
void EB_GetMapSize(int* outW, int* outH);
uint16_t EB_GetTile(int x, int y);
void EB_SetTile(int x, int y, uint16_t v);
uint8_t* EB_GetAltRow(int y);

// Items
int EB_GetNumItems(void);
void EB_GetItem(int index, int32_t* x, int32_t* y, int16_t* type, uint8_t parm[4]);
void EB_SetItem(int index, int32_t x, int32_t y, int16_t type, const uint8_t parm[4]);

// Pomme bootstrap + dataspec
void EB_InitPomme(void);
void EB_SetDataSpecFromHostPath(const char* systemFolderHostPath);

// Tile attributes (bits only)
uint16_t EB_GetTileAttribBits(int tileIndex);
void EB_SetTileAttribBits(int tileIndex, uint16_t bits);

// Animation advance
void EB_AdvanceAnimation(void);

// Save map to PACK_TYPE_NONE packed file at host path
void EB_SaveMapToPath(const char* outPath);

#ifdef __cplusplus
}
#endif
