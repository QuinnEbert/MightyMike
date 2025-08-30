#include "externs.h"
#include "playfield.h"
#include "structures.h"

#include <PommeInit.h>
#include <PommeFiles.h>

const uint32_t* EB_GetPaletteRGBA32(void)
{
    return gGamePalette.finalColors32;
}

int EB_GetNumTiles(void)
{
    return MM_GetNumTiles();
}

const uint8_t* EB_GetTilePixels(int tileIndex)
{
    return MM_GetTilePixelsForTile(tileIndex);
}

const uint8_t* EB_GetPriorityColorMask(void)
{
    return MM_GetPriorityColorMask();
}

void EB_GetMapSize(int* outW, int* outH)
{
    if (outW) *outW = gPlayfieldWidth >> TILE_SIZE_SH;
    if (outH) *outH = gPlayfieldHeight >> TILE_SIZE_SH;
}

uint16_t EB_GetTile(int x, int y)
{
    return gPlayfield[y][x];
}

void EB_SetTile(int x, int y, uint16_t v)
{
    gPlayfield[y][x] = v;
}

uint8_t* EB_GetAltRow(int y)
{
    return MM_GetAltMapRowPtr(y);
}

int EB_GetNumItems(void)
{
    return gNumItems;
}

void EB_GetItem(int index, int32_t* x, int32_t* y, int16_t* type, uint8_t parm[4])
{
    if (index < 0 || index >= gNumItems) return;
    ObjectEntryType* it = &gMasterItemList[index];
    if (x) *x = it->x;
    if (y) *y = it->y;
    if (type) *type = it->type;
    if (parm) { parm[0]=it->parm[0]; parm[1]=it->parm[1]; parm[2]=it->parm[2]; parm[3]=it->parm[3]; }
}

void EB_SetItem(int index, int32_t x, int32_t y, int16_t type, const uint8_t parm[4])
{
    if (index < 0 || index >= gNumItems) return;
    ObjectEntryType* it = &gMasterItemList[index];
    it->x = x;
    it->y = y;
    it->type = type;
    if (parm) { it->parm[0]=parm[0]; it->parm[1]=parm[1]; it->parm[2]=parm[2]; it->parm[3]=parm[3]; }
}

void EB_InitPomme(void)
{
    Pomme::Init();
}

void EB_SetDataSpecFromHostPath(const char* systemFolderHostPath)
{
    FSSpec spec = Pomme::Files::HostPathToFSSpec(std::string(systemFolderHostPath));
    gDataSpec = spec;
}

uint16_t EB_GetTileAttribBits(int tileIndex)
{
    if (!gTileAttributes) return 0;
    if (tileIndex < 0) return 0;
    return gTileAttributes[tileIndex].bits;
}

void EB_SetTileAttribBits(int tileIndex, uint16_t bits)
{
    if (!gTileAttributes) return;
    if (tileIndex < 0) return;
    gTileAttributes[tileIndex].bits = bits;
}

void EB_AdvanceAnimation(void)
{
    extern long gFrames;
    gFrames++;
    UpdateTileAnimation();
}

static inline int32_t EB_ReadBE32(const uint8_t* p)
{
    return (int32_t)((p[0]<<24)|(p[1]<<16)|(p[2]<<8)|p[3]);
}

static inline void EB_WriteBE16(uint8_t* p, uint16_t v)
{
    p[0] = (v>>8)&0xFF; p[1] = v & 0xFF;
}

static inline void EB_WriteBE32(uint8_t* p, uint32_t v)
{
    p[0]=(v>>24)&0xFF; p[1]=(v>>16)&0xFF; p[2]=(v>>8)&0xFF; p[3]=v&0xFF;
}

void EB_SaveMapToPath(const char* outPath)
{
    if (!gPlayfieldHandle) return;
    size_t decompSize = (size_t) GetHandleSize(gPlayfieldHandle);
    uint8_t* copy = (uint8_t*) malloc(decompSize);
    memcpy(copy, *(uint8_t**)gPlayfieldHandle, decompSize);

    int32_t offsetToMapImage = EB_ReadBE32(copy + 2);
    int32_t offsetToAltMap = EB_ReadBE32(copy + 10);
    int32_t offsetToObjectList = EB_ReadBE32(copy + 6);

    uint8_t* mapBase = copy + offsetToMapImage;
    uint16_t w = (uint16_t) (gPlayfieldWidth >> TILE_SIZE_SH);
    uint16_t h = (uint16_t) (gPlayfieldHeight >> TILE_SIZE_SH);
    EB_WriteBE16(mapBase + 0, w);
    EB_WriteBE16(mapBase + 2, h);
    uint8_t* tilesBE = mapBase + 4;
    for (int y=0; y<h; y++)
    {
        for (int x=0; x<w; x++)
        {
            uint16_t v = gPlayfield[y][x];
            EB_WriteBE16(tilesBE, v);
            tilesBE += 2;
        }
    }

    if (offsetToObjectList > 0 && gMasterItemList && gNumItems >= 0)
    {
        uint8_t* objBase = copy + offsetToObjectList + 2;
        for (int i=0; i<gNumItems; i++)
        {
            EB_WriteBE32(objBase+0, (uint32_t)gMasterItemList[i].x);
            EB_WriteBE32(objBase+4, (uint32_t)gMasterItemList[i].y);
            EB_WriteBE16(objBase+8, (uint16_t)gMasterItemList[i].type);
            objBase[10] = gMasterItemList[i].parm[0];
            objBase[11] = gMasterItemList[i].parm[1];
            objBase[12] = gMasterItemList[i].parm[2];
            objBase[13] = gMasterItemList[i].parm[3];
            objBase += sizeof(gMasterItemList[0]);
        }
    }

    FILE* f = fopen(outPath, "wb");
    if (!f) { free(copy); return; }
    uint32_t type = 2; // PACK_TYPE_NONE
    uint8_t hdr[8];
    EB_WriteBE32(hdr+0, (uint32_t)decompSize);
    EB_WriteBE32(hdr+4, type);
    fwrite(hdr, 1, 8, f);
    fwrite(copy, 1, decompSize, f);
    fclose(f);
    free(copy);
}
