#import "TurinBluetooth.h"
#import "TurinUtil.h"
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define BtSetup "/usr/sbin/btsetup"

/* Runs btsetup and hands each line it prints, split at tabs, to `line` (on the calling queue). *pidOut holds its pid
 * while it runs, so a pairing can be cancelled. Callers judge by the lines, not the exit status (see TurinRun). */
static void
runSetup(const char *a1, const char *a2, const char *a3, const char *a4, pid_t *pidOut, void (^line)(NSArray *fields))
{
	char *argv[6] = { BtSetup, (char *)a1, (char *)a2, (char *)a3, (char *)a4, NULL };
	posix_spawn_file_actions_t fa;
	int fds[2], st;
	pid_t pid;
	FILE *f;
	char buf[512];
	if (pipe(fds) != 0) return;
	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_adddup2(&fa, fds[1], 1);
	posix_spawn_file_actions_addclose(&fa, fds[0]);
	if (posix_spawn(&pid, BtSetup, &fa, NULL, argv, environ) != 0) {
		posix_spawn_file_actions_destroy(&fa);
		close(fds[0]); close(fds[1]);
		return;
	}
	posix_spawn_file_actions_destroy(&fa);
	close(fds[1]);
	if (pidOut) *pidOut = pid;
	if ((f = fdopen(fds[0], "r")) != NULL) {
		while (fgets(buf, sizeof buf, f)) {
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			NSString *s;
			buf[strcspn(buf, "\r\n")] = 0;
			s = [NSString stringWithUTF8String: buf];
			if (s && line) line([s componentsSeparatedByString: @"\t"]);
			[pool release];
		}
		fclose(f);
	} else {
		close(fds[0]);
	}
	while (waitpid(pid, &st, 0) < 0 && errno == EINTR) ;
	if (pidOut) *pidOut = 0;
}

static NSString *
field(NSArray *f, NSUInteger i)
{
	return i < [f count] ? [f objectAtIndex: i] : @"";
}

NSString *
TurinBluetoothName(NSDictionary *d)
{
	NSString *n = [d objectForKey: @"name"];
	return [n length] ? n : [d objectForKey: @"addr"];
}

NSString *
TurinBluetoothKind(NSString *kind)
{
	if ([kind isEqual: @"keyboard"]) return @"Keyboard";
	if ([kind isEqual: @"mouse"]) return @"Mouse";
	if ([kind isEqual: @"combo"]) return @"Keyboard and Mouse";
	if ([kind isEqual: @"phone"]) return @"Phone";
	if ([kind isEqual: @"computer"]) return @"Computer";
	if ([kind isEqual: @"audio"]) return @"Audio";
	return @"Device";
}

@implementation TurinBluetooth

- (id) initWithChangeHandler: (void (^)(void))handler
{
	if ((self = [super init])) {
		changed = Block_copy(handler);
		available = access(BtSetup, X_OK) == 0;
		queue = dispatch_queue_create("turin.bluetooth", NULL);
		scanQueue = dispatch_queue_create("turin.bluetooth.scan", NULL);
		pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_source_set_timer(pollTimer, DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC, NSEC_PER_SEC);
		dispatch_source_set_event_handler(pollTimer, ^{ TurinRunOnMain(^{ [self poll]; }); });
		if (available) dispatch_resume(pollTimer);
	}
	return self;
}

- (BOOL) available { return available; }
- (BOOL) known { return known; }
- (BOOL) enabled { return on; }
- (NSArray *) devices { return devices; }
- (NSArray *) nearby { return nearby; }
- (BOOL) scanning { return scanning; }
- (NSString *) pairing { return pairing; }
- (NSString *) pairingName { return pairingName; }
- (NSString *) code { return code; }
- (NSString *) message { return message; }

- (void) setMessage: (NSString *)m { if (m != message) { [message release]; message = [m copy]; } }
- (void) setCode: (NSString *)c { if (c != code) { [code release]; code = [c copy]; } }
- (void) notify { if (changed) changed(); }

- (void) setActive: (BOOL)a
{
	if (a == active || !available) return;
	active = a;
	dispatch_source_set_timer(pollTimer, DISPATCH_TIME_NOW, (a ? 2 : 10) * NSEC_PER_SEC, NSEC_PER_SEC);
	if (a) { [self setMessage: nil]; lastScan = 0; }
}

- (void) poll
{
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSMutableArray *devs = [NSMutableArray array];
		__block NSString *power = nil;
		runSetup("status", NULL, NULL, NULL, NULL, ^(NSArray *f) {
			if ([field(f, 0) isEqual: @"power"]) power = [field(f, 1) retain];
			else if ([field(f, 0) isEqual: @"device"])
				[devs addObject: [NSDictionary dictionaryWithObjectsAndKeys: field(f, 1), @"addr", field(f, 2), @"state",
				                  field(f, 3), @"name", nil]];
		});
		/* a plain local, which the block retains: a __block one it does not (MRC), and the pool frees it */
		NSString *pw = [power autorelease];
		TurinRunOnMain(^{
			NSString *power = pw;
			known = power && ![power isEqual: @"none"];
			if (!powerPending) on = known && [power isEqual: @"on"];
			[devices release];
			devices = [devs copy];
			if (active && on && !pairing && [NSDate timeIntervalSinceReferenceDate] - lastScan > 30) [self scan];
			[self notify];
		});
		[pool release];
	});
}

