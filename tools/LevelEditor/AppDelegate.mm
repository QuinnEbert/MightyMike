#import "AppDelegate.h"
#import "MMMapView.h"

#import <Cocoa/Cocoa.h>

// Forward-declare minimal engine APIs to avoid pulling Pomme types into this ObjC++ file
extern "C" {
    void LoadTileSet(const char* filename);
    void DisposeCurrentMapData(void);
    void LoadPlayfield(const char* filename);
    void UpdateTileAnimation(void);
    void BuildItemList(void);
    void* LoadTGA(const char* path, bool loadPalette, int* outWidth, int* outHeight);
    extern void* gPlayfieldHandle;
}

#import "EditorBridge.h"
#import "MMTilePaletteView.h"
#import <objc/runtime.h>

@interface AppDelegate ()
@property (strong) NSURL *currentMapURL;
@property (assign) int32_t offsetToMapImage;
@property (assign) int32_t offsetToAltMap;
@property (assign) int32_t offsetToObjectList;
@end

@implementation AppDelegate

static char kAttrBoxesKeyStorage;

// Tile attribute bit constants (mirror of playfield.h)
#ifndef TILE_ATTRIB_TOPSOLID
#define TILE_ATTRIB_TOPSOLID        1
#define TILE_ATTRIB_BOTTOMSOLID     (1<<1)
#define TILE_ATTRIB_LEFTSOLID       (1<<2)
#define TILE_ATTRIB_RIGHTSOLID      (1<<3)
#define TILE_ATTRIB_DEATH           (1<<4)
#define TILE_ATTRIB_HURT            (1<<5)
#define TILE_ATTRIB_WATER           (1<<7)
#define TILE_ATTRIB_WIND            (1<<8)
#define TILE_ATTRIB_BULLETGOESTHRU  (1<<9)
#define TILE_ATTRIB_STAIRS          (1<<10)
#define TILE_ATTRIB_FRICTION        (1<<11)
#define TILE_ATTRIB_ICE             (1<<12)
#define TILE_ATTRIB_TRACK           (1<<15)
#endif

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self setupPommeAndDataSpec];
    [self setupUI];

    // Load a default palette so tiles have colors
    LoadTGA(":Images:overheadmap.tga", true, NULL, NULL);

    // Simple animation timer for tile anim preview
    self.animTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer* t){
        EB_AdvanceAnimation();
        [self.paletteView setNeedsDisplay:YES];
        [self.mapView reloadBitmap];
    }];
}

- (void)setupPommeAndDataSpec
{
    EB_InitPomme();

    // Try to locate Data folder relative to this app bundle
    NSString* exePath = [[NSBundle mainBundle] executablePath];
    NSURL* exeURL = [NSURL fileURLWithPath:exePath];

    // Search upwards for a Data folder
    NSURL* dataURL = nil;
    NSURL* url = [exeURL URLByDeletingLastPathComponent];
    for (int i=0; i<5 && url; i++)
    {
        NSURL* candidate = [url URLByAppendingPathComponent:@"../Resources/Data"].standardizedURL;
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) { dataURL = candidate; break; }
        candidate = [url URLByAppendingPathComponent:@"Data"].standardizedURL;
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) { dataURL = candidate; break; }
        url = [url URLByDeletingLastPathComponent];
    }

    if (!dataURL)
    {
        // Fallback: assume repo root Data relative to current working dir
        dataURL = [NSURL fileURLWithPath:@"Data" isDirectory:YES];
    }

    // Set gDataSpec to Data/System so colon paths work
    NSString* dataSystem = [[dataURL.path stringByStandardizingPath] stringByAppendingPathComponent:@"System"];
    EB_SetDataSpecFromHostPath([dataSystem fileSystemRepresentation]);
}

- (void)setupUI
{
    NSRect r = NSMakeRect(0, 0, 1024, 768);
    self.window = [[NSWindow alloc] initWithContentRect:r
                                              styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable|NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered defer:NO];
    [self.window setTitle:@"Mighty Mike Level Editor (Basic)"]; 
    [self.window makeKeyAndOrderFront:nil];

    // Left palette area
    NSView* content = self.window.contentView;
    NSView* leftPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, content.bounds.size.height)];
    leftPane.autoresizingMask = NSViewHeightSizable;
    [content addSubview:leftPane];

    // Right map scroll view fills remaining
    NSRect mapRect = NSMakeRect(240, 0, content.bounds.size.width-240, content.bounds.size.height);
    self.mapView = [[MMMapView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    self.scrollView = [[NSScrollView alloc] initWithFrame:mapRect];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = YES;
    self.scrollView.documentView = self.mapView;
    [content addSubview:self.scrollView];

    // Simple toolbar-like controls
    NSView* controls = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 28)];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:controls positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [controls.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:8],
        [controls.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:8],
        [controls.widthAnchor constraintEqualToConstant:300],
        [controls.heightAnchor constraintEqualToConstant:28],
    ]];

    NSButton* openBtn = [[NSButton alloc] initWithFrame:NSMakeRect(0,0,80,28)];
    openBtn.title = @"Open…"; openBtn.bezelStyle = NSBezelStyleRounded;
    openBtn.target = self; openBtn.action = @selector(onOpen:);
    [controls addSubview:openBtn];

    NSButton* saveBtn = [[NSButton alloc] initWithFrame:NSMakeRect(88,0,80,28)];
    saveBtn.title = @"Save As…"; saveBtn.bezelStyle = NSBezelStyleRounded;
    saveBtn.target = self; saveBtn.action = @selector(onSaveAs:);
    [controls addSubview:saveBtn];

    self.toolSeg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(176, 2, 260, 24)];
    self.toolSeg.segmentCount = 7;
    NSArray* labels = @[ @"Tile", @"Select", @"Fill", @"Line", @"Item", @"Alt", @"Attr" ];
    for (NSInteger i=0;i<7;i++){ [self.toolSeg setLabel:labels[i] forSegment:i]; }
    self.toolSeg.target = self; self.toolSeg.action = @selector(onToolChanged:);
    [controls addSubview:self.toolSeg];

    self.undoButton = [[NSButton alloc] initWithFrame:NSMakeRect(440, 2, 60, 24)];
    self.undoButton.title = @"Undo"; self.undoButton.bezelStyle = NSBezelStyleRounded;
    [self.undoButton setTarget:self]; self.undoButton.action = @selector(onUndo:);
    [controls addSubview:self.undoButton];

    self.redoButton = [[NSButton alloc] initWithFrame:NSMakeRect(504, 2, 60, 24)];
    self.redoButton.title = @"Redo"; self.redoButton.bezelStyle = NSBezelStyleRounded;
    [self.redoButton setTarget:self]; self.redoButton.action = @selector(onRedo:);
    [controls addSubview:self.redoButton];

    // Tile palette on left
    self.paletteView = [[MMTilePaletteView alloc] initWithFrame:NSMakeRect(0, 40, 240, content.bounds.size.height-40)];
    self.paletteView.delegate = (id)self;
    self.paletteView.columns = 4;
    self.paletteView.zoom = 1.0;
    self.paletteScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 40, 240, content.bounds.size.height-40)];
    self.paletteScroll.autoresizingMask = NSViewHeightSizable;
    self.paletteScroll.hasVerticalScroller = YES;
    self.paletteScroll.documentView = self.paletteView;
    [leftPane addSubview:self.paletteScroll];

    NSTextField* tileLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(4,8,36,20)];
    tileLbl.stringValue = @"Tile:"; tileLbl.editable = NO; tileLbl.bezeled = NO; tileLbl.drawsBackground = NO;
    [leftPane addSubview:tileLbl];

    self.tileField = [[NSTextField alloc] initWithFrame:NSMakeRect(44,6,60,24)];
    self.tileField.stringValue = @"0";
    self.tileField.target = self; self.tileField.action = @selector(onTileChanged:);
    [leftPane addSubview:self.tileField];

    self.altPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110,6,122,24) pullsDown:NO];
    [self.altPopup addItemsWithTitles:@[@"Alt: None", @"Up", @"Right", @"Down", @"Left", @"Up-Right", @"Down-Right", @"Down-Left", @"Left-Up", @"Stop", @"Loop" ]];
    self.altPopup.target = self; self.altPopup.action = @selector(onAltChanged:);
    [leftPane addSubview:self.altPopup];

    // Item editor controls
    NSTextField* itemLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-220, 60, 18)];
    itemLbl.stringValue = @"Item:"; itemLbl.editable=NO; itemLbl.bezeled=NO; itemLbl.drawsBackground=NO;
    itemLbl.autoresizingMask = NSViewMinYMargin;
    [leftPane addSubview:itemLbl];

    self.itemCategoryPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(60, content.bounds.size.height-222, 172, 24) pullsDown:NO];
    self.itemCategoryPopup.autoresizingMask = NSViewMinYMargin;
    [self.itemCategoryPopup addItemsWithTitles:@[@"Keys", @"Doors", @"Pickups", @"Enemies", @"Special"]];
    [self.itemCategoryPopup setTarget:self]; self.itemCategoryPopup.action = @selector(onItemCategoryChanged:);
    [leftPane addSubview:self.itemCategoryPopup];

    self.itemTypePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-196, 228, 24) pullsDown:NO];
    self.itemTypePopup.autoresizingMask = NSViewMinYMargin;
    [self.itemTypePopup setTarget:self]; self.itemTypePopup.action = @selector(onItemTypeChanged:);
    [leftPane addSubview:self.itemTypePopup];

    self.itemTypeField = [[NSTextField alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-172, 228, 22)];
    self.itemTypeField.placeholderString = @"Type # (override dropdown)";
    self.itemTypeField.autoresizingMask = NSViewMinYMargin;
    [leftPane addSubview:self.itemTypeField];
    NSArray* pl = @[ @"p0:", @"p1:", @"p2:", @"p3:" ];
    // no-op placeholder removed
    self.itemParm0 = [[NSTextField alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-148, 54, 20)];
    self.itemParm1 = [[NSTextField alloc] initWithFrame:NSMakeRect(64, content.bounds.size.height-148, 54, 20)];
    self.itemParm2 = [[NSTextField alloc] initWithFrame:NSMakeRect(124, content.bounds.size.height-148, 54, 20)];
    self.itemParm3 = [[NSTextField alloc] initWithFrame:NSMakeRect(184, content.bounds.size.height-148, 54, 20)];
    for (NSTextField* f in @[self.itemParm0,self.itemParm1,self.itemParm2,self.itemParm3]) { f.autoresizingMask=NSViewMinYMargin; [leftPane addSubview:f]; }

    // Seed item types
    if ([self respondsToSelector:@selector(onItemCategoryChanged:)])
    {
        [self performSelector:@selector(onItemCategoryChanged:) withObject:self.itemCategoryPopup];
    }

    // Minimal attribute editor below palette
    NSView* attrPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, content.bounds.size.height-140, 240, 140)];
    attrPanel.autoresizingMask = NSViewMinYMargin;
    [leftPane addSubview:attrPanel];
    NSArray* bitNames = @[ @"Top", @"Bottom", @"Left", @"Right", @"Death", @"Hurt", @"Water", @"Wind", @"BulletThrough", @"Stairs", @"Friction", @"Ice", @"Track" ];
    NSMutableArray<NSButton*>* boxes = [NSMutableArray array];
    for (NSInteger i=0;i<bitNames.count;i++){
        NSButton* cb = [[NSButton alloc] initWithFrame:NSMakeRect(4 + (i/7)*120, 30 + (i%7)*14, 116, 14)];
        cb.buttonType = NSButtonTypeSwitch; cb.title = bitNames[i]; cb.tag = (int)i; cb.font=[NSFont systemFontOfSize:10];
        [attrPanel addSubview:cb]; [boxes addObject:cb];
    }
    NSButton* applyAttr = [[NSButton alloc] initWithFrame:NSMakeRect(4, 8, 80, 18)];
    applyAttr.title = @"Apply Attr"; applyAttr.bezelStyle=NSBezelStyleRounded;
    [applyAttr setTarget:self];
    [applyAttr setAction:@selector(onApplyAttr:)];
    [attrPanel addSubview:applyAttr];
    objc_setAssociatedObject(self, &kAttrBoxesKeyStorage, boxes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)onTileChanged:(id)sender
{
    NSInteger t = self.tileField.integerValue;
    if (t < 0) t = 0;
    if (t > 2047) t = 2047; // TILENUM_MASK is 11 bits
    self.mapView.selectedTile = t;
    [self updateAttrPanelForTile:t];
}

