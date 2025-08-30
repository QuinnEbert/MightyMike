#import "MMTilePaletteView.h"
#import "playfield.h"
#import "externs.h"

@implementation MMTilePaletteView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect]))
    {
        _columns = 8;
        _zoom = 1.0;
        self.wantsLayer = YES;
        [self updateSize];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setColumns:(NSInteger)columns
{ _columns = MAX(1, columns); [self updateSize]; }

- (void)setZoom:(CGFloat)zoom
{ _zoom = MAX(0.5, MIN(4.0, zoom)); [self updateSize]; }

- (void)updateSize
{
    int n = MM_GetNumTiles();
    if (n <= 0) n = 1;
    int rows = (n + (int)self.columns - 1) / (int)self.columns;
    [self setFrameSize:NSMakeSize(self.columns * TILE_SIZE * self.zoom,
                                  rows * TILE_SIZE * self.zoom)];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    int n = MM_GetNumTiles(); if (n<=0) return;
    NSGraphicsContext* gc = [NSGraphicsContext currentContext];
    [gc saveGraphicsState];

    for (int i=0; i<n; i++)
    {
        int r = i / (int)self.columns;
        int c = i % (int)self.columns;
        CGFloat x = c * TILE_SIZE * self.zoom;
        CGFloat y = r * TILE_SIZE * self.zoom;

        const uint8_t* src = MM_GetTilePixelsForTile(i);
        if (!src) continue;

        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
            pixelsWide:TILE_SIZE
            pixelsHigh:TILE_SIZE
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:TILE_SIZE*4
            bitsPerPixel:32];
        uint8_t* dst = rep.bitmapData;
        for (int py=0; py<TILE_SIZE; py++)
        {
            uint8_t* row = dst + py*TILE_SIZE*4;
            for (int px=0; px<TILE_SIZE; px++)
            {
                uint8_t idx = *src++;
                uint32_t rgba = gGamePalette.finalColors32[idx];
                row[0]=(rgba>>24)&0xFF; row[1]=(rgba>>16)&0xFF; row[2]=(rgba>>8)&0xFF; row[3]=rgba&0xFF; row+=4;
            }
        }
        NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(TILE_SIZE, TILE_SIZE)];
        [img addRepresentation:rep];
        [img drawInRect:NSMakeRect(x, y, TILE_SIZE*self.zoom, TILE_SIZE*self.zoom)
                fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    }

    [gc restoreGraphicsState];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    int c = p.x / (TILE_SIZE * self.zoom);
    int r = p.y / (TILE_SIZE * self.zoom);
    int idx = r * (int)self.columns + c;
    if (idx >= 0 && idx < MM_GetNumTiles())
    {
        if ([self.delegate respondsToSelector:@selector(tilePalette:didSelectTile:)])
            [self.delegate tilePalette:self didSelectTile:idx];
    }
}

@end

