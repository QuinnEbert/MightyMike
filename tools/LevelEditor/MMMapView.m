#import "MMMapView.h"
#import "myglobals.h"
#import "playfield.h"
#import "externs.h"
#import "structures.h"

@interface MMMapView ()
@property (strong) NSBitmapImageRep *bitmap;
@end

@implementation MMMapView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect]))
    {
        _zoom = 1.0;
        _selectedTile = 0;
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setZoom:(CGFloat)zoom
{
    _zoom = MAX(0.25, MIN(8.0, zoom));
    [self setNeedsDisplay:YES];
}

- (void)reloadBitmap
{
    if (gPlayfield == nil)
        return;

    const NSInteger mapW = gPlayfieldTileWidth;
    const NSInteger mapH = gPlayfieldTileHeight;
    const NSInteger tile = TILE_SIZE;

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:mapW*tile
        pixelsHigh:mapH*tile
        bitsPerSample:8
        samplesPerPixel:4
        hasAlpha:YES
        isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:mapW*tile*4
        bitsPerPixel:32];

    self.bitmap = rep;

    for (NSInteger y = 0; y < mapH; y++)
    {
        for (NSInteger x = 0; x < mapW; x++)
        {
            [self p_drawTileAtX:(int)x y:(int)y];
        }
    }

    [self setFrameSize:NSMakeSize(mapW*tile*_zoom, mapH*tile*_zoom)];
    [self setNeedsDisplay:YES];
}

- (void)updateTileAtX:(NSInteger)x y:(NSInteger)y
{
    if (!self.bitmap) return;
    [self p_drawTileAtX:(int)x y:(int)y];
    [self setNeedsDisplay:YES];
}

