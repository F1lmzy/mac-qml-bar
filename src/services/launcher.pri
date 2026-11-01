# Build the GPUI-free maccer provider library for the same architecture as Qt.
MACCER_SOURCE = $$(MACCER_SOURCE)
isEmpty(MACCER_SOURCE): MACCER_SOURCE = $$(HOME)/Documents/maccer
MACCER_SOURCE = $$clean_path($$MACCER_SOURCE)
LAUNCHER_BUILD_DIR = $$clean_path($$OUT_PWD/../launcher)
LAUNCHER_LIBRARY = $$LAUNCHER_BUILD_DIR/liblauncher_agent.dylib
LAUNCHER_HEADER = $$LAUNCHER_BUILD_DIR/include/maccer_agent.h
LAUNCHER_SCRIPT = $$PWD/../../scripts/build-launcher.sh
MACCER_DEPS = $$MACCER_SOURCE/Cargo.toml $$MACCER_SOURCE/Cargo.lock
MACCER_DEPS += $$system(/usr/bin/find $$shell_quote($$MACCER_SOURCE/crates) -type f -name '*.rs' -print)
MACCER_DEPS += $$system(/usr/bin/find $$shell_quote($$MACCER_SOURCE/crates) -type f -name Cargo.toml -print)
MACCER_DEPS += $$system(/usr/bin/find $$shell_quote($$MACCER_SOURCE/config) -type f -name '*.toml' -print)
MACCER_DEPS += $$MACCER_SOURCE/crates/launcher-agent/include/maccer_agent.h

INCLUDEPATH += $$LAUNCHER_BUILD_DIR/include
DEPENDPATH += $$LAUNCHER_BUILD_DIR/include
LIBS += -L$$LAUNCHER_BUILD_DIR -llauncher_agent
!app_bundle: QMAKE_LFLAGS += -Wl,-rpath,@executable_path/../launcher

launcher_backend.target = $$relative_path($$LAUNCHER_LIBRARY, $$OUT_PWD)
launcher_backend.depends = $$MACCER_DEPS $$LAUNCHER_SCRIPT
launcher_backend.commands = /bin/bash $$shell_quote($$LAUNCHER_SCRIPT) $$shell_quote($$MACCER_SOURCE) $$shell_quote($$LAUNCHER_BUILD_DIR) $$shell_quote($$QMAKE_MACOSX_DEPLOYMENT_TARGET) $$shell_quote($$QMAKE_APPLE_DEVICE_ARCHS)
!exists($$LAUNCHER_HEADER)|!exists($$LAUNCHER_LIBRARY) {
    !system($$launcher_backend.commands): error("Cannot build maccer launcher service. Check MACCER_SOURCE and Cargo dependencies.")
}
launcher_header.target = $$relative_path($$LAUNCHER_HEADER, $$OUT_PWD)
launcher_header.depends = $$launcher_backend.target
launcher_header.commands = test -f $$shell_quote($$LAUNCHER_HEADER) || $$launcher_backend.commands
launcher_adapter.target = launcher.o
launcher_adapter.depends = $$launcher_header.target
launcher_entry_adapter.target = main.o
launcher_entry_adapter.depends = $$launcher_header.target
QMAKE_EXTRA_TARGETS += launcher_backend launcher_header launcher_adapter launcher_entry_adapter
PRE_TARGETDEPS += $$launcher_backend.target