- (void)onAltChanged:(id)sender
{
    self.mapView.altMode = self.altPopup.indexOfSelectedItem;
}

- (void)onApplyAttr:(id)sender
{
    NSInteger tile = self.tileField.integerValue;
    if (tile < 0) return;
    uint16_t bits = 0;
    static const void* kAttrBoxesKey = &kAttrBoxesKey;
    NSArray* boxes = (NSArray*)objc_getAssociatedObject(self, kAttrBoxesKey);
    for (NSButton* cb in boxes)
    {
        if (cb.state == NSControlStateValueOn)
        {
            switch (cb.tag)
            {
                case 0: bits |= TILE_ATTRIB_TOPSOLID; break;
                case 1: bits |= TILE_ATTRIB_BOTTOMSOLID; break;
                case 2: bits |= TILE_ATTRIB_LEFTSOLID; break;
                case 3: bits |= TILE_ATTRIB_RIGHTSOLID; break;
                case 4: bits |= TILE_ATTRIB_DEATH; break;
                case 5: bits |= TILE_ATTRIB_HURT; break;
                case 6: bits |= TILE_ATTRIB_WATER; break;
                case 7: bits |= TILE_ATTRIB_WIND; break;
                case 8: bits |= TILE_ATTRIB_BULLETGOESTHRU; break;
                case 9: bits |= TILE_ATTRIB_STAIRS; break;
                case 10: bits |= TILE_ATTRIB_FRICTION; break;
                case 11: bits |= TILE_ATTRIB_ICE; break;
                case 12: bits |= TILE_ATTRIB_TRACK; break;
            }
        }
    }
    EB_SetTileAttribBits((int)tile, bits);
}