- (void)p_drawTileAtX:(int)mx y:(int)my
{
    if (!self.bitmap || !gPlayfield) return;

    const int tileIndex = gPlayfield[my][mx] & TILENUM_MASK;
    const uint8_t* src = MM_GetTilePixelsForTile(tileIndex);
    if (!src) return;

    uint8_t* dst = [self.bitmap bitmapData];
    const NSInteger bpr = [self.bitmap bytesPerRow];

    const int px0 = mx * TILE_SIZE;
    const int py0 = my * TILE_SIZE;

    for (int ty = 0; ty < TILE_SIZE; ty++)
    {
        uint8_t* row = dst + (py0 + ty) * bpr + px0 * 4;
        for (int tx = 0; tx < TILE_SIZE; tx++)
        {
            uint8_t index = *src++;
            uint32_t rgba = gGamePalette.finalColors32[index];

            row[0] = (rgba >> 24) & 0xFF; // R
            row[1] = (rgba >> 16) & 0xFF; // G
            row[2] = (rgba >>  8) & 0xFF; // B
            row[3] = (rgba >>  0) & 0xFF; // A
            row += 4;
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    if (!self.bitmap) return;

    NSGraphicsContext* gc = [NSGraphicsContext currentContext];
    [gc saveGraphicsState];

    NSAffineTransform* xform = [NSAffineTransform transform];
    [xform scaleBy:self.zoom];
    [xform concat];

    NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(self.bitmap.pixelsWide, self.bitmap.pixelsHigh)];
    [img addRepresentation:self.bitmap];
    [img drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];

    // Draw priority mask overlay
    [[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:0.5] setStroke];
    NSBezierPath* border = [NSBezierPath bezierPath];
    [border setLineWidth:1.0];
    for (int y=0; y<mapH; y++) for (int x=0; x<mapW; x++)
    {
        unsigned short t = gPlayfield[y][x];
        if (t & TILE_PRIORITY_MASK)
        {
            NSRect r = NSMakeRect(x*TILE_SIZE*self.zoom, y*TILE_SIZE*self.zoom, TILE_SIZE*self.zoom, TILE_SIZE*self.zoom);
            [border appendBezierPathWithRect:r];
        }
    }
    [border stroke];

    // Draw alt-map overlay arrows
    int mapW = gPlayfieldTileWidth;
    int mapH = gPlayfieldTileHeight;
    [[NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:0.6] setStroke];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.3] setFill];
    NSBezierPath* arrow = [NSBezierPath bezierPath];
    [arrow setLineWidth:2.0];
    for (int y=0; y<mapH; y++)
    {
        Byte* row = MM_GetAltMapRowPtr(y);
        if (!row) break;
        for (int x=0; x<mapW; x++)
        {
            Byte v = row[x]; if (!v) continue;
            CGFloat cx = (x+0.5)*TILE_SIZE * self.zoom;
            CGFloat cy = (y+0.5)*TILE_SIZE * self.zoom;
            CGFloat r = 12 * self.zoom;
            NSPoint a = NSMakePoint(cx, cy), b=a;
            switch (v)
            {
                case ALT_TILE_DIR_UP:           b = NSMakePoint(cx, cy-r); break;
                case ALT_TILE_DIR_RIGHT:        b = NSMakePoint(cx+r, cy); break;
                case ALT_TILE_DIR_DOWN:         b = NSMakePoint(cx, cy+r); break;
                case ALT_TILE_DIR_LEFT:         b = NSMakePoint(cx-r, cy); break;
                default: break;
            }
            [arrow removeAllPoints];
            [arrow moveToPoint:a];
            [arrow lineToPoint:b];
            [arrow stroke];
        }
    }

    [gc restoreGraphicsState];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.bitmap || !gPlayfield) return;

    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    p.x /= self.zoom; p.y /= self.zoom;
    int tx = (int)(p.x) / TILE_SIZE;
    int ty = (int)(p.y) / TILE_SIZE;

    if (tx < 0 || ty < 0 || tx >= gPlayfieldTileWidth || ty >= gPlayfieldTileHeight) return;

    if (self.toolMode == 5)
    {
        // Alt-map edit
        Byte* row = MM_GetAltMapRowPtr(ty);
        if (row)
        {
            Byte v = 0;
            switch (self.altMode)
            {
                case 1: v = ALT_TILE_DIR_UP; break;
                case 2: v = ALT_TILE_DIR_RIGHT; break;
                case 3: v = ALT_TILE_DIR_DOWN; break;
                case 4: v = ALT_TILE_DIR_LEFT; break;
                default: v = ALT_TILE_NONE; break;
            }
            row[tx] = v;
            [self setNeedsDisplay:YES];
        }
    }
    else if (self.toolMode == 4)
    {
        // Item tool: place item with params from AppDelegate
        // Find a free slot (ITEM_MEMORY set) or reuse first slot
        ObjectEntryType* items = gMasterItemList;
        int n = gNumItems;
        int found = -1;
        for (int i=0;i<n;i++)
        {
            if (items[i].type & ITEM_MEMORY) { found = i; break; }
        }
        if (found < 0 && n>0) { found = 0; } // fallback
        if (found >= 0)
        {
            // Pull type/parms from app delegate
            AppDelegate* app = (AppDelegate*)NSApp.delegate;
            int itype = app.itemTypeField.integerValue;
            items[found].x = tx << TILE_SIZE_SH;
            items[found].y = ty << TILE_SIZE_SH;
            items[found].type = itype & ITEM_NUM; // clear memory bits
            items[found].parm[0] = app.itemParm0.integerValue;
            items[found].parm[1] = app.itemParm1.integerValue;
            items[found].parm[2] = app.itemParm2.integerValue;
            items[found].parm[3] = app.itemParm3.integerValue;
        }
        [self setNeedsDisplay:YES];
    }
    else
    {
        // Tile paint
        unsigned short cur = gPlayfield[ty][tx];
        unsigned short flags = cur & ~TILENUM_MASK;
        gPlayfield[ty][tx] = flags | (unsigned short)self.selectedTile;
        [self updateTileAtX:tx y:ty];
    }
}

@end
