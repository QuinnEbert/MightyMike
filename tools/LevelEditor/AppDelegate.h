#import <Cocoa/Cocoa.h>

@class MMMapView, MMTilePaletteView;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) NSWindow *window;
@property (strong) NSScrollView *scrollView;
@property (strong) MMMapView *mapView;
@property (strong) NSScrollView *paletteScroll;
@property (strong) MMTilePaletteView *paletteView;
@property (strong) NSTextField *tileField;
@property (strong) NSSegmentedControl *toolSeg;
@property (strong) NSPopUpButton *altPopup;
@property (strong) NSTimer *animTimer;
@property (strong) NSTextField *itemTypeField;
@property (strong) NSTextField *itemParm0;
@property (strong) NSTextField *itemParm1;
@property (strong) NSTextField *itemParm2;
@property (strong) NSTextField *itemParm3;

@end
