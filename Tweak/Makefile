include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Relocate
Relocate_FILES = Tweak.xm RLCAnalogStickWindow.m hb/HBPreferences.m hb/HBPreferencesCore.m hb/HBPreferencesCore+Conveniences.m
Relocate_CFLAGS = -fobjc-arc -Ihb -Wno-deprecated-declarations -Wno-error
Relocate_FRAMEWORKS = CoreLocation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
