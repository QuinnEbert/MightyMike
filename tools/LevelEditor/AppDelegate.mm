#import "AppDelegate.h"
#import "MMMapView.h"

#import <Cocoa/Cocoa.h>

// Pull in game headers
extern "C" {
#include "myglobals.h"
#include "externs.h"
#include "playfield.h"
#include "picture.h"
#include "misc.h"
}

// Pull in Pomme to set gDataSpec
#import <PommeInit.h>
#import <PommeFiles.h>
#import "MMTilePaletteView.h"
#import <objc/runtime.h>

@interface AppDelegate ()
@property (strong) NSURL *currentMapURL;
@property (assign) int32_t offsetToMapImage;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self setupPommeAndDataSpec];
    [self setupUI];

    // Load a default palette so tiles have colors
    LoadTGA(":Images:overheadmap.tga", true, NULL, NULL);

    // Simple animation timer for tile anim preview
    self.animTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer* t){
        gFrames++;
        UpdateTileAnimation();
        [self.paletteView setNeedsDisplay:YES];
        [self.mapView setNeedsDisplay:YES];
    }];
}

- (void)setupPommeAndDataSpec
{
    Pomme::Init();

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
    auto dataSystem = (dataURL.path.stringByStandardizingPath).stringByAppendingPathComponent(@"System");
    FSSpec dataSpec = Pomme::Files::HostPathToFSSpec(std::string([dataSystem fileSystemRepresentation]));
    gDataSpec = dataSpec;
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

    self.toolSeg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(176, 2, 220, 24)];
    self.toolSeg.segmentCount = 7;
    NSArray* labels = @[ @"Tile", @"Select", @"Fill", @"Line", @"Item", @"Alt", @"Attr" ];
    for (NSInteger i=0;i<7;i++){ [self.toolSeg setLabel:labels[i] forSegment:i]; }
    self.toolSeg.target = self; self.toolSeg.action = @selector(onToolChanged:);
    [controls addSubview:self.toolSeg];

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
    [self.altPopup addItemsWithTitles:@[@"Alt: None", @"Up", @"Right", @"Down", @"Left" ]];
    self.altPopup.target = self; self.altPopup.action = @selector(onAltChanged:);
    [leftPane addSubview:self.altPopup];

    // Item editor controls
    NSTextField* itemLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-170, 60, 18)];
    itemLbl.stringValue = @"Item:"; itemLbl.editable=NO; itemLbl.bezeled=NO; itemLbl.drawsBackground=NO;
    itemLbl.autoresizingMask = NSViewMinYMargin;
    [leftPane addSubview:itemLbl];
    self.itemTypeField = [[NSTextField alloc] initWithFrame:NSMakeRect(60, content.bounds.size.height-172, 60, 22)];
    self.itemTypeField.autoresizingMask = NSViewMinYMargin;
    [leftPane addSubview:self.itemTypeField];
    NSArray* pl = @[ @"p0:", @"p1:", @"p2:", @"p3:" ];
    NSArray** fieldsPtr = NULL;
    self.itemParm0 = [[NSTextField alloc] initWithFrame:NSMakeRect(4, content.bounds.size.height-194, 54, 20)];
    self.itemParm1 = [[NSTextField alloc] initWithFrame:NSMakeRect(64, content.bounds.size.height-194, 54, 20)];
    self.itemParm2 = [[NSTextField alloc] initWithFrame:NSMakeRect(124, content.bounds.size.height-194, 54, 20)];
    self.itemParm3 = [[NSTextField alloc] initWithFrame:NSMakeRect(184, content.bounds.size.height-194, 54, 20)];
    for (NSTextField* f in @[self.itemParm0,self.itemParm1,self.itemParm2,self.itemParm3]) { f.autoresizingMask=NSViewMinYMargin; [leftPane addSubview:f]; }

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
    objc_setAssociatedObject(self, @"attrBoxes", boxes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)onTileChanged:(id)sender
{
    NSInteger t = self.tileField.integerValue;
    if (t < 0) t = 0;
    if (t > 2047) t = 2047; // TILENUM_MASK is 11 bits
    self.mapView.selectedTile = t;
}

- (void)onAltChanged:(id)sender
{
    self.mapView.altMode = self.altPopup.indexOfSelectedItem;
}

