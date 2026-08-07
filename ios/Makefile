INSTALL_TARGET_PROCESSES = SpringBoard

export TARGET = iphone:clang:11.4:9.0
export ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OmniRCM

OmniRCM_FILES = \
	src/main.m \
	src/AppDelegate.m \
	src/MainViewController.m \
	src/RCMInjector.m \
	src/RCMDeviceWatcher.m \
	src/PayloadManager.m

OmniRCM_FRAMEWORKS = \
	UIKit \
	Foundation

OmniRCM_PRIVATE_FRAMEWORKS = IOKit

OmniRCM_CFLAGS = \
	-fobjc-arc \
	-fno-modules \
	-include IOKit/IOKitLib.h \
	-include IOKit/IOCFPlugIn.h \
	-include IOKit/usb/IOUSBLib.h \
	-include IOKit/IOMessage.h \
	-Wno-documentation \
	-Wno-deprecated-declarations \
	-Wno-nullability-completeness \
	-Wno-objc-missing-super-calls \
	-Wno-unused-variable \
	-Wno-error=undef-prefix \
	-I$(THEOS_OBJ_DIR) \
	-Isrc

OmniRCM_LDFLAGS = -lz

ADDITIONAL_CFLAGS = -F$(THEOS)/vendor/frameworks

OmniRCM_CODESIGN_FLAGS = -SOmniRCM.entitlements
OmniRCM_INSTALL_PATH = /Applications

OmniRCM_INFOPLIST_FILE = Resources/Info.plist

OmniRCM_RESOURCE_FILES = \
	Resources/intermezzo.bin \
	Resources/AppIcon.png

include $(THEOS)/makefiles/application.mk

ipa: package
	$(eval APP := $(shell find .theos/obj -name "OmniRCM.app" -not -path "*/stage/*" -type d | head -1))
	mkdir -p /tmp/OmniRCM-ipa/Payload
	cp -r $(APP) /tmp/OmniRCM-ipa/Payload/
	rm -rf /tmp/OmniRCM-ipa/Payload/OmniRCM.app/OmniRCM.dSYM
	cp Resources/Info.plist /tmp/OmniRCM-ipa/Payload/OmniRCM.app/
	cp Resources/intermezzo.bin /tmp/OmniRCM-ipa/Payload/OmniRCM.app/
	cp Resources/AppIcon.png /tmp/OmniRCM-ipa/Payload/OmniRCM.app/
	cd /tmp/OmniRCM-ipa && zip -r $(CURDIR)/packages/OmniRCM.ipa Payload/
	rm -rf /tmp/OmniRCM-ipa
	@echo "✓ IPA built: packages/OmniRCM.ipa"
