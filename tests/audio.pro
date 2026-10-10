QT += testlib qml
CONFIG += console c++17 testcase
CONFIG -= app_bundle
TARGET = audio-bridge-test
OBJECTIVE_SOURCES += tst_audio.mm ../src/services/audio.mm
HEADERS += ../src/services/audio.h
QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
include(../src/native/native.pri)
native_audio_test.target = tst_audio.o
native_audio_test.depends = $$native_header.target
QMAKE_EXTRA_TARGETS += native_audio_test
LIBS += -framework Foundation
QMAKE_CXXFLAGS += -fobjc-arc
