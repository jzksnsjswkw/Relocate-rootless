THEOS_DEVICE_IP=192.168.0.219
THEOS_DEVICE_PORT=22

FINALPACKAGE = 1

# The package scheme must be named. It picks the install layout, and guessing was
# never safe: a build without one targets the classic rootful paths, which no
# supported device uses, and it fails in a way that looks like a code error rather
# than a missing argument.
#
#   make package THEOS_PACKAGE_SCHEME=roothide    # roothide (TrollStore setups)
#   make package THEOS_PACKAGE_SCHEME=rootless    # Dopamine and other rootless
#
# Both use the 16.5 SDK. The deployment target stays at iOS 15: neither layout
# exists before it.
#
# One architecture per scheme, because each is only ever installed on one kind of
# device — roothide is arm64e, rootless is arm64. Theos builds both by default, so
# leaving it alone compiles every source file twice and throws half away at
# packaging time.
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	TARGET = iphone:clang:16.5:15.0
	ARCHS = arm64
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	TARGET = iphone:clang:16.5:15.0
	ARCHS = arm64e
else
$(error THEOS_PACKAGE_SCHEME must be set: use THEOS_PACKAGE_SCHEME=roothide (or =rootless). A rootful build is not supported — no supported device uses that layout)
endif

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak
SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
