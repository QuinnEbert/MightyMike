#import "MMMapView.h"
#import "EditorBridge.h"

typedef NS_ENUM(NSInteger, MMActionKind) {
    MMActionKindTiles = 0,
    MMActionKindAlt   = 1,
    MMActionKindItem  = 2,
};

@interface MMMapView ()
@property (strong) NSBitmapImageRep *bitmap;
@property (strong) NSMutableArray *undoStack;
@property (strong) NSMutableArray *redoStack;
@property (strong) NSMutableArray *currentChanges; // array of change dicts
@property (assign) MMActionKind currentActionKind;
@property (assign) BOOL isDragging;
@property (assign) NSInteger anchorTX, anchorTY; // for line/select tools
@property (assign) BOOL movingSelection;
@property (assign) NSPoint selectionDragStart;
@property (assign) NSRect selectionOriginalRect;
@property (strong) NSMutableData *selTiles; // 16-bit tile values buffer
@property (strong) NSMutableData *selAlt;   // 8-bit alt map buffer
@end

@implementation MMMapView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect]))
    {
        _zoom = 1.0;
        _selectedTile = 0;
        self.wantsLayer = YES;
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];
        _hasSelection = NO;
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
    int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);
    if (mapW<=0 || mapH<=0) return;

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
    if (!self.bitmap) return;

    const int tileIndex = EB_GetTile(mx,my) & TILENUM_MASK;
    const uint8_t* src = EB_GetTilePixels(tileIndex);
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
            uint32_t rgba = EB_GetPaletteRGBA32()[index];

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

    int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);

    // Draw priority overlays: border for tile mask, per-pixel tint for pixel mask
    const uint8_t* prioMask = EB_GetPriorityColorMask();
    [[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:0.5] setStroke];
    NSBezierPath* border = [NSBezierPath bezierPath];
    [border setLineWidth:1.0];
    [[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:0.25] setFill];
    for (int my = 0; my < mapH; my++)
    {
        for (int mx = 0; mx < mapW; mx++)
        {
            unsigned short t = EB_GetTile(mx,my);
            if (!(t & TILE_PRIORITY_MASK)) continue;

            // Draw border for any priority tile
            NSRect tr = NSMakeRect(mx*TILE_SIZE*self.zoom, my*TILE_SIZE*self.zoom, TILE_SIZE*self.zoom, TILE_SIZE*self.zoom);
            [border appendBezierPathWithRect:tr];

            if (t & TILE_PRIORITY_MASK2)
            {
                // Per-pixel overlay: tint solid-priority pixels
                const int tileIndex = t & TILENUM_MASK;
                const uint8_t* src = EB_GetTilePixels(tileIndex);
                if (src && prioMask)
                {
                    CGFloat px0 = mx*TILE_SIZE*self.zoom;
                    CGFloat py0 = my*TILE_SIZE*self.zoom;
                    for (int py=0; py<TILE_SIZE; py++)
                    {
                        for (int px=0; px<TILE_SIZE; px++)
                        {
                            uint8_t idx = *src++;
                            if (prioMask[idx])
                            {
                                NSRect pr = NSMakeRect(px0 + px*self.zoom, py0 + py*self.zoom, self.zoom, self.zoom);
                                NSRectFillUsingOperation(pr, NSCompositingOperationSourceOver);
                            }
                        }
                    }
                }
            }
        }
    }
    [border stroke];

    // Draw alt-map overlay arrows
    [[NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:0.6] setStroke];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.3] setFill];
    NSBezierPath* arrow = [NSBezierPath bezierPath];
    [arrow setLineWidth:2.0];
    for (int y=0; y<mapH; y++)
    {
        uint8_t* row = EB_GetAltRow(y);
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
                case ALT_TILE_DIR_UP_RIGHT:     b = NSMakePoint(cx+r*0.7, cy-r*0.7); break;
                case ALT_TILE_DIR_RIGHT:        b = NSMakePoint(cx+r, cy); break;
                case ALT_TILE_DIR_DOWN_RIGHT:   b = NSMakePoint(cx+r*0.7, cy+r*0.7); break;
                case ALT_TILE_DIR_DOWN:         b = NSMakePoint(cx, cy+r); break;
                case ALT_TILE_DIR_DOWN_LEFT:    b = NSMakePoint(cx-r*0.7, cy+r*0.7); break;
                case ALT_TILE_DIR_LEFT:         b = NSMakePoint(cx-r, cy); break;
                case ALT_TILE_DIR_LEFT_UP:      b = NSMakePoint(cx-r*0.7, cy-r*0.7); break;
                case ALT_TILE_DIR_STOP:
                {
                    NSBezierPath* x = [NSBezierPath bezierPath];
                    [x moveToPoint:NSMakePoint(cx-r*0.6, cy-r*0.6)];
                    [x lineToPoint:NSMakePoint(cx+r*0.6, cy+r*0.6)];
                    [x moveToPoint:NSMakePoint(cx+r*0.6, cy-r*0.6)];
                    [x lineToPoint:NSMakePoint(cx-r*0.6, cy+r*0.6)];
                    [x stroke];
                    continue;
                }
                case ALT_TILE_DIR_LOOP:
                {
                    NSBezierPath* c = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx-r*0.6, cy-r*0.6, r*1.2, r*1.2)];
                    [c stroke];
                    continue;
                }
                default: break;
            }
            [arrow removeAllPoints];
            [arrow moveToPoint:a];
            [arrow lineToPoint:b];
            [arrow stroke];
        }
    }

    // Draw selection rectangle
    if (self.hasSelection)
    {
        [[NSColor colorWithCalibratedRed:0 green:0.6 blue:1 alpha:0.7] setStroke];
        NSRect sr = NSMakeRect(self.selectionRect.origin.x*TILE_SIZE*self.zoom,
                               self.selectionRect.origin.y*TILE_SIZE*self.zoom,
                               self.selectionRect.size.width*TILE_SIZE*self.zoom,
                               self.selectionRect.size.height*TILE_SIZE*self.zoom);
        NSBezierPath* sp = [NSBezierPath bezierPathWithRect:sr];
        sp.lineWidth = 2.0;
        [sp stroke];
    }

    [gc restoreGraphicsState];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.bitmap) return;

    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    p.x /= self.zoom; p.y /= self.zoom;
    int tx = (int)(p.x) / TILE_SIZE;
    int ty = (int)(p.y) / TILE_SIZE;

    int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);
    if (tx < 0 || ty < 0 || tx >= mapW || ty >= mapH) return;

    self.isDragging = YES;
    self.anchorTX = tx; self.anchorTY = ty;

    if (self.toolMode == 1)
    {
        // Selection tool
        self.hasSelection = YES;
        self.movingSelection = NSPointInRect(NSMakePoint(tx, ty), self.selectionRect);
        self.selectionDragStart = NSMakePoint(tx, ty);
        if (!self.movingSelection)
        {
            self.selectionRect = NSMakeRect(tx, ty, 1, 1);
        }
        else
        {
            self.selectionOriginalRect = self.selectionRect;
            // Capture selection buffers
            int w = (int)self.selectionRect.size.width;
            int h = (int)self.selectionRect.size.height;
            self.selTiles = [NSMutableData dataWithLength:w*h*sizeof(uint16_t)];
            self.selAlt = [NSMutableData dataWithLength:w*h];
            uint16_t* tb = (uint16_t*)self.selTiles.mutableBytes;
            uint8_t* ab = (uint8_t*)self.selAlt.mutableBytes;
            for (int yy=0; yy<h; yy++)
            {
                int sy = (int)self.selectionRect.origin.y + yy;
                uint8_t* arow = EB_GetAltRow(sy);
                for (int xx=0; xx<w; xx++)
                {
                    int sx = (int)self.selectionRect.origin.x + xx;
                    tb[yy*w+xx] = EB_GetTile(sx,sy);
                    ab[yy*w+xx] = arow ? arow[sx] : 0;
                }
            }
        }
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.toolMode == 2)
    {
        // Fill tool: flood fill
        unsigned short cur = EB_GetTile(tx,ty);
        unsigned short flags = cur & ~TILENUM_MASK;
        unsigned short target = cur & TILENUM_MASK;
        unsigned short replacement = (unsigned short)self.selectedTile;
        if (target == replacement) return;

        self.currentActionKind = MMActionKindTiles;
        self.currentChanges = [NSMutableArray array];

        int W=0,H=0; EB_GetMapSize(&W,&H);
        NSMutableArray* stack = [NSMutableArray arrayWithObject:[NSValue valueWithPoint:NSMakePoint(tx, ty)]];
        NSMutableData* visited = [NSMutableData dataWithLength:W*H];
        uint8_t* vis = visited.mutableBytes;
        while (stack.count)
        {
            NSPoint p0 = [stack.lastObject pointValue];
            [stack removeLastObject];
            int x = (int)p0.x, y=(int)p0.y;
            if (x<0||y<0||x>=W||y>=H) continue;
            int idx = y*W+x;
            if (vis[idx]) continue; vis[idx]=1;
            unsigned short val = EB_GetTile(x,y);
            if ((val & TILENUM_MASK) != target) continue;
            // record undo before change
            [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(x), @"y": @(y), @"old": @(val), @"new": @((val & ~TILENUM_MASK) | replacement) }];
            EB_SetTile(x,y, (val & ~TILENUM_MASK) | replacement);
            [stack addObject:[NSValue valueWithPoint:NSMakePoint(x+1,y)]];
            [stack addObject:[NSValue valueWithPoint:NSMakePoint(x-1,y)]];
            [stack addObject:[NSValue valueWithPoint:NSMakePoint(x,y+1)]];
            [stack addObject:[NSValue valueWithPoint:NSMakePoint(x,y-1)]];
        }
        [self.undoStack addObject:@{ @"kind": @(MMActionKindTiles), @"changes": self.currentChanges }];
        [self.redoStack removeAllObjects];
        [self reloadBitmap];
        return;
    }

    if (self.toolMode == 3)
    {
        // Line tool: do nothing here; draw on mouseUp
        return;
    }

    if (self.toolMode == 5)
    {
        // Alt-map edit
        uint8_t* row = EB_GetAltRow(ty);
        if (row)
        {
            uint8_t v = 0;
            switch (self.altMode)
            {
                case 1: v = ALT_TILE_DIR_UP; break;
                case 2: v = ALT_TILE_DIR_RIGHT; break;
                case 3: v = ALT_TILE_DIR_DOWN; break;
                case 4: v = ALT_TILE_DIR_LEFT; break;
                case 5: v = ALT_TILE_DIR_UP_RIGHT; break;
                case 6: v = ALT_TILE_DIR_DOWN_RIGHT; break;
                case 7: v = ALT_TILE_DIR_DOWN_LEFT; break;
                case 8: v = ALT_TILE_DIR_LEFT_UP; break;
                case 9: v = ALT_TILE_DIR_STOP; break;
                case 10: v = ALT_TILE_DIR_LOOP; break;
                default: v = ALT_TILE_NONE; break;
            }
            self.currentActionKind = MMActionKindAlt;
            self.currentChanges = [NSMutableArray arrayWithObject:@{ @"kind": @"alt", @"x": @(tx), @"y": @(ty), @"old": @(row[tx]), @"new": @(v) }];
            row[tx] = v;
            [self setNeedsDisplay:YES];
            return;
        }
    }
    else if (self.toolMode == 4)
    {
        // Item tool: place item with params from AppDelegate
        // Find a free slot (ITEM_MEMORY set) or reuse first slot
        int n = EB_GetNumItems();
        int found = -1;
        // See if click on existing item to remove (alt/option click)
        if ((event.modifierFlags & NSEventModifierFlagOption) && n>0)
        {
            for (int i=0;i<n;i++)
            {
                int32_t ix,iy; int16_t it; uint8_t pr[4];
                EB_GetItem(i,&ix,&iy,&it,pr);
                if (((ix >> TILE_SIZE_SH) == tx) && ((iy >> TILE_SIZE_SH) == ty))
                {
                    // record undo
                    typedef struct { int32_t x; int32_t y; int16_t type; uint8_t parm[4]; } EBItemRec;
                    EBItemRec oldEntry = { ix,iy,it,{pr[0],pr[1],pr[2],pr[3]} };
                    EBItemRec newEntry = oldEntry; newEntry.type = (newEntry.type & ITEM_NUM) | ITEM_MEMORY;
                    NSData* oldData = [NSData dataWithBytes:&oldEntry length:sizeof(EBItemRec)];
                    NSData* newData = [NSData dataWithBytes:&newEntry length:sizeof(EBItemRec)];
                    self.currentActionKind = MMActionKindItem;
                    self.currentChanges = [NSMutableArray arrayWithObject:@{ @"kind": @"item", @"index": @(i), @"old": oldData, @"new": newData }];
                    EB_SetItem(i, newEntry.x, newEntry.y, newEntry.type, newEntry.parm);
                    [self.undoStack addObject:@{ @"kind": @(MMActionKindItem), @"changes": self.currentChanges }];
                    [self.redoStack removeAllObjects];
                    [self setNeedsDisplay:YES];
                    return;
                }
            }
        }
        for (int i=0;i<n;i++)
        {
            int32_t ix,iy; int16_t it; uint8_t pr[4];
            EB_GetItem(i,&ix,&iy,&it,pr);
            if (it & ITEM_MEMORY) { found = i; break; }
        }
        if (found < 0 && n>0) { found = 0; } // fallback
        if (found >= 0)
        {
            // Pull type/parms from app delegate
            id app = NSApp.delegate;
            int itype = [[app valueForKey:@"itemTypeField"] integerValue];
            // record undo
            int32_t nx = tx << TILE_SIZE_SH, ny = ty << TILE_SIZE_SH; int16_t nt = itype & ITEM_NUM;
            id f0 = [app valueForKey:@"itemParm0"]; id f1 = [app valueForKey:@"itemParm1"]; id f2 = [app valueForKey:@"itemParm2"]; id f3 = [app valueForKey:@"itemParm3"];
            uint8_t npr[4] = { (uint8_t)[f0 integerValue], (uint8_t)[f1 integerValue], (uint8_t)[f2 integerValue], (uint8_t)[f3 integerValue] };
            typedef struct { int32_t x; int32_t y; int16_t type; uint8_t parm[4]; } EBItemRec;
            int32_t ox,oy; int16_t ot; uint8_t opr[4]; EB_GetItem(found,&ox,&oy,&ot,opr);
            EBItemRec oldRec = { ox,oy,ot,{opr[0],opr[1],opr[2],opr[3]} };
            EBItemRec newRec = { nx,ny,nt,{npr[0],npr[1],npr[2],npr[3]} };
            EB_SetItem(found, nx, ny, nt, npr);
            NSData* oldData = [NSData dataWithBytes:&oldRec length:sizeof(EBItemRec)];
            NSData* newData = [NSData dataWithBytes:&newRec length:sizeof(EBItemRec)];
            self.currentActionKind = MMActionKindItem;
            self.currentChanges = [NSMutableArray arrayWithObject:@{ @"kind": @"item", @"index": @(found), @"old": oldData, @"new": newData }];
            [self.undoStack addObject:@{ @"kind": @(MMActionKindItem), @"changes": self.currentChanges }];
            [self.redoStack removeAllObjects];
        }
        [self setNeedsDisplay:YES];
        return;
    }
    else
    {
        // Tile paint, begin action
        self.currentActionKind = MMActionKindTiles;
        self.currentChanges = [NSMutableArray array];
        unsigned short cur = EB_GetTile(tx,ty);
        unsigned short newv = (cur & ~TILENUM_MASK) | (unsigned short)self.selectedTile;
        if (cur != newv)
        {
            [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(tx), @"y": @(ty), @"old": @(cur), @"new": @(newv) }];
            EB_SetTile(tx,ty,newv);
            [self updateTileAtX:tx y:ty];
        }
        return;
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!self.isDragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    p.x /= self.zoom; p.y /= self.zoom;
    int tx = (int)(p.x) / TILE_SIZE;
    int ty = (int)(p.y) / TILE_SIZE;
    int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);
    if (tx < 0 || ty < 0 || tx >= mapW || ty >= mapH) return;

    if (self.toolMode == 1)
    {
        if (self.movingSelection)
        {
            // just show selection rect moved visually during drag
            NSPoint d = NSMakePoint(tx - self.selectionDragStart.x, ty - self.selectionDragStart.y);
            NSRect sr = self.selectionRect;
            self.selectionRect = NSMakeRect(sr.origin.x + d.x, sr.origin.y + d.y, sr.size.width, sr.size.height);
            self.selectionDragStart = NSMakePoint(tx, ty);
        }
        else
        {
            int x0 = (int)self.anchorTX, y0 = (int)self.anchorTY;
            int x1 = tx, y1 = ty;
            int x = MIN(x0,x1), y = MIN(y0,y1);
            int w = abs(x1-x0)+1, h = abs(y1-y0)+1;
            self.selectionRect = NSMakeRect(x, y, w, h);
        }
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.toolMode == 5)
    {
        uint8_t* row = EB_GetAltRow(ty);
        if (!row) return;
        Byte v = 0;
        switch (self.altMode)
        {
            case 1: v = ALT_TILE_DIR_UP; break;
            case 2: v = ALT_TILE_DIR_RIGHT; break;
            case 3: v = ALT_TILE_DIR_DOWN; break;
            case 4: v = ALT_TILE_DIR_LEFT; break;
            case 5: v = ALT_TILE_DIR_UP_RIGHT; break;
            case 6: v = ALT_TILE_DIR_DOWN_RIGHT; break;
            case 7: v = ALT_TILE_DIR_DOWN_LEFT; break;
            case 8: v = ALT_TILE_DIR_LEFT_UP; break;
            case 9: v = ALT_TILE_DIR_STOP; break;
            case 10: v = ALT_TILE_DIR_LOOP; break;
            default: v = ALT_TILE_NONE; break;
        }
        if (self.currentChanges == nil)
        {
            self.currentActionKind = MMActionKindAlt;
            self.currentChanges = [NSMutableArray array];
        }
        // Avoid duplicate change entries for same coord
        row[tx] = v;
        [self.currentChanges addObject:@{ @"kind": @"alt", @"x": @(tx), @"y": @(ty), @"old": @(row[tx]), @"new": @(v) }];
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.toolMode == 0)
    {
        unsigned short cur = EB_GetTile(tx,ty);
        unsigned short newv = (cur & ~TILENUM_MASK) | (unsigned short)self.selectedTile;
        if (cur != newv)
        {
            if (!self.currentChanges)
            {
                self.currentActionKind = MMActionKindTiles;
                self.currentChanges = [NSMutableArray array];
            }
            [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(tx), @"y": @(ty), @"old": @(cur), @"new": @(newv) }];
            EB_SetTile(tx,ty,newv);
            [self updateTileAtX:tx y:ty];
        }
        return;
    }
}