- (void)updateAttrPanelForTile:(NSInteger)tile
{
    if (tile < 0) return;
    uint16_t bits = EB_GetTileAttribBits((int)tile);
    NSArray* boxes = (NSArray*)objc_getAssociatedObject(self, &kAttrBoxesKeyStorage);
    for (NSButton* cb in boxes)
    {
        uint16_t bit=0;
        switch (cb.tag)
        {
            case 0: bit = TILE_ATTRIB_TOPSOLID; break;
            case 1: bit = TILE_ATTRIB_BOTTOMSOLID; break;
            case 2: bit = TILE_ATTRIB_LEFTSOLID; break;
            case 3: bit = TILE_ATTRIB_RIGHTSOLID; break;
            case 4: bit = TILE_ATTRIB_DEATH; break;
            case 5: bit = TILE_ATTRIB_HURT; break;
            case 6: bit = TILE_ATTRIB_WATER; break;
            case 7: bit = TILE_ATTRIB_WIND; break;
            case 8: bit = TILE_ATTRIB_BULLETGOESTHRU; break;
            case 9: bit = TILE_ATTRIB_STAIRS; break;
            case 10: bit = TILE_ATTRIB_FRICTION; break;
            case 11: bit = TILE_ATTRIB_ICE; break;
            case 12: bit = TILE_ATTRIB_TRACK; break;
        }
        cb.state = (bits & bit) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)onToolChanged:(id)sender
{
    self.mapView.toolMode = self.toolSeg.selectedSegment;
}

- (void)onOpen:(id)sender
{
    NSOpenPanel* p = [NSOpenPanel openPanel];
    p.allowsMultipleSelection = NO;
    p.allowedFileTypes = @[ @"map-1", @"map-2", @"map-3", @"map" ];
    p.canChooseFiles = YES; p.canChooseDirectories = NO;
    if ([p runModal] != NSModalResponseOK) return;

    self.currentMapURL = p.URLs.firstObject;
    [self loadMapAtURL:self.currentMapURL];
}

- (void)onSaveAs:(id)sender
{
    if (!self.currentMapURL || !gPlayfieldHandle) return;

    NSSavePanel* sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = self.currentMapURL.lastPathComponent;
    if ([sp runModal] != NSModalResponseOK) return;

    EB_SaveMapToPath(sp.URL.fileSystemRepresentation);
}

- (void)loadMapAtURL:(NSURL*)mapURL
{
    // Derive scene name (prefix before first dot)
    NSString* name = mapURL.lastPathComponent;
    NSString* scene = [name componentsSeparatedByString:@"."].firstObject;
    if (scene.length == 0) return;

    // Load tileset for scene
    NSString* tilesetColonPath = [@":Maps:" stringByAppendingString:[scene stringByAppendingString:@".tileset"]];
    LoadTileSet(tilesetColonPath.UTF8String);

    // Load palette (overheadmap palette is good enough)
    LoadTGA(":Images:overheadmap.tga", true, NULL, NULL);

    // Copy the file into Data/Maps if opened from elsewhere, or temporarily set gDataSpec to its folder
    // Instead, read map colon path relative to Data using FileManager: if external, use a temp copy path
    // Simpler: compute colon path from game data root based on scene
    // But the map URL may be anywhere; for now, support in-place editing only if it’s under Data/Maps

    // Load the map via unpacker using colon path when available
    // If selected file resides within Data/Maps, compute colon path
    NSString* mapPath = mapURL.path.stringByStandardizingPath;
    BOOL isInData = [mapPath containsString:@"/Data/Maps/"];
    if (isInData)
    {
        // Build colon path starting at ":Maps:"
        NSString* colon = [@":Maps:" stringByAppendingString:mapURL.lastPathComponent];
        DisposeCurrentMapData();
        LoadPlayfield(colon.UTF8String);
    }
    else
    {
        // For now, only maps under Data/Maps are supported directly.
        return;
    }

    // Offsets managed internally by EditorBridge when saving

    // Build item list for editing
    BuildItemList();

    [self.mapView reloadBitmap];
    [self.paletteView updateSize];
    [self.window setTitle:[NSString stringWithFormat:@"Level Editor — %@", name]];
}

// Saving handled in EditorBridge

@end

#pragma mark - Tile palette delegate

@interface AppDelegate (Palette) <MMTilePaletteDelegate>
@end

@implementation AppDelegate (Palette)
- (void)tilePalette:(MMTilePaletteView *)palette didSelectTile:(NSInteger)tileIndex
{
    self.mapView.selectedTile = tileIndex;
    self.tileField.integerValue = tileIndex;
    self.paletteView.selectedTile = tileIndex;
    [self.paletteView setNeedsDisplay:YES];
}

- (void)onUndo:(id)sender { [self.mapView undo]; }
- (void)onRedo:(id)sender { [self.mapView redo]; }
@end

#pragma mark - Items

@interface AppDelegate (Items)
@end

@implementation AppDelegate (Items)

- (void)onItemCategoryChanged:(id)sender
{
    // Populate itemTypePopup based on category
    [self.itemTypePopup removeAllItems];
    switch (self.itemCategoryPopup.indexOfSelectedItem)
    {
        case 0: // Keys
            [self.itemTypePopup addItemsWithTitles:@[@"Key (19)", @"KeyColor (55)"]];
            break;
        case 1: // Doors
            [self.itemTypePopup addItemsWithTitles:@[@"Clown Door (20)", @"Candy Door (22)", @"Jurassic Door (31)", @"Fairy Door (44)", @"Bargain Door (52)"]];
            break;
        case 2: // Pickups
            [self.itemTypePopup addItemsWithTitles:@[@"Health (15)", @"Weapon Powerup (33)", @"Misc Powerup (34)", @"Gumball (35)", @"Ship POW (49)", @"Star (23)"]];
            break;
        case 3: // Enemies (subset)
            [self.itemTypePopup addItemsWithTitles:@[@"Caveman (0)", @"Baby Dino (8)", @"Rex (9)", @"Clown (13)", @"FlowerClown (16)", @"ChocBunny (24)", @"GBear (28)", @"Carmel (32)", @"LemonDrop (36)", @"Giant (37)", @"Dragon (38)", @"Witch (39)", @"BBWolf (40)", @"Soldier (41)", @"Spider (43)", @"Battery (45)", @"Slinky (47)", @"8Ball (48)", @"Robot (50)", @"Doggy (51)", @"Top (53)"]];
            break;
        default: // Special
            [self.itemTypePopup addItemsWithTitles:@[@"Teleport (17)", @"RaceCar (18)", @"MagicHat (14)"]];
            break;
    }
    [self onItemTypeChanged:self.itemTypePopup];
}

- (void)onItemTypeChanged:(id)sender
{
    NSString* title = self.itemTypePopup.selectedItem.title;
    NSRange r = [title rangeOfString:@"(" options:NSBackwardsSearch];
    if (r.location != NSNotFound)
    {
        NSInteger num = [[title substringFromIndex:r.location+1] integerValue];
        self.itemTypeField.integerValue = num;
    }
}

@end
