#import "TurinBluetoothPane.h"

enum { ListRowH = 30 };

/* ---- a list of devices: the paired ones, or the ones in range ---- */

@interface TurinDeviceList : NSView {
	TurinBluetooth *bt;
	TurinBluetoothPane *pane;
	BOOL paired;
@public
	NSInteger selected;
}
- (id) initWithFrame: (NSRect)f bluetooth: (TurinBluetooth *)b pane: (TurinBluetoothPane *)p paired: (BOOL)isPaired;
- (NSDictionary *) selectedDevice;
- (void) reload;
@end

@interface TurinBluetoothPane (List)
- (void) update;
- (void) pairSelected: (id)sender;
- (void) listSelected: (TurinDeviceList *)list;
@end

@implementation TurinDeviceList

- (id) initWithFrame: (NSRect)f bluetooth: (TurinBluetooth *)b pane: (TurinBluetoothPane *)p paired: (BOOL)isPaired
{
	if ((self = [super initWithFrame: f])) { bt = b; pane = p; paired = isPaired; selected = -1; }
	return self;
}

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (NSArray *) shown { return ![bt enabled] && !paired ? nil : paired ? [bt devices] : [bt nearby]; }

- (void) reload
{
	NSScrollView *sv = [self enclosingScrollView];
	CGFloat h = MAX([sv contentSize].height, [[self shown] count] * ListRowH);
	if (selected >= (NSInteger)[[self shown] count]) selected = -1;
	if (h != NSHeight([self frame])) [self setFrameSize: NSMakeSize(NSWidth([self frame]), h)];
	[self setNeedsDisplay: YES];
}

- (NSRect) rowRect: (NSUInteger)i { return NSMakeRect(0, NSHeight([self bounds]) - (i + 1) * ListRowH, NSWidth([self bounds]), ListRowH); }

- (NSDictionary *) selectedDevice
{
	NSArray *d = [self shown];
	return selected >= 0 && selected < (NSInteger)[d count] ? [d objectAtIndex: selected] : nil;
}

- (void) deselect { if (selected != -1) { selected = -1; [self setNeedsDisplay: YES]; } }

/* the rune, as Naples draws it in the menu bar */
static void
rune(NSRect r, NSColor *color)
{
	CGFloat w = MIN(r.size.width, r.size.height * 0.62), h = r.size.height;
	CGFloat cx = NSMidX(r), l = cx - w / 2, rt = cx + w / 2, b = NSMinY(r) + 0.5, t = NSMaxY(r) - 0.5;
	NSBezierPath *p = [NSBezierPath bezierPath];
	[color set];
	[p setLineWidth: 1.5];
	[p setLineJoinStyle: NSRoundLineJoinStyle];
	[p setLineCapStyle: NSRoundLineCapStyle];
	[p moveToPoint: NSMakePoint(l, b + h * 0.27)];
	[p lineToPoint: NSMakePoint(rt, t - h * 0.25)];
	[p lineToPoint: NSMakePoint(cx, t)];
	[p lineToPoint: NSMakePoint(cx, b)];
	[p lineToPoint: NSMakePoint(rt, b + h * 0.25)];
	[p lineToPoint: NSMakePoint(l, t - h * 0.27)];
	[p stroke];
}

- (void) drawRect: (NSRect)dirty
{
	NSArray *devs = [self shown];
	NSUInteger i;
	NSDictionary *ta = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0.08 alpha: 1], NSForegroundColorAttributeName, nil];
	NSDictionary *sa = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
	                    [NSColor whiteColor], NSForegroundColorAttributeName, nil];
	NSDictionary *ga = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0 alpha: 0.5], NSForegroundColorAttributeName, nil];
	NSDictionary *gs = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 1 alpha: 0.8], NSForegroundColorAttributeName, nil];
	[[NSColor whiteColor] set];
	NSRectFill(dirty);
	if (![devs count]) {
		NSString *s = paired ? @"No devices are paired."
		            : ![bt enabled] ? @"Turn Bluetooth on to see the devices in range."
		            : [bt scanning] ? @"Searching for devices…" : @"No devices found. Put the device in pairing mode, then Search.";
		[s drawAtPoint: NSMakePoint(12, NSHeight([self bounds]) - 22) withAttributes: ga];
		return;
	}
	for (i = 0; i < [devs count]; i++) {
		NSDictionary *d = [devs objectAtIndex: i];
		NSRect r = [self rowRect: i];
		BOOL sel = (NSInteger)i == selected;
		NSString *right, *st = [d objectForKey: @"state"];
		NSSize sz;
		if (!NSIntersectsRect(r, dirty)) continue;
		if (sel) { [TurinAccent() set]; NSRectFill(r); }
		else if (i % 2) { [[NSColor colorWithCalibratedWhite: 0.965 alpha: 1] set]; NSRectFill(r); }
		rune(NSMakeRect(15, NSMidY(r) - 7, 9, 14), sel ? [NSColor whiteColor]
		     : paired && [st isEqual: @"connected"] ? TurinAccent() : [NSColor colorWithCalibratedWhite: 0.1 alpha: 1]);
		[TurinBluetoothName(d) drawAtPoint: NSMakePoint(40, NSMidY(r) - 8) withAttributes: sel ? sa : ta];
		if (paired)
			right = [NSString stringWithFormat: @"%@ · %@", [st isEqual: @"connected"] ? @"Connected"
			         : [st isEqual: @"connecting"] ? @"Connecting…" : @"Not Connected", [d objectForKey: @"addr"]];
		else if ([[bt pairing] isEqual: [d objectForKey: @"addr"]])
			right = @"Pairing…";
		else
			right = [NSString stringWithFormat: @"%@ · %@", TurinBluetoothKind([d objectForKey: @"kind"]), [d objectForKey: @"addr"]];
		sz = [right sizeWithAttributes: ga];
		[right drawAtPoint: NSMakePoint(NSWidth(r) - 14 - sz.width, NSMidY(r) - 7) withAttributes: sel ? gs : ga];
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
	NSUInteger i, n = [[self shown] count];
	for (i = 0; i < n; i++)
		if (NSPointInRect(p, [self rowRect: i])) {
			selected = i;
			[self setNeedsDisplay: YES];
			[pane listSelected: self];
			if ([e clickCount] == 2 && !paired) [pane pairSelected: nil];
			return;
		}
}

