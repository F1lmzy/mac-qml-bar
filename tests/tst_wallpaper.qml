import QtQuick
import QtTest
import "../qml/ricelin"

TestCase {
    name: "PillWallpaperCarousel"
    when: windowShown
    visible: true
    width: 640
    height: 320

    QtObject {
        id: system
        property var theme: ({})
        property var calls: []
        signal stateChanged()
        signal errorOccurred(string domain, string operation, string code, string message)
        function invoke(domain, action, argument) {
            calls = calls.concat([{domain: domain, action: action, argument: argument}]);
        }
    }

    WallpaperCarousel {
        id: carousel
        width: 520
        height: 236
        s: 1
        open: true
        systemService: system
    }

    function fixtureTheme() {
        const url = String(Qt.resolvedUrl("fixtures/wallpaper.png"));
        return {
            available: true, slug: "fixture", busy: false,
            canSetBackground: true, canNextBackground: true, canResyncWallpaper: true,
            backgroundPath: "/tmp/b.png",
            wallpapers: [
                {path: "/tmp/a.png", url: url, thumb: "file:///tmp/cached-thumb.jpg", name: "First"},
                {path: "/tmp/b.png", url: url, thumb: "", name: "Current"},
                {path: "/tmp/c.png", url: url, thumb: "file:///tmp/cached-third.jpg", name: "Third"}
            ]
        };
    }

    function init() {
        system.calls = [];
        system.theme = fixtureTheme();
        carousel.clearPending();
        carousel.centerOnCurrent();
    }

    function test_centersOnCurrentAndMovementClamps() {
        compare(carousel.focusIndex, 1);
        compare(carousel.pos, 1);
        carousel.move(1);
        compare(carousel.focusIndex, 2);
        carousel.move(1);
        compare(carousel.focusIndex, 2);
        carousel.move(-2);
        compare(carousel.focusIndex, 0);
        carousel.move(-1);
        compare(carousel.focusIndex, 0);
    }

    function test_activateAppliesConfirmedBackground() {
        carousel.focusIndex = 2;
        carousel.activate();
        compare(system.calls.length, 1);
        compare(system.calls[0].domain, "theme");
        compare(system.calls[0].action, "setBackground");
        compare(system.calls[0].argument.path, "/tmp/c.png");
        compare(system.calls[0].argument.slug, "fixture");
        verify(system.calls[0].argument.confirmed);
        compare(carousel.pendingAction, "");
    }

    function test_focusChangeDoesNotWrite() {
        carousel.move(1);
        compare(carousel.focusIndex, 2);
        compare(system.calls.length, 0);
    }

    function test_tilePrefersThumbAndFallsBackToOriginal() {
        const thumbImage = findChild(carousel, "wallpaperImage_0");
        const fallbackImage = findChild(carousel, "wallpaperImage_1");
        verify(thumbImage !== null);
        verify(fallbackImage !== null);
        compare(thumbImage.source, "file:///tmp/cached-thumb.jpg");
        compare(fallbackImage.source, String(Qt.resolvedUrl("fixtures/wallpaper.png")));
        compare(thumbImage.sourceSize.width, 384);
        compare(thumbImage.sourceSize.height, 384);
    }

    function test_preloaderIsBoundedToFiveNearbyThumbs() {
        compare(findChild(carousel, "wallpaperPreload_0") !== null, true);
        compare(findChild(carousel, "wallpaperPreload_1"), null); // no cached thumb for current row
        compare(findChild(carousel, "wallpaperPreload_2") !== null, true);
        carousel.focusIndex = 0;
        compare(carousel.preloadRows.length, 2);
    }

    function test_emptyStateAndUnavailableActions() {
        system.theme = Object.assign({}, system.theme, {wallpapers: [], canSetBackground: false});
        verify(findChild(carousel, "appearanceEmptyWallpapers").visible);
        carousel.activate();
        compare(system.calls.length, 0);
    }
}
