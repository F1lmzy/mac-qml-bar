#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <QCursor>
#include <QDir>
#include <QElapsedTimer>
#include <QKeyEvent>
#include <QQuickItem>
#include <QScreen>
#include <memory>
#include "host.h"
#include "geometry.h"

@interface DismissView : NSView
@property(copy) void (^dismiss)(void);
@end
@implementation DismissView
- (void)mouseDown:(NSEvent *)event { Q_UNUSED(event); if (self.dismiss) self.dismiss(); }
- (void)rightMouseDown:(NSEvent *)event { [self mouseDown:event]; }
@end

@interface DismissPanel : NSPanel
@end
@implementation DismissPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

static NSWindow *nativeWindow(QQuickView &view) {
    return [(__bridge NSView *)reinterpret_cast<void *>(view.winId()) window];
}

// Equivalent to omacosy's BarWindow.constrainFrameRect override. Subclass only
// this instance, never patch NSWindow/Qt globally or depend on private Qt headers.
static NSRect unconstrainedFrame(id, SEL, NSRect frame, NSScreen *) { return frame; }
static void allowMenuBarStrip(NSWindow *window) {
    const Class base = object_getClass(window);
    const QByteArray name = QByteArray("PillUnconstrained_") + class_getName(base);
    Class subclass = objc_getClass(name.constData());
    if (!subclass) {
        subclass = objc_allocateClassPair(base, name.constData(), 0);
        const SEL selector = @selector(constrainFrameRect:toScreen:);
        const Method method = class_getInstanceMethod(base, selector);
        if (!subclass || !method || !class_addMethod(subclass, selector,
            reinterpret_cast<IMP>(unconstrainedFrame), method_getTypeEncoding(method)))
            qFatal("Cannot create an unconstrained macOS panel");
        objc_registerClassPair(subclass);
    }
    object_setClass(window, subclass);
}

Host::Host(QQuickView &view, int topOffset, bool selfTest)
    : view(view), topOffset(topOffset), testing(selfTest) {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *window = nativeWindow(view);
    allowMenuBarStrip(window);
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.level = -20;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle
        | NSWindowCollectionBehaviorFullScreenAuxiliary;

    DismissPanel *panel = [[DismissPanel alloc] initWithContentRect:NSZeroRect
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO;
    panel.opaque = NO;
    // A nonzero alpha keeps the WindowServer hit-testable without a visible backdrop.
    panel.backgroundColor = [NSColor colorWithWhite:0 alpha:0.001];
    panel.hasShadow = NO;
    panel.hidesOnDeactivate = NO;
    panel.level = NSFloatingWindowLevel - 1;
    panel.collectionBehavior = window.collectionBehavior;
    DismissView *dismissView = [[DismissView alloc] initWithFrame:NSZeroRect];
    dismissView.dismiss = ^{ QMetaObject::invokeMethod(this->view.rootObject(), "dismiss"); };
    panel.contentView = dismissView;
    catcher = (__bridge_retained void *)panel;

    auto *root = view.rootObject();
    connect(root, &QQuickItem::widthChanged, this, &Host::syncGeometry);
    connect(root, &QQuickItem::heightChanged, this, &Host::syncGeometry);
    connect(root, SIGNAL(expandedChanged()), this, SLOT(updateMode()));
    connect(root, SIGNAL(hoverHeldChanged()), this, SLOT(syncGeometry()));
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &Host::syncGeometry);
    // Update placement after resolution changes and display hotplug.
    for (auto *screen : QGuiApplication::screens())
        connect(screen, &QScreen::geometryChanged, this, &Host::syncGeometry);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, [this](QScreen *screen) {
        connect(screen, &QScreen::geometryChanged, this, &Host::syncGeometry);
        syncGeometry();
    });

    pointerTimer.setInterval(16);
    connect(&pointerTimer, &QTimer::timeout, this, &Host::updatePointer);
    if (!testing) pointerTimer.start();
}

Host::~Host() {
    pointerTimer.stop();
    DismissPanel *panel = (__bridge DismissPanel *)catcher;
    ((DismissView *)panel.contentView).dismiss = nil;
    [panel close];
    CFBridgingRelease(catcher);
    if (previousApplication) CFBridgingRelease(previousApplication);
}

void Host::syncGeometry() {
    QScreen *screen = QGuiApplication::primaryScreen();
    if (!screen) return;
    view.setScreen(screen);
    auto *root = view.rootObject();
    NSWindow *window = nativeWindow(view);
    QRect frame = pillFrame(screen->geometry(),
        QSize(qRound(root->width()), qRound(root->height())), topOffset);
    // Match omacosy's notch policy: use the top strip, but move content out of
    // the unusable centre. Keep the collapsed pill's centre stable during morphs.
    if (window.screen.safeAreaInsets.top > 0) {
        const NSRect left = window.screen.auxiliaryTopLeftArea;
        const qreal centre = NSMaxX(left) - 12 - 125;
        frame.moveLeft(qRound(centre - frame.width() / 2.0));
    }
    view.setGeometry(frame);
    // Qt Quick can pause animation on an occluded Cocoa window. Raise as soon as
    // hover begins and keep it raised through the closing animation.
    const bool animating = root->width() > 250 || root->height() > 34;
    const NSInteger level = (expanded || root->property("hoverHeld").toBool() || animating)
        ? NSFloatingWindowLevel : -20;
    if (window.level != level) {
        window.level = level;
        if (level == NSFloatingWindowLevel) [window orderFrontRegardless];
    }
    NSPanel *panel = (__bridge NSPanel *)catcher;
    if (window.screen) [panel setFrame:window.screen.frame display:NO];
}