- (void)mouseUp:(NSEvent *)event
{
    if (!self.isDragging) return;
    self.isDragging = NO;

    if (self.toolMode == 1)
    {
        if (self.movingSelection)
        {
            // Apply move: paste selTiles at new position, clear original
            NSRect src = self.selectionOriginalRect;
            NSRect dst = self.selectionRect;
            int sw = (int)src.size.width, sh=(int)src.size.height;
            if (sw>0 && sh>0)
            {
                self.currentActionKind = MMActionKindTiles;
                self.currentChanges = [NSMutableArray array];
                uint16_t* tb = (uint16_t*)self.selTiles.bytes;
                uint8_t* ab = (uint8_t*)self.selAlt.bytes;

                // Clear source
                for (int yy=0; yy<sh; yy++)
                {
                    int sy = (int)src.origin.y + yy;
                    uint8_t* arow = EB_GetAltRow(sy);
                    for (int xx=0; xx<sw; xx++)
                    {
                        int sx = (int)src.origin.x + xx;
                        unsigned short oldv = EB_GetTile(sx,sy);
                        unsigned short newv = 0;
                        if (oldv != newv)
                        {
                            [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(sx), @"y": @(sy), @"old": @(oldv), @"new": @(newv) }];
                            EB_SetTile(sx,sy,newv);
                        }
                        if (arow)
                        {
                            Byte olda = arow[sx];
                            if (olda != 0)
                            {
                                [self.currentChanges addObject:@{ @"kind": @"alt", @"x": @(sx), @"y": @(sy), @"old": @(olda), @"new": @0 }];
                                arow[sx] = 0;
                            }
                        }
                    }
                }

                // Paste into destination
                for (int yy=0; yy<sh; yy++)
                {
                    int dy = (int)dst.origin.y + yy;
                    int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);
                    if (dy<0 || dy>=mapH) continue;
                    uint8_t* arow = EB_GetAltRow(dy);
                    for (int xx=0; xx<sw; xx++)
                    {
                        int dx = (int)dst.origin.x + xx;
                        if (dx<0 || dx>=mapW) continue;
                        unsigned short oldv = EB_GetTile(dx,dy);
                        unsigned short newv = tb[yy*sw+xx];
                        if (oldv != newv)
                        {
                            [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(dx), @"y": @(dy), @"old": @(oldv), @"new": @(newv) }];
                            EB_SetTile(dx,dy,newv);
                        }
                        if (arow)
                        {
                            Byte olda = arow[dx];
                            Byte newa = ab[yy*sw+xx];
                            if (olda != newa)
                            {
                                [self.currentChanges addObject:@{ @"kind": @"alt", @"x": @(dx), @"y": @(dy), @"old": @(olda), @"new": @(newa) }];
                                arow[dx] = newa;
                            }
                        }
                    }
                }

                if (self.currentChanges.count)
                {
                    [self.undoStack addObject:@{ @"kind": @(MMActionKindTiles), @"changes": self.currentChanges }];
                    [self.redoStack removeAllObjects];
                }

                [self reloadBitmap];
            }
        }
        return;
    }

    if (self.toolMode == 3)
    {
        // Draw line from anchor to current tile
        NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
        p.x /= self.zoom; p.y /= self.zoom;
        int x0 = (int)self.anchorTX, y0=(int)self.anchorTY;
        int x1 = (int)p.x / TILE_SIZE, y1 = (int)p.y / TILE_SIZE;
        int dx = abs(x1-x0), sx = x0 < x1 ? 1 : -1;
        int dy = -abs(y1-y0), sy = y0 < y1 ? 1 : -1;
        int err = dx + dy;
        self.currentActionKind = MMActionKindTiles;
        self.currentChanges = [NSMutableArray array];
        int x=x0, y=y0;
        while (true)
        {
            int mapW=0,mapH=0; EB_GetMapSize(&mapW,&mapH);
            if (x>=0 && y>=0 && x<mapW && y<mapH)
            {
                unsigned short cur = EB_GetTile(x,y);
                unsigned short newv = (cur & ~TILENUM_MASK) | (unsigned short)self.selectedTile;
                if (cur != newv)
                {
                    [self.currentChanges addObject:@{ @"kind": @"tile", @"x": @(x), @"y": @(y), @"old": @(cur), @"new": @(newv) }];
                    EB_SetTile(x,y,newv);
                }
            }
            if (x==x1 && y==y1) break;
            int e2 = 2*err;
            if (e2 >= dy) { err += dy; x += sx; }
            if (e2 <= dx) { err += dx; y += sy; }
        }
        if (self.currentChanges.count > 0)
        {
            [self.undoStack addObject:@{ @"kind": @(MMActionKindTiles), @"changes": self.currentChanges }];
            [self.redoStack removeAllObjects];
            [self reloadBitmap];
        }
        return;
    }

    if (self.currentChanges && self.currentChanges.count)
    {
        [self.undoStack addObject:@{ @"kind": @(self.currentActionKind), @"changes": self.currentChanges }];
        [self.redoStack removeAllObjects];
        self.currentChanges = nil;
    }
}

