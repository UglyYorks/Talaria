.DEFAULT_GOAL := all
APP_NAME := Talaria
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
APP_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_LINK_EXECUTABLE := $(BUILD_DIR)/bin/$(APP_NAME)
APP_BUILD_STAMP := $(BUILD_DIR)/.$(APP_NAME).build.stamp
APP_ENTITLEMENTS := Entitlements.plist
# Keep this identity persistent so the credential helper can authenticate builds.
# Override with an Apple Development identity when one becomes available.
CODE_SIGN_IDENTITY ?= Talaria Local Development
SIGNING_CONFIG := $(BUILD_DIR)/.signing-identity
AGENT_RUNTIME_FILES := $(wildcard AgentRuntime/*.py) AgentRuntime/talaria-init
AGENT_LINUX_RUNTIME_DIR := $(BUILD_DIR)/agent-runtime/linux-arm64
AGENT_LINUX_RUNTIME_STAMP := $(AGENT_LINUX_RUNTIME_DIR)/.initrd.stamp
AGENT_LINUX_KERNEL_ZBOOT := $(AGENT_LINUX_RUNTIME_DIR)/vmlinuz-virt
AGENT_LINUX_KERNEL := $(AGENT_LINUX_RUNTIME_DIR)/Image
AGENT_LINUX_INITRD := $(AGENT_LINUX_RUNTIME_DIR)/initrd
AGENT_LINUX_BASE_INITRD := $(AGENT_LINUX_RUNTIME_DIR)/initramfs-base
AGENT_LINUX_MODLOOP := $(AGENT_LINUX_RUNTIME_DIR)/modloop-virt
AGENT_LINUX_APK_CACHE := $(AGENT_LINUX_RUNTIME_DIR)/apk-cache
ALPINE_RELEASE := v3.24
ALPINE_NETBOOT_URL := https://dl-cdn.alpinelinux.org/alpine/$(ALPINE_RELEASE)/releases/aarch64/netboot
ALPINE_KERNEL_SHA256 := 47970e0ee0478fe5c60824a89f162d5a353fa29466e5d3bddb0f9c506f1ed756
ALPINE_INITRD_SHA256 := e47d38bc88509a3db11affc09f9762f9643b026bd29441724a4729ad8e97add6
ALPINE_MODLOOP_SHA256 := f969d12c8e23b486c8df651f04a4a9767f32fee16aed385c23462c31ea6cb47b
APP_OBJC_SOURCES := $(wildcard Source/*.m) $(wildcard Source/design_system/*.m)
APP_OBJCXX_SOURCES := $(wildcard Source/*.mm)
APP_CXX_SOURCES := $(filter-out Source/ChromiumProcessHelper.cc,$(wildcard Source/*.cc))
APP_SOURCES := $(APP_OBJC_SOURCES) $(APP_OBJCXX_SOURCES) $(APP_CXX_SOURCES)
COMPILE_CONFIG := $(BUILD_DIR)/.compile-config
APP_OBJECT_DIR := $(BUILD_DIR)/app-objects
APP_OBJECTS := $(patsubst Source/%.m,$(APP_OBJECT_DIR)/%.m.o,$(APP_OBJC_SOURCES)) \
	$(patsubst Source/%.mm,$(APP_OBJECT_DIR)/%.mm.o,$(APP_OBJCXX_SOURCES)) \
	$(patsubst Source/%.cc,$(APP_OBJECT_DIR)/%.cc.o,$(APP_CXX_SOURCES))
TEST_EXECUTABLE := $(BUILD_DIR)/PromptBuilderTests
TAB_LAYOUT_TEST_EXECUTABLE := $(BUILD_DIR)/TabLayoutTests
NOTCH_VIEW_TEST_EXECUTABLE := $(BUILD_DIR)/NotchOverlayViewTests
GLASS_PANE_TEST_EXECUTABLE := $(BUILD_DIR)/GlassPaneTests
MARKDOWN_IT := Vendor/markdown-it/markdown-it.min.js
OVERLAY_PROBE := Source/BrowserOverlayProbe.js
DOCUMENT_FOOTER := Source/BrowserDocumentFooter.js Source/BrowserFooterColor.js
CODE_RESOURCES := Source/MarkdownFind.js Source/MarkdownCode.js Vendor/highlight.js/highlight.min.js Vendor/highlight.js/LICENSE
MATH_RESOURCES := Source/MarkdownMath.js $(shell find Vendor/katex -type f)
MARKDOWN_RESOURCES_STAMP := $(BUILD_DIR)/.markdown-resources.stamp
READABILITY_FILES := Vendor/readability/Readability.js Vendor/readability/LICENSE.md
SIDEBAR_PLANET := assets/sidebar-planet.png
APP_ICON := assets/Talaria.icns
INBOX_ICON_FILES := $(wildcard assets/inbox-icons/*.svg)
BOOKMARK_ICON_FILES := $(wildcard assets/browser-bookmarks/*.png)
HELPER_EXECUTABLE_NAME := $(APP_NAME)Helper
HELPER_EXECUTABLE := $(BUILD_DIR)/$(HELPER_EXECUTABLE_NAME)
HELPER_BUNDLES_DIR := $(BUILD_DIR)/helper-bundles
HELPER_BUILD_STAMP := $(BUILD_DIR)/.helper-bundles.build.stamp

CEF_DIST := cef_binary_151.3.24+g2384915+chromium-151.0.7922.174_macosarm64
CEF_ARCHIVE := $(CEF_DIST).tar.bz2
CEF_URL := https://cef-builds.spotifycdn.com/cef_binary_151.3.24%2Bg2384915%2Bchromium-151.0.7922.174_macosarm64.tar.bz2
CEF_SHA1 := 0132e8440567c9d1dd8c6dd478c554349ad0bc86
CEF_DEPS_DIR := $(BUILD_DIR)/deps
CEF_ROOT := $(CEF_DEPS_DIR)/$(CEF_DIST)
CEF_ARCHIVE_PATH := $(CEF_DEPS_DIR)/$(CEF_ARCHIVE)
CEF_EXTRACT_STAMP := $(CEF_ROOT)/.extract.stamp
CEF_RELEASE_DIR := $(CEF_ROOT)/Release
CEF_WRAPPER_OBJ_DIR := $(BUILD_DIR)/cef-wrapper-objects
CEF_WRAPPER_LIB := $(BUILD_DIR)/libcef_dll_wrapper.a
CEF_FRAMEWORK_DEST := $(APP_BUNDLE)/Contents/Frameworks/Chromium Embedded Framework.framework

OBJCFLAGS := -fobjc-arc -fmodules -fmodules-cache-path=$(abspath $(BUILD_DIR)/module-cache) -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0
CEF_DEFINES := -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -DCEF_USE_SANDBOX
CEF_INCLUDE_FLAGS := -I$(CEF_ROOT)
CEF_CXXFLAGS := $(CEF_DEFINES) $(CEF_INCLUDE_FLAGS) -fno-strict-aliasing -fstack-protector -funwind-tables -fvisibility=hidden -Wall -Wextra -Wno-missing-field-initializers -Wno-unused-parameter -fno-exceptions -fno-rtti -fno-threadsafe-statics -fobjc-call-cxx-cdtors -fvisibility-inlines-hidden -std=c++20 -Wno-narrowing -Wsign-compare -Wno-undefined-var-template -O3 -mmacosx-version-min=13.0
APP_OBJCXXFLAGS := $(OBJCFLAGS) $(CEF_DEFINES) $(CEF_INCLUDE_FLAGS) -fno-exceptions -fno-rtti -fno-threadsafe-statics -fobjc-call-cxx-cdtors -fvisibility-inlines-hidden -std=c++20 -Wno-sign-compare -Wno-nullability-completeness -Wno-missing-field-initializers
APP_FRAMEWORKS := -framework Vision -framework CoreImage -framework Quartz -framework ServiceManagement -framework Carbon -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -framework AppKit -framework Foundation -framework QuartzCore -framework ScreenCaptureKit -framework SceneKit -framework CoreText -framework Cocoa -framework IOSurface -framework WebKit -framework Virtualization -framework Security -lsqlite3 -lpthread
TEST_FRAMEWORKS := -framework Foundation -framework AppKit -framework Virtualization -framework Security -lsqlite3

.PHONY: all build test audit-theme-colors clean run widgetbook close-running-app check-signing-identity FORCE

all: build

# Explicit installation only: ordinary builds never replace/re-sign the installed
# helper, whose stable code hash preserves its Keychain partition approval.
.PHONY: credential-helper install-credential-helper
CREDENTIAL_HELPER_BUNDLE := $(BUILD_DIR)/Talaria Credentials.app
credential-helper: $(BUILD_DIR)/.credential-helper.stamp

$(BUILD_DIR)/.credential-helper.stamp: CredentialHelper/main.m CredentialHelper/Info.plist Source/TLCredentialStore.m Source/TLCredentialStore.h Source/TLCredentialHelperProtocol.h $(SIGNING_CONFIG)
	mkdir -p "$(CREDENTIAL_HELPER_BUNDLE)/Contents/MacOS"
	xcrun clang $(OBJCFLAGS) -DTL_CREDENTIAL_HELPER_BUILD -ISource CredentialHelper/main.m Source/TLCredentialStore.m -framework Foundation -framework Security -o "$(CREDENTIAL_HELPER_BUNDLE)/Contents/MacOS/TalariaCredentials"
	cp CredentialHelper/Info.plist "$(CREDENTIAL_HELPER_BUNDLE)/Contents/Info.plist"
	codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$(CREDENTIAL_HELPER_BUNDLE)"
	touch "$@"

install-credential-helper: credential-helper
	python3 CredentialHelper/install.py "$(CREDENTIAL_HELPER_BUNDLE)"

# Optional integration check against the installed helper. Never reads secrets.
.PHONY: test-credential-helper
test-credential-helper: check-signing-identity
	xcrun clang $(OBJCFLAGS) -ISource Tests/CredentialHelperProbe.m -framework Foundation -framework Security -o "$(BUILD_DIR)/CredentialHelperProbe"
	cp "$(BUILD_DIR)/CredentialHelperProbe" "$(BUILD_DIR)/CredentialHelperUntrustedProbe"
	codesign --force --options runtime --identifier com.talaria.chat --sign "$(CODE_SIGN_IDENTITY)" "$(BUILD_DIR)/CredentialHelperProbe"
	codesign --force --options runtime --identifier com.talaria.untrusted-probe --sign "$(CODE_SIGN_IDENTITY)" "$(BUILD_DIR)/CredentialHelperUntrustedProbe"
	"$(BUILD_DIR)/CredentialHelperProbe" allow
	"$(BUILD_DIR)/CredentialHelperUntrustedProbe" deny
	"$(BUILD_DIR)/CredentialHelperProbe" allow

build: $(APP_BUILD_STAMP)

check-signing-identity:
	@if [ "$(CODE_SIGN_IDENTITY)" = "-" ] || [ -z "$(CODE_SIGN_IDENTITY)" ] || \
	  ! security find-identity -v -p codesigning | grep -F -- '$(CODE_SIGN_IDENTITY)' >/dev/null; then \
	  echo 'Missing persistent signing identity: $(CODE_SIGN_IDENTITY)' >&2; \
	  echo 'Install the local development certificate or set CODE_SIGN_IDENTITY to an installed signing identity.' >&2; \
	  exit 1; \
	fi

$(SIGNING_CONFIG): FORCE | check-signing-identity
	@mkdir -p "$(BUILD_DIR)"
	@printf '%s\n' '$(CODE_SIGN_IDENTITY)' > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi

$(APP_LINK_EXECUTABLE): $(APP_OBJECTS) $(CEF_WRAPPER_LIB) $(COMPILE_CONFIG)
	mkdir -p "$(dir $@)"
	xcrun clang++ $(APP_OBJECTS) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$@"

$(APP_BUILD_STAMP): $(APP_LINK_EXECUTABLE) $(OVERLAY_PROBE) $(DOCUMENT_FOOTER) Makefile $(SIGNING_CONFIG) $(APP_OBJECTS) Info.plist ChromiumHelper-Info.plist $(APP_ENTITLEMENTS) $(AGENT_RUNTIME_FILES) $(AGENT_LINUX_RUNTIME_STAMP) $(SIDEBAR_PLANET) $(APP_ICON) $(INBOX_ICON_FILES) $(BOOKMARK_ICON_FILES) $(MARKDOWN_IT) $(MATH_RESOURCES) $(CODE_RESOURCES) $(READABILITY_FILES) $(CEF_WRAPPER_LIB) $(HELPER_BUILD_STAMP)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources" "$(APP_BUNDLE)/Contents/Frameworks"
	cp "$(APP_LINK_EXECUTABLE)" "$(APP_EXECUTABLE)"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(OVERLAY_PROBE)" "$(APP_BUNDLE)/Contents/Resources/BrowserOverlayProbe.js"
	cp $(DOCUMENT_FOOTER) "$(APP_BUNDLE)/Contents/Resources/"
	cp "$(SIDEBAR_PLANET)" "$(APP_BUNDLE)/Contents/Resources/sidebar-planet.png"
	cp "$(APP_ICON)" "$(APP_BUNDLE)/Contents/Resources/Talaria.icns"
	ditto "assets/inbox-icons" "$(APP_BUNDLE)/Contents/Resources/inbox-icons"
	ditto "assets/browser-bookmarks" "$(APP_BUNDLE)/Contents/Resources/browser-bookmarks"
	cp "$(MARKDOWN_IT)" "$(APP_BUNDLE)/Contents/Resources/markdown-it.min.js"
	cp Source/MarkdownMath.js "$(APP_BUNDLE)/Contents/Resources/MarkdownMath.js"
	cp Source/MarkdownFind.js Source/MarkdownCode.js Vendor/highlight.js/highlight.min.js "$(APP_BUNDLE)/Contents/Resources/"
	cp Vendor/highlight.js/LICENSE "$(APP_BUNDLE)/Contents/Resources/highlight-LICENSE"
	cp Vendor/browser-import/leveldb-1.23/LICENSE "$(APP_BUNDLE)/Contents/Resources/leveldb-LICENSE"
	cp Vendor/browser-import/snappy-1.1.9/COPYING "$(APP_BUNDLE)/Contents/Resources/snappy-LICENSE"
	ditto Vendor/katex "$(APP_BUNDLE)/Contents/Resources/katex"
	cp Vendor/readability/Readability.js "$(APP_BUNDLE)/Contents/Resources/Readability.js"
	cp Vendor/readability/LICENSE.md "$(APP_BUNDLE)/Contents/Resources/Readability-LICENSE.md"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources/AgentRuntime/linux-arm64"
	cp "$(AGENT_LINUX_KERNEL)" "$(APP_BUNDLE)/Contents/Resources/AgentRuntime/linux-arm64/Image"
	cp "$(AGENT_LINUX_INITRD)" "$(APP_BUNDLE)/Contents/Resources/AgentRuntime/linux-arm64/initrd"
	mkdir -p "$(CEF_FRAMEWORK_DEST)/Versions"
	ditto "$(CEF_RELEASE_DIR)/Chromium Embedded Framework.framework" "$(CEF_FRAMEWORK_DEST)/Versions/A"
	cd "$(CEF_FRAMEWORK_DEST)" && ln -sf "Versions/A/Chromium Embedded Framework" "Chromium Embedded Framework"
	cd "$(CEF_FRAMEWORK_DEST)" && ln -sf "Versions/A/Libraries" "Libraries"
	cd "$(CEF_FRAMEWORK_DEST)" && ln -sf "Versions/A/Resources" "Resources"
	cd "$(CEF_FRAMEWORK_DEST)/Versions" && ln -sf "A" "Current"
	ditto "$(HELPER_BUNDLES_DIR)" "$(APP_BUNDLE)/Contents/Frameworks"
	@set -e; \
	for library in "$(CEF_FRAMEWORK_DEST)/Versions/A/Libraries/"*.dylib; do \
	  codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$$library"; \
	done; \
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(CEF_FRAMEWORK_DEST)"; \
	find "$(APP_BUNDLE)/Contents/Frameworks" -maxdepth 1 -name "$(APP_NAME) Helper*.app" -type d -print0 | \
	  xargs -0 -n 1 codesign --force --sign "$(CODE_SIGN_IDENTITY)"; \
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(APP_BUNDLE)"
	touch "$(APP_BUILD_STAMP)"

$(APP_OBJECT_DIR)/%.m.o: Source/%.m $(COMPILE_CONFIG)
	mkdir -p "$(dir $@)"
	xcrun clang $(OBJCFLAGS) -ISource -MMD -MP -MF "$@.d" -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.mm.o: Source/%.mm $(COMPILE_CONFIG) | $(CEF_EXTRACT_STAMP)
	mkdir -p "$(dir $@)"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource -MMD -MP -MF "$@.d" -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.cc.o: Source/%.cc $(COMPILE_CONFIG) | $(CEF_EXTRACT_STAMP)
	mkdir -p "$(dir $@)"
	xcrun clang++ $(CEF_CXXFLAGS) -ISource -MMD -MP -MF "$@.d" -c "$<" -o "$@"

$(HELPER_BUILD_STAMP): $(COMPILE_CONFIG) Source/ChromiumProcessHelper.cc ChromiumHelper-Info.plist $(CEF_WRAPPER_LIB)
	rm -rf "$(HELPER_BUNDLES_DIR)"
	mkdir -p "$(BUILD_DIR)" "$(HELPER_BUNDLES_DIR)"
	xcrun clang++ $(CEF_CXXFLAGS) -MMD -MP -MF "$(BUILD_DIR)/.helper.d" -MT "$(HELPER_BUILD_STAMP)" Source/ChromiumProcessHelper.cc "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(HELPER_EXECUTABLE)"
	@set -e; \
	printf '%s\n' '|' ' (Alerts)|.alerts' ' (GPU)|.gpu' ' (Plugin)|.plugin' ' (Renderer)|.renderer' | \
	while IFS='|' read -r name_suffix bundle_suffix; do \
	  helper_name="$(APP_NAME) Helper$${name_suffix}"; \
	  helper_bundle="$(HELPER_BUNDLES_DIR)/$${helper_name}.app"; \
	  mkdir -p "$${helper_bundle}/Contents/MacOS"; \
	  cp "$(HELPER_EXECUTABLE)" "$${helper_bundle}/Contents/MacOS/$${helper_name}"; \
	  sed \
	    -e "s|@@EXECUTABLE_NAME@@|$${helper_name}|g" \
	    -e "s|@@PRODUCT_NAME@@|$${helper_name}|g" \
	    -e "s|@@BUNDLE_ID_SUFFIX@@|$${bundle_suffix}|g" \
	    ChromiumHelper-Info.plist > "$${helper_bundle}/Contents/Info.plist"; \
	  printf "APPL????" > "$${helper_bundle}/Contents/PkgInfo"; \
	done
	touch "$(HELPER_BUILD_STAMP)"

CEF_COMPILE_CONFIG := $(BUILD_DIR)/.cef-compile-config
$(CEF_COMPILE_CONFIG): FORCE
	@mkdir -p "$(BUILD_DIR)"
	@printf '%s\n' '$(CEF_CXXFLAGS)' > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi

CEF_WRAPPER_INPUTS := $(if $(wildcard $(CEF_ROOT)/libcef_dll),$(shell find "$(CEF_ROOT)/libcef_dll" "$(CEF_ROOT)/include" -type f))
$(CEF_WRAPPER_LIB): $(CEF_EXTRACT_STAMP) $(CEF_COMPILE_CONFIG) Scripts/cef-wrapper.mk $(CEF_WRAPPER_INPUTS)
	$(MAKE) -f Scripts/cef-wrapper.mk CEF_ROOT="$(CEF_ROOT)" CEF_WRAPPER_OBJ_DIR="$(CEF_WRAPPER_OBJ_DIR)" CEF_WRAPPER_LIB="$(CEF_WRAPPER_LIB)" CEF_CXXFLAGS='$(CEF_CXXFLAGS)' CEF_COMPILE_CONFIG="$(CEF_COMPILE_CONFIG)"

$(CEF_EXTRACT_STAMP): $(CEF_ARCHIVE_PATH)
	tar -xjf "$(CEF_ARCHIVE_PATH)" -C "$(CEF_DEPS_DIR)"
	touch "$(CEF_EXTRACT_STAMP)"

$(CEF_ARCHIVE_PATH):
	mkdir -p "$(CEF_DEPS_DIR)"
	curl -fL -o "$(CEF_ARCHIVE_PATH)" "$(CEF_URL)"
	@actual=$$(shasum -a 1 "$(CEF_ARCHIVE_PATH)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(CEF_SHA1)" ]; then \
	  rm -f "$(CEF_ARCHIVE_PATH)"; \
	  echo "CEF checksum mismatch: $$actual"; \
	  exit 1; \
	fi

# Immutable downloads and the generated guest image have separate dependencies.
define alpine_download
$(1):
	mkdir -p "$(AGENT_LINUX_RUNTIME_DIR)"
	curl -fL -o "$$@.tmp" "$(ALPINE_NETBOOT_URL)/$(2)"
	@actual=$$$$(shasum -a 256 "$$@.tmp" | awk '{print $$$$1}'); test "$$$$actual" = "$(3)" || { rm -f "$$@.tmp"; echo "Alpine checksum mismatch"; exit 1; }
	mv "$$@.tmp" "$$@"
endef
$(eval $(call alpine_download,$(AGENT_LINUX_KERNEL_ZBOOT),vmlinuz-virt,$(ALPINE_KERNEL_SHA256)))
$(eval $(call alpine_download,$(AGENT_LINUX_BASE_INITRD),initramfs-virt,$(ALPINE_INITRD_SHA256)))
$(eval $(call alpine_download,$(AGENT_LINUX_MODLOOP),modloop-virt,$(ALPINE_MODLOOP_SHA256)))

$(AGENT_LINUX_RUNTIME_STAMP): Scripts/build-agent-initrd.py $(AGENT_RUNTIME_FILES) $(AGENT_LINUX_KERNEL_ZBOOT) $(AGENT_LINUX_BASE_INITRD) $(AGENT_LINUX_MODLOOP)
	python3 Scripts/build-agent-initrd.py \
	  --alpine-release "$(ALPINE_RELEASE)" \
	  --zboot-kernel "$(AGENT_LINUX_KERNEL_ZBOOT)" \
	  --kernel-output "$(AGENT_LINUX_KERNEL)" \
	  --base-initrd "$(AGENT_LINUX_BASE_INITRD)" \
	  --modloop "$(AGENT_LINUX_MODLOOP)" \
	  --agent-script AgentRuntime/talaria_agent.py \
	  --terminal-script AgentRuntime/terminal_service.py \
	  --init-script AgentRuntime/talaria-init \
	  --cache-dir "$(AGENT_LINUX_APK_CACHE)" \
	  --output "$(AGENT_LINUX_INITRD)"
	test -s "$(AGENT_LINUX_KERNEL)"
	test -s "$(AGENT_LINUX_INITRD)"
	touch "$(AGENT_LINUX_RUNTIME_STAMP)"

include Scripts/tests.mk

test-automations: $(BUILD_DIR)/AutomationsTests
	"$(BUILD_DIR)/AutomationsTests"


# Explicit native integration check; uses existing Screen Recording access only.
.PHONY: test-screen-capture
test-screen-capture: $(BUILD_DIR)/ScreenCaptureTests check-signing-identity
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --identifier com.talaria.chat "$<"
	"$<"




$(MARKDOWN_RESOURCES_STAMP): $(MARKDOWN_IT) $(MATH_RESOURCES) $(CODE_RESOURCES)
	mkdir -p "$(BUILD_DIR)"
	cp "$(MARKDOWN_IT)" "$(BUILD_DIR)/markdown-it.min.js"
	cp Source/MarkdownMath.js "$(BUILD_DIR)/MarkdownMath.js"
	cp Source/MarkdownFind.js Source/MarkdownCode.js Vendor/highlight.js/highlight.min.js "$(BUILD_DIR)/"
	ditto Vendor/katex "$(BUILD_DIR)/katex"
	touch "$@"






audit-theme-colors:
	python3 Scripts/audit-theme-colors.py


close-running-app:
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.2

run: build close-running-app
	open -n "$(CURDIR)/$(APP_BUNDLE)"

widgetbook: build close-running-app
	open -n "$(CURDIR)/$(APP_BUNDLE)" --args --widgetbook

clean:
	python3 -c 'import shutil; shutil.rmtree("$(BUILD_DIR)", ignore_errors=True)'










.PHONY: test-hermes-gateway
test-hermes-gateway:
	python3 -B -m unittest discover -s Tests -p "test_*.py"


$(BUILD_DIR)/TerminalClientProbe: Source/TLTerminalClient.m Tests/TerminalClientProbe.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

# Split state, native pane geometry and real chat workspace integration.

# Uses installed Chromium with a temporary profile; requires Node 22+.
# CHROME_BIN can override the Chrome/Chromium executable path.
.PHONY: test-browser-overlay
test-browser-overlay:
	node Tests/BrowserDocumentFooterTests.mjs
	node Tests/BrowserOverlayTests.mjs

# Explicit integration test: signed desktop bundle, local HTTP fixtures, disposable profile.
.PHONY: test-browser-preferences
test-browser-preferences: build
	mkdir -p "$(BUILD_DIR)/BrowserPreferencesProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserPreferencesProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserPreferencesProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserPreferencesIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserPreferencesProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserPreferencesProbe.app"
	python3 Scripts/test-browser-preferences.py

.PHONY: test-browser-navigation
test-browser-navigation: build
	mkdir -p "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserNavigationProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserNavigationIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserNavigationProbe.app"
	python3 Scripts/test-browser-navigation.py

# Native conversation attachment viewer, including transcript integration.



.PHONY: test-browser-images
test-browser-images: build
	mkdir -p "$(BUILD_DIR)/BrowserImageProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserImageProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserImageProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserImageIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserImageProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserImageProbe.app"
	python3 Scripts/test-browser-images.py

.PHONY: test-browser-links
test-browser-links: build
	mkdir -p "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserLinkProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserLinkIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserLinkProbe.app"
	python3 Scripts/test-browser-links.py

# Shared WebKit/Chromium link-menu parity and native context routing.


test-browser-find: $(BUILD_DIR)/BrowserFindTests
	"$(BUILD_DIR)/BrowserFindTests"


.PHONY: test-browser-find test-browser-find-cef
test-browser-find-cef: build
	mkdir -p "$(BUILD_DIR)/BrowserFindProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserFindProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserFindProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserFindCEFTests.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserFindProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserFindProbe.app"
	python3 Scripts/test-browser-find.py


# Native transcript search plus real WebKit rendering, without network or an AI runtime.

# Browsing history migration, persistence and native navigation callback routing.


include Scripts/browser-import.mk

# Empty chat sky rendering, responsive tips and loading/message transitions.

# Compare effective flags so command-line overrides invalidate the right artifacts.
$(COMPILE_CONFIG): FORCE
	@mkdir -p "$(@D)"
	@printf '%s\n' '$(OBJCFLAGS)' '$(APP_OBJCXXFLAGS)' '$(CEF_CXXFLAGS)' '$(APP_FRAMEWORKS)' '$(TEST_FRAMEWORKS)' > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi

-include $(APP_OBJECTS:=.d) $(BUILD_DIR)/.helper.d

.PHONY: test-agent-protocol
test-agent-protocol: $(BUILD_DIR)/AgentProtocolTests
	"$(BUILD_DIR)/AgentProtocolTests"
