/* TurinBluetooth: Bluetooth state and actions, the model half of Naples' NaplesBluetooth.m with its menu-bar panel left
 * out.
 *
 * Everything goes through iokit's /usr/sbin/btsetup (status, power, scan, pair, forget), which drives NetBSD's
 * Bluetooth tools on the kernel's netbt stack and prints tab-separated lines. Calls take seconds (a scan 10 s, pairing
 * up to 90 s), so they run on queues, never on the main thread; the change handler runs on the main thread. They need
 * root. Naples and Turin keep no state of their own: btsetup reads bthidd's /var/run/bthidd.status, the paired names
 * in /var/db/bluetooth-names, and /etc/bluetooth.off, so either one shows what the other did at its next poll. */
#import <AppKit/AppKit.h>

@interface TurinBluetooth : NSObject {
	void (^changed)(void);
	dispatch_queue_t queue, scanQueue;
	BOOL available, known, on, scanning, active;
	int powerPending;
	NSArray *devices;	/* paired: NSDictionary {addr, state, name} */
	NSArray *nearby;	/* the last scan, paired ones left out: {addr, kind, name} */
	NSString *pairing, *pairingName, *code;
	pid_t pairPid;
	NSString *message;
	dispatch_source_t pollTimer;
	NSTimeInterval lastScan;
}
- (id) initWithChangeHandler: (void (^)(void))handler;
- (BOOL) available;	/* NO: no /usr/sbin/btsetup on this system */
- (BOOL) known;	/* NO: no controller (no bt=1) */
- (BOOL) enabled;
- (NSArray *) devices;
- (NSArray *) nearby;
- (BOOL) scanning;
- (NSString *) pairing;	/* the address being paired, nil if none */
- (NSString *) pairingName;
- (NSString *) code;	/* the PIN or passkey to type on the device being paired, nil if none (yet) */
- (NSString *) message;	/* the last error, nil if none */
- (void) setActive: (BOOL)a;	/* the pane shows: poll faster and scan */
- (void) setEnabled: (BOOL)v;
- (void) scan;
- (void) pair: (NSDictionary *)device;
- (void) cancelPairing;
- (void) forget: (NSDictionary *)device;
@end

NSString *TurinBluetoothName(NSDictionary *device);	/* its name, or its address when it has none */
NSString *TurinBluetoothKind(NSString *kind);	/* "Keyboard", "Mouse", … for btsetup's kinds */