void Host::updatePointer() {
    const QPoint local = QCursor::pos() - view.position();
    bool inside = pillContains(QSizeF(view.size()), local);
    NSWindow *window = nativeWindow(view);
    if (window.ignoresMouseEvents == inside) window.ignoresMouseEvents = !inside;
    if (suppressHoverUntilExit) {
        if (!inside) suppressHoverUntilExit = false;
        inside = false;
    }
    view.rootObject()->setProperty("hovered", inside);
}

void Host::updateMode() {
    expanded = view.rootObject()->property("expanded").toBool();
    NSWindow *window = nativeWindow(view);
    NSPanel *panel = (__bridge NSPanel *)catcher;
    if (expanded) {
        suppressHoverUntilExit = false;
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (front.processIdentifier != NSProcessInfo.processInfo.processIdentifier)
            previousApplication = (__bridge_retained void *)front;
        window.level = NSFloatingWindowLevel;
        window.ignoresMouseEvents = NO;
        [panel orderFrontRegardless];
        [window orderFrontRegardless];
        if (!testing) {
            [NSApp activateIgnoringOtherApps:YES];
            view.requestActivate();
        }
        qInfo("expanded: catcher visible, panel level 3");
    } else {
        [panel orderOut:nil];
        syncGeometry();
        suppressHoverUntilExit = true;
        if (previousApplication) {
            NSRunningApplication *previous = (__bridge NSRunningApplication *)previousApplication;
            if (NSApp.active) [previous activateWithOptions:0];
            CFBridgingRelease(previousApplication);
            previousApplication = nullptr;
        }
        qInfo("closing: catcher hidden; return to level -20 after morph");
    }
}

void Host::runSelfTest(const QString &directory) {
    QDir().mkpath(directory);
    // Real Cocoa windows and QML rendering, not WindowServer input injection.
    auto failed = std::make_shared<bool>(false);
    auto check = [failed](bool condition, const char *message) {
        if (!condition) { qCritical("FAIL: %s", message); *failed = true; }
        else qInfo("PASS: %s", message);
    };
    auto capture = [this, directory, check](const QString &name) {
        check(view.grabWindow().save(directory + "/" + name + ".png"), "rendered screenshot saved");
    };
    auto phase = std::make_shared<int>(0);
    auto elapsed = std::make_shared<QElapsedTimer>();
    elapsed->start();
    auto *timer = new QTimer(this);
    timer->setInterval(20);
    connect(timer, &QTimer::timeout, this, [=] {
        if (elapsed->elapsed() > 5000) {
            qCritical() << "FAIL: native phase timed out" << *phase
                        << view.size() << view.rootObject()->size();
            timer->stop();
            QCoreApplication::exit(1);
            return;
        }
        auto *window = nativeWindow(view);
        auto *panel = (__bridge NSPanel *)catcher;
        auto *root = view.rootObject();
        switch (*phase) {
        case 0:
            check(window.level == -20, "collapsed native level");
            check(window.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces, "joins Spaces");
            check(view.size() == QSize(250, 34), "collapsed frame fits pill");
            check(qAbs(NSMaxY(window.frame) - NSMaxY(window.screen.frame) + topOffset) < 1,
                  "native frame aligns with requested screen top, not the menu-bar floor");
            check(!panel.visible, "no idle click catcher");
            capture("collapsed");
            root->setProperty("hovered", true);
            break;
        case 1:
            if (view.size() != QSize(360, 44) || root->size() != QSizeF(360, 44)) return;
            check(window.level == NSFloatingWindowLevel, "hover window raised to animate while occluded");
            check(root->size() == QSizeF(360, 44), "hover morph resizes native window");
            capture("hover");
            QMetaObject::invokeMethod(root, "open");
            break;
        case 2: {
            if (view.size() != QSize(440, 264) || root->size() != QSizeF(440, 264)) return;
            check(root->size() == QSizeF(440, 264), "expanded native geometry");
            check(window.level == NSFloatingWindowLevel, "expanded panel above ordinary windows");
            check(panel.visible, "expanded catcher visible");
            const auto screen = view.screen()->geometry();
            const qreal centre = window.screen.safeAreaInsets.top > 0
                ? NSMaxX(window.screen.auxiliaryTopLeftArea) - 12 - 125
                : screen.x() + screen.width() / 2.0;
            check(view.x() == qRound(centre - view.width() / 2.0), "pill centre remains stable");
            capture("mixer");
            auto *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
                context:nil eventNumber:0 clickCount:1 pressure:1];
            [(DismissView *)panel.contentView mouseDown:click];
            check(!root->property("expanded").toBool(), "native catcher dismisses panel");
            break;
        }
        case 3:
            if (view.size() != QSize(250, 34) || root->size() != QSizeF(250, 34)) return;
            check(window.level == -20, "closing animation returns to idle level");
            check(!panel.visible, "catcher removed after dismissal");
            QMetaObject::invokeMethod(root, "open");
            break;
        case 4: {
            if (view.size() != QSize(440, 264) || root->size() != QSizeF(440, 264)) return;
            QKeyEvent escape(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
            QCoreApplication::sendEvent(&view, &escape);
            check(!root->property("expanded").toBool(), "Escape reaches QML");
            break;
        }
        case 5:
            if (view.size() != QSize(250, 34) || root->size() != QSizeF(250, 34)) return;
            timer->stop();
            QCoreApplication::exit(*failed ? 1 : 0);
            return;
        }
        ++*phase;
        elapsed->restart();
    });
    timer->start();
}
