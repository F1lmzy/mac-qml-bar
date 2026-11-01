QT += testlib qml quick quickcontrols2
CONFIG += console c++17 testcase
CONFIG -= app_bundle
TARGET = launcher-test
SOURCES += tst_launcher.cpp
OBJECTIVE_SOURCES += ../src/services/launcher.mm
HEADERS += ../src/services/launcher.h
QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
include(../src/services/launcher.pri)
launcher_test_adapter.target = tst_launcher.o
launcher_test_adapter.depends = $$launcher_header.target
QMAKE_EXTRA_TARGETS += launcher_test_adapter
LIBS += -framework AppKit -framework Foundation
QMAKE_CXXFLAGS += -fobjc-arc