- (void) scan
{
	if (scanning || !on || pairing) return;
	scanning = YES;
	lastScan = [NSDate timeIntervalSinceReferenceDate];
	[self notify];
	dispatch_async(scanQueue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSMutableArray *found = [NSMutableArray array];
		runSetup("scan", NULL, NULL, NULL, NULL, ^(NSArray *f) {
			if ([field(f, 0) isEqual: @"found"])
				[found addObject: [NSDictionary dictionaryWithObjectsAndKeys: field(f, 1), @"addr", field(f, 2), @"kind",
				                   field(f, 3), @"name", nil]];
		});
		TurinRunOnMain(^{
			NSMutableArray *list = [NSMutableArray array];
			NSDictionary *n, *d;
			scanning = NO;
			for (n in found) {
				BOOL paired = NO;
				for (d in devices)
					if ([[d objectForKey: @"addr"] caseInsensitiveCompare: [n objectForKey: @"addr"]] == NSOrderedSame) paired = YES;
				if (!paired) [list addObject: n];
			}
			if (on) { [nearby release]; nearby = [list copy]; }
			[self notify];
		});
		[pool release];
	});
}

- (void) setEnabled: (BOOL)v
{
	if (powerPending || pairing) return;
	on = v;
	powerPending++;
	[self setMessage: nil];
	if (!v) { [nearby release]; nearby = nil; }
	[self notify];
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		__block NSString *err = nil;
		runSetup("power", v ? "on" : "off", NULL, NULL, NULL, ^(NSArray *f) {
			if ([field(f, 0) isEqual: @"error"]) err = [field(f, 1) retain];
		});
		NSString *failure = [err autorelease];
		TurinRunOnMain(^{
			NSString *err = failure;
			powerPending--;
			if (err) { [self setMessage: err]; on = !v; }
			[self poll];
			if (v && !err && active) [self performSelector: @selector(scan) withObject: nil afterDelay: 0.5];
			[self notify];
		});
		[pool release];
	});
}

- (void) pair: (NSDictionary *)device
{
	NSString *addr = [[[device objectForKey: @"addr"] copy] autorelease];
	NSString *kind = [[[device objectForKey: @"kind"] copy] autorelease];
	NSString *name = [[[device objectForKey: @"name"] copy] autorelease];
	if (pairing || !on || !addr) return;
	pairing = [addr copy];
	[pairingName release];
	pairingName = [TurinBluetoothName(device) copy];
	[self setCode: nil];
	[self setMessage: nil];
	[self notify];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		__block BOOL paired = NO;
		__block NSString *err = nil;
		runSetup("pair", [addr UTF8String], [kind UTF8String], [name UTF8String], &pairPid, ^(NSArray *f) {
			NSString *what = field(f, 0), *val = field(f, 1);
			if ([what isEqual: @"pin"] || [what isEqual: @"passkey"])
				TurinRunOnMain(^{ if ([pairing isEqual: addr]) { [self setCode: val]; [self notify]; } });
			else if ([what isEqual: @"paired"])
				paired = YES;
			else if ([what isEqual: @"error"]) { [err release]; err = [val retain]; }
		});
		NSString *failure = [err autorelease];
		TurinRunOnMain(^{
			NSString *err = failure;
			if (![pairing isEqual: addr]) return;	/* cancelled */
			[pairing release];
			pairing = nil;
			[self setCode: nil];
			if (!paired) [self setMessage: err ? err : @"Pairing did not finish."];
			else { [nearby release]; nearby = nil; lastScan = 0; }
			[self poll];
			[self notify];
		});
		[pool release];
	});
}

- (void) cancelPairing
{
	NSString *addr = [[pairing copy] autorelease];
	pid_t pid = pairPid;
	if (!addr) return;
	[pairing release];
	pairing = nil;
	[self setCode: nil];
	if (pid > 0) kill(pid, SIGTERM);
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		runSetup("forget", [addr UTF8String], NULL, NULL, NULL, NULL);	/* nothing left half-paired */
		TurinRunOnMain(^{ [self poll]; });
		[pool release];
	});
	[self notify];
}

- (void) forget: (NSDictionary *)device
{
	NSString *addr = [[[device objectForKey: @"addr"] copy] autorelease];
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		runSetup("forget", [addr UTF8String], NULL, NULL, NULL, NULL);
		TurinRunOnMain(^{ [self poll]; });
		[pool release];
	});
}

@end
