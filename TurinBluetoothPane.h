/* TurinBluetoothPane: Bluetooth on/off, the paired keyboards and mice (connected or not, Forget), and the devices in
 * range to pair, with the code to type while a keyboard pairs. */
#import "TurinPane.h"
#import "TurinBluetooth.h"
#import "TurinUtil.h"

@interface TurinBluetoothPane : TurinPane {
	TurinBluetooth *bt;
	TurinSwitch *power;
	NSTextField *status;
	NSView *pairedList, *nearbyList;
	NSScrollView *pairedScroll, *nearbyScroll;
	NSButton *forgetButton, *pairButton, *searchButton, *cancelButton;
	NSTextField *scanLabel, *pairLabel;
}
@end
