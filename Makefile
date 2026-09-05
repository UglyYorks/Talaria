APP_NAME := Talaria
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
APP_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_BUILD_STAMP := $(BUILD_DIR)/.$(APP_NAME).build.stamp
APP_ENTITLEMENTS := Entitlements.plist
# Keep this identity persistent so the credential helper can authenticate builds.
# Override with an Apple Development identity when one becomes available.
CODE_SIGN_IDENTITY ?= Talaria Local Development
SIGNING_CONFIG := $(BUILD_DIR)/.signing-identity
AGENT_RUNTIME_FILES := $(wildcard AgentRuntime/*.py) AgentRuntime/talaria-init
AGENT_LINUX_RUNTIME_DIR := $(BUILD_DIR)/agent-runtime/linux-arm64
AGENT_LINUX_RUNTIME_STAMP := $(AGENT_LINUX_RUNTIME_DIR)/.download.stamp
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
APP_HEADERS := $(wildcard Source/*.h) $(wildcard Source/design_system/*.h)
APP_OBJC_SOURCES := $(wildcard Source/*.m) $(wildcard Source/design_system/*.m)
APP_OBJCXX_SOURCES := $(wildcard Source/*.mm)
APP_CXX_SOURCES := $(filter-out Source/ChromiumProcessHelper.cc,$(wildcard Source/*.cc))
APP_SOURCES := $(APP_OBJC_SOURCES) $(APP_OBJCXX_SOURCES) $(APP_CXX_SOURCES)
APP_OBJECT_DIR := $(BUILD_DIR)/app-objects
APP_OBJECTS := $(patsubst Source/%.m,$(APP_OBJECT_DIR)/%.m.o,$(APP_OBJC_SOURCES)) \
	$(patsubst Source/%.mm,$(APP_OBJECT_DIR)/%.mm.o,$(APP_OBJCXX_SOURCES)) \
	$(patsubst Source/%.cc,$(APP_OBJECT_DIR)/%.cc.o,$(APP_CXX_SOURCES))
TEST_EXECUTABLE := $(BUILD_DIR)/PromptBuilderTests
TAB_LAYOUT_TEST_EXECUTABLE := $(BUILD_DIR)/TabLayoutTests
NOTCH_VIEW_TEST_EXECUTABLE := $(BUILD_DIR)/NotchOverlayViewTests
GLASS_PANE_TEST_EXECUTABLE := $(BUILD_DIR)/GlassPaneTests
MARKDOWN_IT := Vendor/markdown-it/markdown-it.min.js
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
APP_FRAMEWORKS := -framework AppKit -framework Foundation -framework QuartzCore -framework SceneKit -framework CoreText -framework Cocoa -framework IOSurface -framework WebKit -framework Virtualization -framework Security -lsqlite3 -lpthread
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

$(APP_BUILD_STAMP): Makefile $(SIGNING_CONFIG) $(APP_OBJECTS) Info.plist ChromiumHelper-Info.plist $(APP_ENTITLEMENTS) $(AGENT_RUNTIME_FILES) $(AGENT_LINUX_RUNTIME_STAMP) $(SIDEBAR_PLANET) $(APP_ICON) $(INBOX_ICON_FILES) $(BOOKMARK_ICON_FILES) $(MARKDOWN_IT) $(READABILITY_FILES) $(CEF_WRAPPER_LIB) $(HELPER_BUILD_STAMP)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources" "$(APP_BUNDLE)/Contents/Frameworks"
	xcrun clang++ $(APP_OBJECTS) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(APP_EXECUTABLE)"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(SIDEBAR_PLANET)" "$(APP_BUNDLE)/Contents/Resources/sidebar-planet.png"
	cp "$(APP_ICON)" "$(APP_BUNDLE)/Contents/Resources/Talaria.icns"
	ditto "assets/inbox-icons" "$(APP_BUNDLE)/Contents/Resources/inbox-icons"
	ditto "assets/browser-bookmarks" "$(APP_BUNDLE)/Contents/Resources/browser-bookmarks"
	cp "$(MARKDOWN_IT)" "$(APP_BUNDLE)/Contents/Resources/markdown-it.min.js"
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

$(APP_OBJECT_DIR)/%.m.o: Source/%.m $(APP_HEADERS) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang $(OBJCFLAGS) -ISource -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.mm.o: Source/%.mm $(APP_HEADERS) $(CEF_EXTRACT_STAMP) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.cc.o: Source/%.cc $(APP_HEADERS) $(CEF_EXTRACT_STAMP) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang++ $(CEF_CXXFLAGS) -ISource -c "$<" -o "$@"

$(HELPER_BUILD_STAMP): Makefile Source/ChromiumProcessHelper.cc ChromiumHelper-Info.plist $(CEF_WRAPPER_LIB)
	rm -rf "$(HELPER_BUNDLES_DIR)"
	mkdir -p "$(BUILD_DIR)" "$(HELPER_BUNDLES_DIR)"
	xcrun clang++ $(CEF_CXXFLAGS) Source/ChromiumProcessHelper.cc "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(HELPER_EXECUTABLE)"
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

$(CEF_WRAPPER_LIB): $(CEF_EXTRACT_STAMP) Makefile
	rm -rf "$(CEF_WRAPPER_OBJ_DIR)"
	mkdir -p "$(CEF_WRAPPER_OBJ_DIR)"
	@set -e; \
	find "$(CEF_ROOT)/libcef_dll" -type f \( -name '*.cc' -o -name '*.mm' \) | sort > "$(CEF_WRAPPER_OBJ_DIR)/sources.txt"; \
	while IFS= read -r source; do \
	  relative="$${source#$(CEF_ROOT)/libcef_dll/}"; \
	  object="$(CEF_WRAPPER_OBJ_DIR)/$$relative.o"; \
	  mkdir -p "$$(dirname "$$object")"; \
	  xcrun clang++ $(CEF_CXXFLAGS) -DWRAPPING_CEF_SHARED -c "$$source" -o "$$object"; \
	done < "$(CEF_WRAPPER_OBJ_DIR)/sources.txt"
	xcrun ar rcs "$(CEF_WRAPPER_LIB)" $$(find "$(CEF_WRAPPER_OBJ_DIR)" -type f -name '*.o' | sort)

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

$(AGENT_LINUX_RUNTIME_STAMP): Scripts/build-agent-initrd.py $(AGENT_RUNTIME_FILES)
	mkdir -p "$(AGENT_LINUX_RUNTIME_DIR)"
	curl -fL -o "$(AGENT_LINUX_KERNEL_ZBOOT).tmp" "$(ALPINE_NETBOOT_URL)/vmlinuz-virt"
	mv "$(AGENT_LINUX_KERNEL_ZBOOT).tmp" "$(AGENT_LINUX_KERNEL_ZBOOT)"
	@actual=$$(shasum -a 256 "$(AGENT_LINUX_KERNEL_ZBOOT)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(ALPINE_KERNEL_SHA256)" ]; then \
	  rm -f "$(AGENT_LINUX_KERNEL_ZBOOT)"; \
	  echo "Alpine kernel checksum mismatch: $$actual"; \
	  exit 1; \
	fi
	curl -fL -o "$(AGENT_LINUX_BASE_INITRD).tmp" "$(ALPINE_NETBOOT_URL)/initramfs-virt"
	mv "$(AGENT_LINUX_BASE_INITRD).tmp" "$(AGENT_LINUX_BASE_INITRD)"
	@actual=$$(shasum -a 256 "$(AGENT_LINUX_BASE_INITRD)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(ALPINE_INITRD_SHA256)" ]; then \
	  rm -f "$(AGENT_LINUX_BASE_INITRD)"; \
	  echo "Alpine initrd checksum mismatch: $$actual"; \
	  exit 1; \
	fi
	curl -fL -o "$(AGENT_LINUX_MODLOOP).tmp" "$(ALPINE_NETBOOT_URL)/modloop-virt"
	mv "$(AGENT_LINUX_MODLOOP).tmp" "$(AGENT_LINUX_MODLOOP)"
	@actual=$$(shasum -a 256 "$(AGENT_LINUX_MODLOOP)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(ALPINE_MODLOOP_SHA256)" ]; then \
	  rm -f "$(AGENT_LINUX_MODLOOP)"; \
	  echo "Alpine modloop checksum mismatch: $$actual"; \
	  exit 1; \
	fi
	python3 Scripts/build-agent-initrd.py \
	  --alpine-release "$(ALPINE_RELEASE)" \
	  --zboot-kernel "$(AGENT_LINUX_KERNEL_ZBOOT)" \
	  --kernel-output "$(AGENT_LINUX_KERNEL)" \
	  --base-initrd "$(AGENT_LINUX_BASE_INITRD)" \
	  --modloop "$(AGENT_LINUX_MODLOOP)" \
	  --agent-script AgentRuntime/openrouter_agent.py \
	  --init-script AgentRuntime/talaria-init \
	  --cache-dir "$(AGENT_LINUX_APK_CACHE)" \
	  --output "$(AGENT_LINUX_INITRD)"
	test -s "$(AGENT_LINUX_KERNEL)"
	test -s "$(AGENT_LINUX_INITRD)"
	touch "$(AGENT_LINUX_RUNTIME_STAMP)"

test: test-hermes-gateway audit-theme-colors $(TEST_EXECUTABLE) $(TAB_LAYOUT_TEST_EXECUTABLE) $(NOTCH_VIEW_TEST_EXECUTABLE) $(GLASS_PANE_TEST_EXECUTABLE) $(BUILD_DIR)/CredentialStoreTests $(BUILD_DIR)/AssistantTurnResultTests $(BUILD_DIR)/AppStateManagerTests $(BUILD_DIR)/TransitionCoordinatorTests $(BUILD_DIR)/FeatureControllerTests
	"$(TEST_EXECUTABLE)"
	"$(TAB_LAYOUT_TEST_EXECUTABLE)"
	"$(NOTCH_VIEW_TEST_EXECUTABLE)"
	"$(GLASS_PANE_TEST_EXECUTABLE)"
	"$(BUILD_DIR)/CredentialStoreTests"
	"$(BUILD_DIR)/AssistantTurnResultTests"
	"$(BUILD_DIR)/AppStateManagerTests"
	"$(BUILD_DIR)/TransitionCoordinatorTests"
	"$(BUILD_DIR)/FeatureControllerTests"
	python3 Tests/AgentRuntimeTests.py

$(GLASS_PANE_TEST_EXECUTABLE): Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/design_system/UIComponents.m Source/design_system/TLMessageInput.m Source/design_system/TLGlassButton.m Source/design_system/TLBrowserChatPane.m Source/MarkdownRenderer.m Source/BrowserPageContext.m Source/PromptBuilder.m Source/InputSuggestions.m Source/TLBrowserHeightTransition.m Tests/GlassPaneTests.m
	mkdir -p "$(BUILD_DIR)"
	cp "$(MARKDOWN_IT)" "$(BUILD_DIR)/markdown-it.min.js"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -framework CoreText -framework WebKit -o "$@"

$(NOTCH_VIEW_TEST_EXECUTABLE): Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/NotchOverlayState.m Source/NotchOverlayController.m Tests/NotchOverlayViewTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -o "$@"

$(TAB_LAYOUT_TEST_EXECUTABLE): Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/WorkspaceState.m Source/design_system/TLTabIconView.m Source/design_system/TLChromeTabView.m Source/design_system/TLTransitionCoordinator.m Source/TLWorkspaceTabsController.m Tests/TabLayoutTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -framework CoreText -o "$@"

audit-theme-colors:
	python3 Scripts/audit-theme-colors.py

$(TEST_EXECUTABLE): Source/TalariaModels.m Source/PromptBuilder.m Source/PromptMessages.m Source/BrowserPageContext.m Source/BrowserConversation.m Source/StreamingBlockBuffer.m Source/OpenRouterSupport.m Source/OpenRouterParsing.m Source/OpenRouterRequestFactory.m Source/OpenRouterStream.m Source/OpenRouterClient.m Source/ChatIconGenerator.m Source/AgentClient.m Source/AgentVMService.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Source/AgentOrchestrator.m Source/AssistantTurnRunner.m Source/NotchOverlayState.m Source/WorkspaceState.m Source/AppStateManager.m Tests/PromptBuilderTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ $(TEST_FRAMEWORKS) -o "$@"

close-running-app:
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.2

run: build close-running-app
	open -n "$(CURDIR)/$(APP_BUNDLE)"

widgetbook: build close-running-app
	open -n "$(CURDIR)/$(APP_BUNDLE)" --args --widgetbook

clean:
	python3 -c 'import shutil; shutil.rmtree("$(BUILD_DIR)", ignore_errors=True)'

$(BUILD_DIR)/CredentialStoreTests: Source/TalariaModels.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Tests/CredentialStoreTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -framework Security -lsqlite3 -o "$@"

$(BUILD_DIR)/AssistantTurnResultTests: Source/TalariaModels.m Source/PromptMessages.m Source/PromptBuilder.m Source/StreamingBlockBuffer.m Source/AssistantTurnRunner.m Tests/AssistantTurnResultTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

$(BUILD_DIR)/AppStateManagerTests: Source/WorkspaceState.m Source/AppStateManager.m Tests/AppStateManagerTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

$(BUILD_DIR)/TransitionCoordinatorTests: Source/design_system/TLTransitionCoordinator.m Tests/TransitionCoordinatorTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -framework QuartzCore -o "$@"

$(BUILD_DIR)/FeatureControllerTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(CEF_WRAPPER_LIB) Tests/FeatureControllerTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $(filter %.m %.o %.a,$^) $(APP_FRAMEWORKS) -o "$@"

.PHONY: test-hermes-gateway
test-hermes-gateway:
	python3 -B -m unittest discover -s Tests -p "test_*.py"
