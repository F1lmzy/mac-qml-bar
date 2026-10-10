QT += quick qml quickcontrols2
CONFIG += c++17
TARGET = PillSpike
SOURCES += src/main.cpp
OBJECTIVE_SOURCES += src/host.mm src/services/nativebridge.mm
HEADERS += src/host.h src/geometry.h src/services/nativebridge.h
RESOURCES += qml.qrc
QMAKE_CXXFLAGS += -fobjc-arc
QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
LIBS += -framework AppKit
QMAKE_INFO_PLIST = Info.plist
include(src/native/native.pri)
# Copy only our Swift library, using Qt's existing bundle Frameworks rpath.
native_bundle.files = $$NATIVE_LIBRARY
native_bundle.path = Contents/Frameworks
QMAKE_BUNDLE_DATA += native_bundle
