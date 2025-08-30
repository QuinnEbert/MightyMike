#import <Cocoa/Cocoa.h>

@interface MMMapView : NSView

@property (assign) NSInteger selectedTile; // tile index to paint
@property (assign) CGFloat zoom;           // zoom factor
@property (assign) NSInteger toolMode;     // 0=tile,1=select,2=fill,3=line,4=item,5=alt,6=attr
@property (assign) NSInteger altMode;      // 0=None,1=Up,2=Right,3=Down,4=Left

// Selection/drag
@property (assign) NSRect selectionRect;   // in tile coords (x,y,w,h)
@property (assign) BOOL hasSelection;

// Undo/redo support
- (void)undo;
- (void)redo;
- (void)clearUndoStack;

- (void)reloadBitmap;                      // rebuild bitmap from current playfield
- (void)updateTileAtX:(NSInteger)x y:(NSInteger)y; // redraw single tile

@end
