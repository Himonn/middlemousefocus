// g++ -O2 -Wall -fobjc-arc -D"NS_FORMAT_ARGUMENT(A)=" -o MiddleMouseFocus MiddleMouseFocus.mm \
//   -framework AppKit && ./MiddleMouseFocus

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>
#include <Carbon/Carbon.h>

CFMachPortRef eventTap = NULL;
static AXUIElementRef _accessibility_object = AXUIElementCreateSystemWide();

// Helper method to raise and activate a window
inline void raiseAndActivate(AXUIElementRef _window, pid_t window_pid) {
    if (AXUIElementPerformAction(_window, kAXRaiseAction) == kAXErrorSuccess) {
        [[NSRunningApplication runningApplicationWithProcessIdentifier: window_pid]
            activateWithOptions: NSApplicationActivateIgnoringOtherApps];
    }
}

// Get the window under the mouse cursor
AXUIElementRef get_mousewindow(CGPoint point) {
    AXUIElementRef _element = NULL;
    AXError error = AXUIElementCopyElementAtPosition(_accessibility_object, point.x, point.y, &_element);

    AXUIElementRef _window = NULL;
    if (_element) {
        AXUIElementCopyAttributeValue(_element, kAXWindowAttribute, (CFTypeRef *) &_window);
        if (!_window) {
            CFRelease(_element);
        }
    }

    return _window;
}

// Event tap handler
CGEventRef eventTapHandler(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    if (type == kCGEventOtherMouseDown) {
        CGMouseButton button = (CGMouseButton) CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        if (button == kCGMouseButtonCenter) {
            CGPoint mousePoint = CGEventGetLocation(event);
            AXUIElementRef _window = get_mousewindow(mousePoint);
            if (_window) {
                pid_t window_pid;
                if (AXUIElementGetPid(_window, &window_pid) == kAXErrorSuccess) {
                    raiseAndActivate(_window, window_pid);
                }
                CFRelease(_window);
            }
        }
    } else if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(eventTap, true);
    }

    return event;
}

//int main(int argc, const char * argv[]) {
//    @autoreleasepool {
//        eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
//            CGEventMaskBit(kCGEventOtherMouseDown), eventTapHandler, NULL);
//        if (eventTap) {
//            CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
//            if (runLoopSource) {
//                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
//                CGEventTapEnable(eventTap, true);
//            }
//        }
//
//        [[NSApplication sharedApplication] run];
//    }
//    return 0;
//}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    // Load icon from the .icns file in the app bundle
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"MiddleMouseFocus" ofType:@"icns"];
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    [self.statusItem.button setImage:icon];

    self.statusItem.button.action = @selector(handleMenuAction:);
    self.statusItem.button.target = self;

    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
            CGEventMaskBit(kCGEventOtherMouseDown), eventTapHandler, NULL);
    if (eventTap) {
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        if (runLoopSource) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
            CGEventTapEnable(eventTap, true);
        }
    }
}

- (void)handleMenuAction:(id)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    [self.statusItem popUpStatusItemMenu:menu];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}