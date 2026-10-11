# Both the application and bridge tests consume the same generated Swift facade.
NATIVE_BUILD_DIR = $$clean_path($$OUT_PWD/../native)
NATIVE_LIBRARY = $$NATIVE_BUILD_DIR/libPillNative.dylib
NATIVE_HEADER = $$NATIVE_BUILD_DIR/PillNative-Swift.h
NATIVE_SOURCE = $$files($$PWD/*.swift)
NATIVE_SCRIPT = $$PWD/../../scripts/build-native.sh

INCLUDEPATH += $$NATIVE_BUILD_DIR
DEPENDPATH += $$NATIVE_BUILD_DIR
LIBS += -L$$NATIVE_BUILD_DIR -lPillNative
# Qt's macOS spec already adds @executable_path/../Frameworks for app bundles.
# Test executable lives outside an app bundle.
!app_bundle: QMAKE_LFLAGS += -Wl,-rpath,@executable_path/../native

native_backend.target = $$relative_path($$NATIVE_LIBRARY, $$OUT_PWD)
native_backend.depends = $$NATIVE_SOURCE $$NATIVE_SCRIPT
native_backend.commands = /bin/bash $$shell_quote($$NATIVE_SCRIPT) $$shell_quote($$NATIVE_BUILD_DIR) $$shell_quote($$QMAKE_MACOSX_DEPLOYMENT_TARGET) $$shell_quote($$QMAKE_APPLE_DEVICE_ARCHS)
# qmake misresolves includes of absent generated headers relative to .mm files.
# Bootstrap once during configuration; make handles subsequent source changes.
!exists($$NATIVE_HEADER)|!exists($$NATIVE_LIBRARY) {
    !system($$native_backend.commands): error("Cannot bootstrap the Swift facade")
}
native_header.target = $$relative_path($$NATIVE_HEADER, $$OUT_PWD)
native_header.depends = $$native_backend.target
native_header.commands = test -f $$shell_quote($$NATIVE_HEADER) || $$native_backend.commands
# PRE_TARGETDEPS covers linking, not parallel compilation.
native_adapter.target = nativebridge.o
native_adapter.depends = $$native_header.target
native_audio_adapter.target = audio.o
native_audio_adapter.depends = $$native_header.target
native_system_adapter.target = system.o
native_system_adapter.depends = $$native_header.target
QMAKE_EXTRA_TARGETS += native_backend native_header native_adapter native_audio_adapter native_system_adapter
PRE_TARGETDEPS += $$native_backend.target
