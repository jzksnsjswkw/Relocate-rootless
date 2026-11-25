include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RelocatePrefs
$(BUNDLE_NAME)_FILES = Preferences.m SystemServices.m RLCChinaCoords.m RLCLocalize.m $(wildcard RLC*.m) \
                       hb/HBPreferences.m hb/HBPreferencesCore.m hb/HBPreferencesCore+Conveniences.m
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_FRAMEWORKS = UIKit MapKit QuartzCore
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc -Ihb -Wno-deprecated-declarations -Wno-error
$(BUNDLE_NAME)_EXTRA_FRAMEWORKS = AltList

# The prefs bundle links AltList.framework, which is installed by its own package
# rather than next to this one. Without an rpath the bundle fails to load with
# "Library not loaded: @rpath/AltList.framework/AltList".
#
# Each scheme puts the frameworks somewhere different: roothide under the
# randomized jbroot beside this dylib, rootless under /var/jb.
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
$(BUNDLE_NAME)_LDFLAGS += -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/.jbroot/usr/lib
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
$(BUNDLE_NAME)_LDFLAGS += -rpath /var/jb/Library/Frameworks -rpath /var/jb/usr/lib
endif

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
# The bundle needs an Info.plist that declares CFBundleLocalizations, otherwise
# the zh-Hans/zh-Hant .lproj tables are never consulted.
	$(ECHO_NOTHING)cp Resources/Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/$(BUNDLE_NAME).bundle/Info.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
