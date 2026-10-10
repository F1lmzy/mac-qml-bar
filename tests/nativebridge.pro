QT += testlib qml
CONFIG += console c++17 testcase
CONFIG -= app_bundle
TARGET = nativebridge-test
OBJECTIVE_SOURCES += tst_nativebridge.mm ../src/services/nativebridge.mm
HEADERS += ../src/services/nativebridge.h
QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
include(../src/native/native.pri)
native_test.target = tst_nativebridge.o
native_test.depends = $$native_header.target
QMAKE_EXTRA_TARGETS += native_test
LIBS += -framework Foundation
QMAKE_CXXFLAGS += -fobjc-arc
