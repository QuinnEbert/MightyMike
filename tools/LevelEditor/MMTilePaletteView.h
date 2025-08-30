#import <Cocoa/Cocoa.h>

@class MMTilePaletteView;

@protocol MMTilePaletteDelegate <NSObject>
- (void)tilePalette:(MMTilePaletteView*)palette didSelectTile:(NSInteger)tileIndex;
@end

@interface MMTilePaletteView : NSView
@property (weak) id<MMTilePaletteDelegate> delegate;
@property (assign) NSInteger columns;   // tiles per row
@property (assign) CGFloat zoom;        // tile preview zoom
@property (assign) NSInteger selectedTile; // highlight selection
- (void)updateSize;
@end