@end

/* ---- the pane ---- */

@implementation TurinBluetoothPane

- (NSString *) title { return @"Bluetooth"; }
- (TurinIconKind) icon { return TurinIconBluetooth; }

- (id) init
{
	if ((self = [super init]))
		bt = [[TurinBluetooth alloc] initWithChangeHandler: ^{ [self update]; }];
	return self;
}

- (NSScrollView *) scrollIn: (NSView *)v frame: (NSRect)f list: (NSView **)list paired: (BOOL)isPaired
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame: f];
	[sv setHasVerticalScroller: YES];
	[sv setBorderType: NSBezelBorder];
	*list = [[TurinDeviceList alloc] initWithFrame: NSMakeRect(0, 0, [sv contentSize].width, [sv contentSize].height)
	                                     bluetooth: bt pane: self paired: isPaired];
	[sv setDocumentView: *list];
	[v addSubview: sv];
	return sv;
}

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth;
	NSImageView *icon;
	NSImage *img;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 440, W - 40, 60)],
	    [NSValue valueWithRect: NSMakeRect(20, 250, W - 40, 176)],
	    [NSValue valueWithRect: NSMakeRect(20, 16, W - 40, 220)], nil]];
	/* header: the icon, the name, a status line and the switch */
	icon = [[[NSImageView alloc] initWithFrame: NSMakeRect(34, 452, 36, 36)] autorelease];
	img = [[[NSImage alloc] initWithSize: NSMakeSize(36, 36)] autorelease];
	[img lockFocus];
	TurinDrawIcon(TurinIconBluetooth, NSMakeRect(0, 0, 36, 36));
	[img unlockFocus];
	[icon setImage: img];
	[v addSubview: icon];
	[v addSubview: TurinLabel(NSMakeRect(80, 470, 200, 20), @"Bluetooth", 14, YES)];
	status = [TurinLabel(NSMakeRect(80, 450, 420, 18), @"", 11, NO) retain];
	[v addSubview: status];
	power = [[TurinSwitch alloc] initWithFrame: NSMakeRect(W - 80, 458, 40, 24)];
	[power setTarget: self];
	[power setAction: @selector(togglePower:)];
	[v addSubview: power];

	/* the paired devices */
	[v addSubview: TurinLabel(NSMakeRect(34, 396, 200, 18), @"My Devices", 12, YES)];
	pairedScroll = [self scrollIn: v frame: NSMakeRect(34, 296, W - 68, 96) list: &pairedList paired: YES];
	forgetButton = [TurinButton(NSMakeRect(W - 174, 260, 140, 26), @"Forget Device…", self, @selector(forget:)) retain];
	[v addSubview: forgetButton];

	/* the devices in range */
	[v addSubview: TurinLabel(NSMakeRect(34, 206, 200, 18), @"Nearby Devices", 12, YES)];
	scanLabel = [TurinLabel(NSMakeRect(160, 206, 200, 18), @"", 11, NO) retain];
	[scanLabel setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.5]];
	[v addSubview: scanLabel];
	nearbyScroll = [self scrollIn: v frame: NSMakeRect(34, 92, W - 68, 110) list: &nearbyList paired: NO];
	pairLabel = [TurinLabel(NSMakeRect(34, 58, W - 68, 28), @"", 13, NO) retain];
	[v addSubview: pairLabel];
	cancelButton = [TurinButton(NSMakeRect(34, 26, 100, 26), @"Cancel", self, @selector(cancelPairing:)) retain];
	searchButton = [TurinButton(NSMakeRect(W - 234, 26, 90, 26), @"Search", self, @selector(search:)) retain];
	pairButton = [TurinButton(NSMakeRect(W - 134, 26, 100, 26), @"Pair", self, @selector(pairSelected:)) retain];
	[v addSubview: cancelButton];
	[v addSubview: searchButton];
	[v addSubview: pairButton];
	[self update];
}

