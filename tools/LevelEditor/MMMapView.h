#import <Cocoa/Cocoa.h>

@interface MMMapView : NSView

@property (assign) NSInteger selectedTile; // tile index to paint
@property (assign) CGFloat zoom;           // zoom factor

- (void)reloadBitmap;                      // rebuild bitmap from current playfield
- (void)updateTileAtX:(NSInteger)x y:(NSInteger)y; // redraw single tile

@end