- (void)onApplyAttr:(id)sender
{
    NSInteger tile = self.tileField.integerValue;
    int count=0; TileAttribType* at = MM_GetTileAttribs(&count);
    if (!at || tile<0 || tile>=count) return;
    TileAttribType t = at[tile];
    t.bits = 0;
    NSArray* boxes = objc_getAssociatedObject(self, @"attrBoxes");
    for (NSButton* cb in boxes)
    {
        if (cb.state == NSControlStateValueOn)
        {
            switch (cb.tag)
            {
                case 0: t.bits |= TILE_ATTRIB_TOPSOLID; break;
                case 1: t.bits |= TILE_ATTRIB_BOTTOMSOLID; break;
                case 2: t.bits |= TILE_ATTRIB_LEFTSOLID; break;
                case 3: t.bits |= TILE_ATTRIB_RIGHTSOLID; break;
                case 4: t.bits |= TILE_ATTRIB_DEATH; break;
                case 5: t.bits |= TILE_ATTRIB_HURT; break;
                case 6: t.bits |= TILE_ATTRIB_WATER; break;
                case 7: t.bits |= TILE_ATTRIB_WIND; break;
                case 8: t.bits |= TILE_ATTRIB_BULLETGOESTHRU; break;
                case 9: t.bits |= TILE_ATTRIB_STAIRS; break;
                case 10: t.bits |= TILE_ATTRIB_FRICTION; break;
                case 11: t.bits |= TILE_ATTRIB_ICE; break;
                case 12: t.bits |= TILE_ATTRIB_TRACK; break;
            }
        }
    }
    MM_SetTileAttrib((int)tile, &t);
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

    // Update tile matrix back into packed buffer and write PACK_TYPE_NONE
    [self writePackedMapToURL:sp.URL];
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
        // Fallback: load via raw file API
        // Read file bytes, unpack using LoadPackedFile via temporary override of gDataSpec
        // Simplify: create a temporary symlink in Data/Maps and load from there
        NSString* tempName = mapURL.lastPathComponent;
        NSString* dataMaps = [[[NSString stringWithUTF8String:Pomme::Files::FSSpecToHostPath(gDataSpec).c_str()] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Maps"]; 
        NSString* tempPath = [dataMaps stringByAppendingPathComponent:tempName];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:mapPath toPath:tempPath error:nil];
        DisposeCurrentMapData();
        NSString* colon = [@":Maps:" stringByAppendingString:tempName];
        LoadPlayfield(colon.UTF8String);
    }

    // Remember offset to MAP_IMAGE so we can save later
    Ptr pfPtr = *gPlayfieldHandle;
    self.offsetToMapImage = UnpackI32BEInPlace(pfPtr + 2);

    [self.mapView reloadBitmap];
    [self.paletteView updateSize];
    [self.window setTitle:[NSString stringWithFormat:@"Level Editor — %@", name]];
}

- (void)writePackedMapToURL:(NSURL*)outURL
{
    if (!gPlayfieldHandle) return;

    // Update big-endian tile numbers back into the underlying buffer
    uint16_t* tempPtr = (uint16_t*)((*gPlayfieldHandle) + self.offsetToMapImage);
    // width/height already there
    int w = gPlayfieldTileWidth;
    int h = gPlayfieldTileHeight;
    tempPtr += 2; // skip width/height
    for (int y=0; y<h; y++)
    {
        for (int x=0; x<w; x++)
        {
            uint16_t v = gPlayfield[y][x];
            // Write as big-endian
            uint16_t be = ((v & 0xFF) << 8) | ((v >> 8) & 0xFF);
            *tempPtr++ = be;
        }
    }

    // Write PACK_TYPE_NONE header + payload
    FILE* f = fopen(outURL.path.fileSystemRepresentation, "wb");
    if (!f) return;
    uint32_t decompSize = (uint32_t) GetHandleSize(gPlayfieldHandle);
    uint32_t type = 2; // PACK_TYPE_NONE
    // write big-endian
    uint8_t hdr[8] = {
        (uint8_t)((decompSize>>24)&0xFF), (uint8_t)((decompSize>>16)&0xFF), (uint8_t)((decompSize>>8)&0xFF), (uint8_t)(decompSize&0xFF),
        (uint8_t)((type>>24)&0xFF), (uint8_t)((type>>16)&0xFF), (uint8_t)((type>>8)&0xFF), (uint8_t)(type&0xFF)
    };
    fwrite(hdr, 1, 8, f);
    fwrite(*gPlayfieldHandle, 1, decompSize, f);
    fclose(f);
}

@end

#pragma mark - Tile palette delegate

@interface AppDelegate (Palette) <MMTilePaletteDelegate>
@end

@implementation AppDelegate (Palette)
- (void)tilePalette:(MMTilePaletteView *)palette didSelectTile:(NSInteger)tileIndex
{
    self.mapView.selectedTile = tileIndex;
    self.tileField.integerValue = tileIndex;
}
@end
