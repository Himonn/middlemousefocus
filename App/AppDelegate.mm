#import "AppDelegate.h"
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>

static CFMachPortRef eventTap = NULL;
static AXUIElementRef accessibilityObject = NULL;
static NSInteger triggerButton = kCGMouseButtonCenter;
static BOOL isCapturingButton = NO;
static BOOL eventTapActive = NO;

static void raiseAndActivate(AXUIElementRef window, pid_t windowPid) {
    if (AXUIElementPerformAction(window, kAXRaiseAction) == kAXErrorSuccess) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:windowPid];
        if (@available(macOS 14.0, *)) {
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        } else {
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
    }
}

static AXUIElementRef get_mousewindow(CGPoint point) {
    AXUIElementRef element = NULL;
    AXError error = AXUIElementCopyElementAtPosition(accessibilityObject, point.x, point.y, &element);

    if (error != kAXErrorSuccess || !element) {
        NSLog(@"[MMF] AXUIElementCopyElementAtPosition failed: AXError %d", error);
        return NULL;
    }

    // Try to get the containing window from the element
    AXUIElementRef window = NULL;
    AXUIElementCopyAttributeValue(element, kAXWindowAttribute, (CFTypeRef *)&window);

    if (window) {
        CFRelease(element);
        return window;
    }

    // The element itself may be the window (e.g. clicking on empty window background)
    CFStringRef role = NULL;
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute, (CFTypeRef *)&role);
    BOOL isWindow = role && CFStringCompare(role, kAXWindowRole, 0) == kCFCompareEqualTo;
    if (role) CFRelease(role);

    if (isWindow) {
        NSLog(@"[MMF] Element is the window directly — using it");
        return element;
    }

    NSLog(@"[MMF] Element found but no window could be resolved");
    CFRelease(element);
    return NULL;
}

static CGEventRef eventTapHandler(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    if (type == kCGEventOtherMouseDown) {
        CGMouseButton button = (CGMouseButton)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);

        if (isCapturingButton) {
            isCapturingButton = NO;
            triggerButton = button;
            [[NSUserDefaults standardUserDefaults] setInteger:button forKey:@"triggerButton"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSLog(@"[MMF] Trigger button set to %ld", (long)button);
            [NSApp stopModal];
            return NULL;
        }

        if (button == (CGMouseButton)triggerButton) {
            NSLog(@"[MMF] Trigger fired (button %ld)", (long)button);
            CGPoint mousePoint = CGEventGetLocation(event);
            AXUIElementRef window = get_mousewindow(mousePoint);
            if (window) {
                NSLog(@"[MMF] Window found — raising");
                pid_t windowPid;
                if (AXUIElementGetPid(window, &windowPid) == kAXErrorSuccess) {
                    raiseAndActivate(window, windowPid);
                }
                CFRelease(window);
            } else {
                NSLog(@"[MMF] No window found at cursor — accessibility may be missing");
            }
        }
    } else if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(eventTap, true);
    }

    return event;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    accessibilityObject = AXUIElementCreateSystemWide();

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"triggerButton": @(kCGMouseButtonCenter)}];
    triggerButton = [[NSUserDefaults standardUserDefaults] integerForKey:@"triggerButton"];

    [self setupStatusItem];
    [self checkAccessibilityAndSetupEventTap];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    NSImage *icon = [NSImage imageNamed:@"StatusBarIcon"];
    [icon setTemplate:YES];
    icon.size = NSMakeSize(20, 20);
    [self.statusItem.button setImage:icon];

    self.statusItem.button.action = @selector(handleMenuAction:);
    self.statusItem.button.target = self;
}

- (void)checkAccessibilityAndSetupEventTap {
    if (AXIsProcessTrusted()) {
        [self setupEventTap];
    } else {
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        [self pollForAccessibilityPermission];
    }
}

- (void)pollForAccessibilityPermission {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (AXIsProcessTrusted()) {
            [self setupEventTap];
        } else {
            [self pollForAccessibilityPermission];
        }
    });
}

- (void)setupEventTap {
    if (eventTap != NULL) {
        return;
    }

    eventTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        CGEventMaskBit(kCGEventOtherMouseDown),
        eventTapHandler,
        NULL
    );

    if (!eventTap) {
        NSLog(@"[MMF] CGEventTapCreate failed — accessibility permission may not have taken effect yet, retrying in 2s");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (AXIsProcessTrusted()) {
                [self setupEventTap];
            }
        });
        return;
    }

    NSLog(@"[MMF] Event tap created successfully");
    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    if (runLoopSource) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, (CFStringRef)NSModalPanelRunLoopMode);
        CGEventTapEnable(eventTap, true);
        CFRelease(runLoopSource);
        eventTapActive = YES;
        NSLog(@"[MMF] Event tap active, listening for button %ld", (long)triggerButton);
    }
}

- (NSString *)buttonName:(NSInteger)button {
    if (button == kCGMouseButtonCenter) return @"Middle Click";
    return [NSString stringWithFormat:@"Button %ld", (long)(button + 1)];
}

- (void)handleMenuAction:(id)sender {
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *appTitleItem = [[NSMenuItem alloc] initWithTitle:@"Middle Mouse Focus" action:nil keyEquivalent:@""];
    [appTitleItem setEnabled:NO];
    [menu addItem:appTitleItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *statusTitle;
    SEL statusAction = nil;
    if (eventTapActive) {
        statusTitle = @"Status: Active ✓";
    } else if (AXIsProcessTrusted()) {
        statusTitle = @"Status: Restart Required";
    } else {
        statusTitle = @"Grant Accessibility Access…";
        statusAction = @selector(requestAccessibility:);
    }
    NSMenuItem *statusItem = [[NSMenuItem alloc] initWithTitle:statusTitle action:statusAction keyEquivalent:@""];
    [statusItem setEnabled:statusAction != nil];
    [menu addItem:statusItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *triggerLabel = [NSString stringWithFormat:@"Trigger: %@", [self buttonName:triggerButton]];
    NSMenuItem *triggerItem = [[NSMenuItem alloc] initWithTitle:triggerLabel action:nil keyEquivalent:@""];
    [triggerItem setEnabled:NO];
    [menu addItem:triggerItem];

    [menu addItemWithTitle:@"Change Trigger Button…" action:@selector(changeButton:) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Version 2.0.0" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"About" action:@selector(showAbout:) keyEquivalent:@""];
    [menu addItemWithTitle:@"GitHub" action:@selector(openSourceCode:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Help" action:@selector(openMailClient:) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];

    [self.statusItem popUpStatusItemMenu:menu];
}

- (void)requestAccessibility:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    [self pollForAccessibilityPermission];
}

- (void)changeButton:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Change Trigger Button";
    alert.informativeText = @"Press any mouse button (except left or right click) to set it as the new trigger. The dialog will close automatically.";
    [alert addButtonWithTitle:@"Cancel"];

    isCapturingButton = YES;
    NSModalResponse response = [alert runModal];

    if (response == NSAlertFirstButtonReturn) {
        // User cancelled
        isCapturingButton = NO;
    }
}

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Middle Mouse Focus";
    alert.informativeText = @"Press your middle mouse button to raise and focus the hovered window.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)openSourceCode:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/Himonn/middlemousefocus"]];
}

- (void)openMailClient:(id)sender {
    NSString *email = @"mailto:middlemousefocus@himon.dev?subject=Help";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:email]];
}

@end
