TARGET := iphone:clang:latest:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = YouTube5s

YouTube5s_FILES = $(wildcard *.m)
YouTube5s_FRAMEWORKS = UIKit AVFoundation AVKit CoreGraphics QuartzCore
YouTube5s_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk
