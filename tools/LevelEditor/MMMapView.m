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
    extern short *gTileXlatePtr; // from Playfield.c
    extern Ptr gTilesPtr;        // from Playfield.c

    if (!gTileXlatePtr || !gTilesPtr)
        return;

    int xlate = gTileXlatePtr[tileIndex];
    const uint8_t* src = (const uint8_t*)(gTilesPtr + (xlate << (TILE_SIZE_SH*2)));

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

    unsigned short cur = gPlayfield[ty][tx];
    unsigned short flags = cur & ~TILENUM_MASK;
    gPlayfield[ty][tx] = flags | (unsigned short)self.selectedTile;
    [self updateTileAtX:tx y:ty];
}

@end