- (void) dealloc
{
	[bt release]; [power release]; [status release]; [pairedList release]; [nearbyList release];
	[pairedScroll release]; [nearbyScroll release]; [forgetButton release]; [pairButton release]; [searchButton release];
	[cancelButton release]; [scanLabel release]; [pairLabel release];
	[super dealloc];
}

- (void) didShow { [bt setActive: YES]; }
- (void) didHide { [bt setActive: NO]; }

- (void) update
{
	NSString *s, *p = @"";
	BOOL root = TurinIsRoot(), on = [bt enabled], busy = [bt pairing] != nil;
	if (!status) return;	/* not loaded yet */
	if (![bt available]) s = @"This system has no Bluetooth tools (/usr/sbin/btsetup).";
	else if (![bt known]) s = @"No Bluetooth hardware answered (boot with bt=1).";
	else if (!on) s = @"Off";
	else if ([[bt devices] count]) {
		NSUInteger n = 0;
		NSDictionary *d;
		for (d in [bt devices]) if ([[d objectForKey: @"state"] isEqual: @"connected"]) n++;
		s = n ? [NSString stringWithFormat: @"On · %lu device%@ connected", (unsigned long)n, n == 1 ? @"" : @"s"] : @"On";
	} else s = @"On · Keyboards and mice can be paired below.";
	if (!root && [bt known]) s = [s stringByAppendingString: @" — changing Bluetooth needs the root account."];
	[status setStringValue: s];
	[status setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
	if (busy && [bt code])
		p = [NSString stringWithFormat: @"Type %@ on “%@”, then press Return.", [bt code], [bt pairingName]];
	else if (busy)
		p = [NSString stringWithFormat: @"Pairing with “%@”…", [bt pairingName]];
	else if ([bt message])
		p = [bt message];
	[pairLabel setStringValue: p];
	[pairLabel setTextColor: !busy && [bt message] ? [NSColor colorWithCalibratedRed: 0.8 green: 0.15 blue: 0.12 alpha: 1]
	                                               : [NSColor colorWithCalibratedWhite: 0.08 alpha: 1]];
	[pairLabel setFont: busy && [bt code] ? [NSFont boldSystemFontOfSize: 14] : [NSFont systemFontOfSize: 12]];
	[power setOn: on];
	[power setEnabled: [bt known] && root && !busy];
	[forgetButton setEnabled: root && !busy && [(TurinDeviceList *)pairedList selectedDevice] != nil];
	[pairButton setEnabled: root && on && !busy && [(TurinDeviceList *)nearbyList selectedDevice] != nil];
	[searchButton setEnabled: on && !busy && ![bt scanning]];
	[cancelButton setHidden: !busy];
	[scanLabel setStringValue: [bt scanning] ? @"Searching…" : @""];
	[(TurinDeviceList *)pairedList reload];
	[(TurinDeviceList *)nearbyList reload];
}

/* one selection at a time across the two lists, so the buttons say what they act on */
- (void) listSelected: (TurinDeviceList *)list
{
	if (list == (TurinDeviceList *)pairedList) [(TurinDeviceList *)nearbyList deselect];
	else [(TurinDeviceList *)pairedList deselect];
	[self update];
}

- (void) togglePower: (id)sender { [bt setEnabled: [power isOn]]; }
- (void) search: (id)sender { [bt scan]; }
- (void) cancelPairing: (id)sender { [bt cancelPairing]; }

- (void) pairSelected: (id)sender
{
	NSDictionary *d = [(TurinDeviceList *)nearbyList selectedDevice];
	if (!d || !TurinIsRoot() || [bt pairing]) return;
	[bt pair: d];
}

- (void) forget: (id)sender
{
	NSDictionary *d = [(TurinDeviceList *)pairedList selectedDevice];
	if (!d) return;
	[TurinDialog showIn: [view window] title: [NSString stringWithFormat: @"Forget “%@”?", TurinBluetoothName(d)]
	            message: @"The Pi will disconnect this device and remove its pairing. To use it again, pair it again."
	             fields: nil checkbox: nil checked: NO okTitle: @"Forget"
	         completion: ^BOOL(BOOL ok, NSArray *values, BOOL checked) {
		if (ok) [bt forget: d];
		return YES;
	}];
}

@end