- (void)undo
{
    NSDictionary* act = [self.undoStack lastObject];
    if (!act) return;
    [self.undoStack removeLastObject];
    MMActionKind kind = [act[@"kind"] integerValue];
    NSArray* changes = act[@"changes"];
    // Apply in reverse using 'old'
    for (NSDictionary* c in [changes reverseObjectEnumerator])
    {
        NSString* k = c[@"kind"];
        if ([k isEqualToString:@"tile"])
        {
            int x=[c[@"x"] intValue], y=[c[@"y"] intValue];
            EB_SetTile(x,y,[c[@"old"] intValue]);
        }
        else if ([k isEqualToString:@"alt"]) {
            int x=[c[@"x"] intValue], y=[c[@"y"] intValue];
            uint8_t* row = EB_GetAltRow(y);
            if (row) row[x] = [c[@"old"] intValue];
        }
        else if ([k isEqualToString:@"item"]) {
            int i=[c[@"index"] intValue];
            typedef struct { int32_t x; int32_t y; int16_t type; uint8_t parm[4]; } EBItemRec;
            EBItemRec v; [[c objectForKey:@"old"] getBytes:&v length:sizeof(v)];
            EB_SetItem(i, v.x, v.y, v.type, v.parm);
        }
    }
    [self.redoStack addObject:act];
    [self reloadBitmap];
}

