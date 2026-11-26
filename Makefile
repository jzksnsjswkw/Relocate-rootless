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

# The control file's `Package:` carries the same suffix the index gives it.
#
# roothide and rootless are two builds of one tweak, and a client keys on the
# package name: without a suffix a source would show one row for two packages and
# install whichever it happened to see. `make_repo.sh` reads the name as-is, so
# the deb has to agree or an upgrade from the other scheme installs a second copy
# instead of replacing the first.
THEOS_PACKAGE_NAME := com.jzksnsjswkw.relocate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	RELOCATE_PACKAGE_NAME = $(THEOS_PACKAGE_NAME)-roothide
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	RELOCATE_PACKAGE_NAME = $(THEOS_PACKAGE_NAME)-rootless
endif

# The patch has to happen before `deb.mk` reads the control — it derives
# `THEOS_PACKAGE_NAME` from it at parse time and generates the staged control
# from it later, so editing either afterwards is too late. A per-scheme copy is
# written here and handed to `deb.mk` as its source control file.
RELOCATE_CONTROL := $(THEOS_PROJECT_DIR)/.theos/control.$(THEOS_PACKAGE_SCHEME)
$(shell mkdir -p $(THEOS_PROJECT_DIR)/.theos && \
        /usr/bin/sed 's|^Package: .*|Package: $(RELOCATE_PACKAGE_NAME)|' \
            $(THEOS_PROJECT_DIR)/control > $(RELOCATE_CONTROL))
_THEOS_DEB_PACKAGE_CONTROL_PATH := $(RELOCATE_CONTROL)

include $(THEOS)/makefiles/common.mk

# Repeated after the include.
#
# `THEOS_PROJECT_DIR` is defined by common.mk, so the block above runs with it
# empty and writes to `/.theos/` instead — where mkdir fails and the control file
# is never produced, leaving `deb.mk` to read the unpatched one. Doing it again
# here, once the variable exists, is what actually takes effect.
RELOCATE_CONTROL := $(THEOS_PROJECT_DIR)/.theos/control.$(THEOS_PACKAGE_SCHEME)
$(shell mkdir -p $(THEOS_PROJECT_DIR)/.theos && \
        /usr/bin/sed 's|^Package: .*|Package: $(RELOCATE_PACKAGE_NAME)|' \
            $(THEOS_PROJECT_DIR)/control > $(RELOCATE_CONTROL))
_THEOS_DEB_PACKAGE_CONTROL_PATH := $(RELOCATE_CONTROL)

# The deb's filename, not just its control.
#
# `deb.mk` sets THEOS_PACKAGE_NAME from the control file with `:=`, which expands
# at include time — before the per-scheme control above exists, so it read the
# unpatched one and named the file `com.jzksnsjswkw.relocate_...` while the
# package inside was `-roothide`. The control and the filename disagreeing is
# confusing to read and worse to download by hand.
#
# Reassigned here, after include, so the filename carries the same name the
# package declares. `_THEOS_DEB_PACKAGE_FILENAME` is a recursively expanded
# variable, so it picks this up when the packaging rule runs.
THEOS_PACKAGE_NAME := $(RELOCATE_PACKAGE_NAME)

SUBPROJECTS += Tweak
SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
