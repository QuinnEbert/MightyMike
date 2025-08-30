#import <Cocoa/Cocoa.h>

@class MMMapView;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) NSWindow *window;
@property (strong) NSScrollView *scrollView;
@property (strong) MMMapView *mapView;
@property (strong) NSTextField *tileField;

@end