- (void)redo
{
    NSDictionary* act = [self.redoStack lastObject];
    if (!act) return;
    [self.redoStack removeLastObject];
    MMActionKind kind = [act[@"kind"] integerValue];
    NSArray* changes = act[@"changes"];
    for (NSDictionary* c in changes)
    {
        NSString* k = c[@"kind"];
        if ([k isEqualToString:@"tile"])
        {
            int x=[c[@"x"] intValue], y=[c[@"y"] intValue];
            EB_SetTile(x,y,[c[@"new"] intValue]);
        }
        else if ([k isEqualToString:@"alt"]) {
            int x=[c[@"x"] intValue], y=[c[@"y"] intValue];
            uint8_t* row = EB_GetAltRow(y);
            if (row) row[x] = [c[@"new"] intValue];
        }
        else if ([k isEqualToString:@"item"]) {
            int i=[c[@"index"] intValue];
            typedef struct { int32_t x; int32_t y; int16_t type; uint8_t parm[4]; } EBItemRec;
            EBItemRec v; [[c objectForKey:@"new"] getBytes:&v length:sizeof(v)];
            EB_SetItem(i, v.x, v.y, v.type, v.parm);
        }
    }
    [self.undoStack addObject:act];
    [self reloadBitmap];
}

- (void)clearUndoStack
{
    [self.undoStack removeAllObjects];
    [self.redoStack removeAllObjects];
}

@end
