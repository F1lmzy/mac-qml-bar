QT += testlib qml
CONFIG += console c++17 testcase
CONFIG -= app_bundle
TARGET = system-bridge-test
OBJECTIVE_SOURCES += tst_system.mm ../src/services/system.mm
HEADERS += ../src/services/system.h
QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
include(../src/native/native.pri)
native_system_test.target = tst_system.o
native_system_test.depends = $$native_header.target
QMAKE_EXTRA_TARGETS += native_system_test
LIBS += -framework Foundation
QMAKE_CXXFLAGS += -fobjc-arc
