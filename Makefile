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
APP_CXX_SOURCES := $(wildcard Source/*.cc)
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
OVERLAY_PROBE := Source/BrowserOverlayProbe.js
WEBKIT_BRIDGE := Source/BrowserWebKitBridge.js
DOCUMENT_FOOTER := Source/BrowserDocumentFooter.js Source/BrowserFooterColor.js
CODE_RESOURCES := Source/MarkdownFind.js Source/MarkdownCode.js Vendor/highlight.js/highlight.min.js Vendor/highlight.js/LICENSE
MATH_RESOURCES := Source/MarkdownMath.js $(shell find Vendor/katex -type f)
MARKDOWN_RESOURCES_STAMP := $(BUILD_DIR)/.markdown-resources.stamp
READABILITY_FILES := Vendor/readability/Readability.js Vendor/readability/LICENSE.md
SIDEBAR_PLANET := assets/sidebar-planet.png
APP_ICON := assets/Talaria.icns
INBOX_ICON_FILES := $(wildcard assets/inbox-icons/*.svg)
BOOKMARK_ICON_FILES := $(wildcard assets/browser-bookmarks/*.png)
OBJCFLAGS := -fobjc-arc -fmodules -fmodules-cache-path=$(abspath $(BUILD_DIR)/module-cache) -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0
APP_OBJCXXFLAGS := $(OBJCFLAGS) -fno-exceptions -fno-rtti -fno-threadsafe-statics -fobjc-call-cxx-cdtors -fvisibility-inlines-hidden -std=c++20 -Wno-sign-compare -Wno-nullability-completeness -Wno-missing-field-initializers
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

$(APP_BUILD_STAMP): $(WEBKIT_BRIDGE) $(OVERLAY_PROBE) $(DOCUMENT_FOOTER) Makefile $(SIGNING_CONFIG) $(APP_OBJECTS) Info.plist $(APP_ENTITLEMENTS) $(AGENT_RUNTIME_FILES) $(AGENT_LINUX_RUNTIME_STAMP) $(SIDEBAR_PLANET) $(APP_ICON) $(INBOX_ICON_FILES) $(BOOKMARK_ICON_FILES) $(MARKDOWN_IT) $(MATH_RESOURCES) $(CODE_RESOURCES) $(READABILITY_FILES)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	xcrun clang++ $(APP_OBJECTS) $(APP_FRAMEWORKS) -o "$(APP_EXECUTABLE)"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(WEBKIT_BRIDGE)" "$(APP_BUNDLE)/Contents/Resources/BrowserWebKitBridge.js"
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
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(APP_BUNDLE)"
	touch "$(APP_BUILD_STAMP)"

$(APP_OBJECT_DIR)/%.m.o: Source/%.m $(APP_HEADERS) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang $(OBJCFLAGS) -ISource -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.mm.o: Source/%.mm $(APP_HEADERS) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource -c "$<" -o "$@"

$(APP_OBJECT_DIR)/%.cc.o: Source/%.cc $(APP_HEADERS) Makefile
	mkdir -p "$(dir $@)"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource -c "$<" -o "$@"

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
	  --agent-script AgentRuntime/talaria_agent.py \
	  --terminal-script AgentRuntime/terminal_service.py \
	  --init-script AgentRuntime/talaria-init \
	  --cache-dir "$(AGENT_LINUX_APK_CACHE)" \
	  --output "$(AGENT_LINUX_INITRD)"
	test -s "$(AGENT_LINUX_KERNEL)"
	test -s "$(AGENT_LINUX_INITRD)"
	touch "$(AGENT_LINUX_RUNTIME_STAMP)"

test: $(BUILD_DIR)/BookmarkTests $(BUILD_DIR)/AgentVMLockTests $(BUILD_DIR)/BrowserDownloadTests test-browser-overlay $(BUILD_DIR)/BrowserOverlayPolicyTests $(BUILD_DIR)/SplitWorkspaceTests $(BUILD_DIR)/TerminalClientProbe $(BUILD_DIR)/AppResetTests $(BUILD_DIR)/ChatAttachmentTests test-hermes-gateway audit-theme-colors $(TEST_EXECUTABLE) $(TAB_LAYOUT_TEST_EXECUTABLE) $(NOTCH_VIEW_TEST_EXECUTABLE) $(GLASS_PANE_TEST_EXECUTABLE) $(BUILD_DIR)/CredentialStoreTests $(BUILD_DIR)/AssistantTurnResultTests $(BUILD_DIR)/AppStateManagerTests $(BUILD_DIR)/TransitionCoordinatorTests $(BUILD_DIR)/FeatureControllerTests $(BUILD_DIR)/TabShortcutTests
	"$(BUILD_DIR)/BookmarkTests"
	"$(BUILD_DIR)/StarryEmptyStateTests"
	"$(BUILD_DIR)/BrowserHistoryTests"
	"$(BUILD_DIR)/BrowserDownloadTests"
	"$(BUILD_DIR)/BrowserSettingsTests"
	"$(BUILD_DIR)/WebKitDownloadLifecycleTests"
	"$(BUILD_DIR)/AgentVMLockTests"
	"$(BUILD_DIR)/IncognitoTests"
	"$(BUILD_DIR)/NotificationDataTests"
	"$(BUILD_DIR)/NotificationSidebarTests"
	"$(BUILD_DIR)/NotificationNavigationTests"
	"$(BUILD_DIR)/AutomationsTests"
	"$(BUILD_DIR)/QuickInputTests"
	"$(BUILD_DIR)/SplitWorkspaceTests"
	"$(BUILD_DIR)/BrowserOverlayPolicyTests"
	"$(BUILD_DIR)/WheelScrollAnimationTests"
	"$(BUILD_DIR)/ChatAttachmentTests"
	"$(BUILD_DIR)/AttachmentViewerTests"
	python3 -B Tests/TerminalServiceTests.py
	"$(BUILD_DIR)/AppResetTests"
	"$(TEST_EXECUTABLE)"
	"$(TAB_LAYOUT_TEST_EXECUTABLE)"
	"$(NOTCH_VIEW_TEST_EXECUTABLE)"
	"$(GLASS_PANE_TEST_EXECUTABLE)"
	"$(BUILD_DIR)/CredentialStoreTests"
	"$(BUILD_DIR)/AssistantTurnResultTests"
	"$(BUILD_DIR)/AppStateManagerTests"
	"$(BUILD_DIR)/WorkspaceSessionTests"
	"$(BUILD_DIR)/WorkspaceRestoreTests"
	"$(BUILD_DIR)/AppStartupTests"
	"$(BUILD_DIR)/TransitionCoordinatorTests"
	"$(BUILD_DIR)/FeatureControllerTests"
	"$(BUILD_DIR)/TabShortcutTests"
	"$(BUILD_DIR)/BrowserFindTests"
	"$(BUILD_DIR)/ChatFindTests"
	python3 Tests/AgentRuntimeTests.py
	"$(BUILD_DIR)/MarkdownMathTests"
	"$(BUILD_DIR)/MarkdownCodeTests"
	"$(BUILD_DIR)/MarkdownLinkContextTests"
	"$(BUILD_DIR)/MarkdownTableTests"

test: $(BUILD_DIR)/MarkdownLinkContextTests $(BUILD_DIR)/MarkdownMathTests $(BUILD_DIR)/MarkdownCodeTests $(BUILD_DIR)/MarkdownTableTests

test: $(BUILD_DIR)/QuickInputTests

test: $(BUILD_DIR)/AutomationsTests
test: $(BUILD_DIR)/WorkspaceSessionTests $(BUILD_DIR)/WorkspaceRestoreTests
test: $(BUILD_DIR)/AppStartupTests
test: $(BUILD_DIR)/NotificationDataTests $(BUILD_DIR)/NotificationSidebarTests $(BUILD_DIR)/NotificationNavigationTests
test-notifications: $(BUILD_DIR)/NotificationDataTests $(BUILD_DIR)/NotificationSidebarTests $(BUILD_DIR)/NotificationNavigationTests test-hermes-gateway
	"$(BUILD_DIR)/NotificationDataTests"
	"$(BUILD_DIR)/NotificationSidebarTests"
	"$(BUILD_DIR)/NotificationNavigationTests"

$(BUILD_DIR)/NotificationDataTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/NotificationDataTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
$(BUILD_DIR)/NotificationSidebarTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/NotificationSidebarTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
$(BUILD_DIR)/NotificationNavigationTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/NotificationNavigationTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

test-automations: $(BUILD_DIR)/AutomationsTests
	"$(BUILD_DIR)/AutomationsTests"

$(BUILD_DIR)/AutomationsTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/AutomationsTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
$(BUILD_DIR)/QuickInputTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/QuickInputTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

# Explicit native integration check; uses existing Screen Recording access only.
.PHONY: test-screen-capture
test-screen-capture: $(BUILD_DIR)/ScreenCaptureTests check-signing-identity
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --identifier com.talaria.chat "$<"
	"$<"

$(BUILD_DIR)/ScreenCaptureTests: Source/TLScreenCapture.m Source/TLScreenCapture.h Tests/ScreenCaptureTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $(filter %.m,$^) -framework AppKit -framework ScreenCaptureKit -o "$@"

$(BUILD_DIR)/MarkdownCodeTests: Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/MarkdownRenderer.m Source/design_system/TLMarkdownContentWebView.m Tests/MarkdownCodeTests.m $(MARKDOWN_RESOURCES_STAMP)
	xcrun clang $(OBJCFLAGS) -ISource $(filter %.m,$^) -framework AppKit -framework WebKit -o "$@"

$(BUILD_DIR)/MarkdownTableTests: Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/MarkdownRenderer.m Source/design_system/TLMarkdownContentWebView.m Tests/MarkdownTableTests.m $(MARKDOWN_RESOURCES_STAMP)
	xcrun clang $(OBJCFLAGS) -ISource $(filter %.m,$^) -framework AppKit -framework WebKit -o "$@"

$(MARKDOWN_RESOURCES_STAMP): $(MARKDOWN_IT) $(MATH_RESOURCES) $(CODE_RESOURCES)
	mkdir -p "$(BUILD_DIR)"
	cp "$(MARKDOWN_IT)" "$(BUILD_DIR)/markdown-it.min.js"
	cp Source/MarkdownMath.js "$(BUILD_DIR)/MarkdownMath.js"
	cp Source/MarkdownFind.js Source/MarkdownCode.js Vendor/highlight.js/highlight.min.js "$(BUILD_DIR)/"
	ditto Vendor/katex "$(BUILD_DIR)/katex"
	touch "$@"

$(BUILD_DIR)/MarkdownMathTests: Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/MarkdownRenderer.m Source/design_system/TLMarkdownContentWebView.m Tests/MarkdownMathTests.m Tests/Fixtures/latex-formulas.md $(MARKDOWN_RESOURCES_STAMP)
	xcrun clang $(OBJCFLAGS) -ISource $(filter %.m,$^) -framework AppKit -framework WebKit -o "$@"

$(GLASS_PANE_TEST_EXECUTABLE) $(BUILD_DIR)/FeatureControllerTests $(BUILD_DIR)/MarkdownLinkContextTests: | $(MARKDOWN_RESOURCES_STAMP)

$(GLASS_PANE_TEST_EXECUTABLE): Source/design_system/TLButton.m Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/design_system/UIComponents.m Source/design_system/TLMessageInput.m Source/design_system/TLAttachmentChipView.m Source/design_system/TLGlassButton.m Source/design_system/TLTransitionCoordinator.m Source/design_system/TLBrowserChatPane.m Source/design_system/TLToolActivityView.m Source/design_system/TLApprovalCardView.m Source/design_system/TLThemedButton.m Source/MarkdownRenderer.m Source/design_system/TLMarkdownContentWebView.m Source/BrowserPageContext.m Source/PromptBuilder.m Source/InputSuggestions.m Source/TLBrowserHeightTransition.m Tests/GlassPaneTests.m
	mkdir -p "$(BUILD_DIR)"
	cp "$(MARKDOWN_IT)" "$(BUILD_DIR)/markdown-it.min.js"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -framework CoreText -framework WebKit -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -o "$@"

$(NOTCH_VIEW_TEST_EXECUTABLE): Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/design_system/TLNotchSurfaceView.m Source/NotchOverlayState.m Source/NotchOverlayController.m Tests/NotchOverlayViewTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -o "$@"

$(TAB_LAYOUT_TEST_EXECUTABLE): Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/WorkspaceState.m Source/design_system/TLTabIconView.m Source/design_system/TLChromeTabView.m Source/design_system/TLTransitionCoordinator.m Source/TLWorkspaceTabsController.m Tests/TabLayoutTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework AppKit -framework QuartzCore -framework CoreText -o "$@"

audit-theme-colors:
	python3 Scripts/audit-theme-colors.py

$(TEST_EXECUTABLE): Source/ChatAttachmentStore.m Source/TalariaModels.m Source/PromptBuilder.m Source/PromptMessages.m Source/BrowserPageContext.m Source/BrowserConversation.m Source/StreamingBlockBuffer.m Source/AgentModel.m Source/ChatIconGenerator.m Source/AgentClient.m Source/AgentVMService.m Source/TLAgentVMLock.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Source/AgentOrchestrator.m Source/AssistantTurnRunner.m Source/NotchOverlayState.m Source/WorkspaceState.m Source/AppStateManager.m Tests/PromptBuilderTests.m
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

$(BUILD_DIR)/WorkspaceSessionTests: Source/WorkspaceState.m Source/AppStateManager.m Source/TLWorkspaceSessionStore.m Tests/WorkspaceSessionTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

$(BUILD_DIR)/WorkspaceRestoreTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/WorkspaceRestoreTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

$(BUILD_DIR)/AppStartupTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/AppStartupTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

$(BUILD_DIR)/TransitionCoordinatorTests: Source/design_system/TLTransitionCoordinator.m Tests/TransitionCoordinatorTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -framework QuartzCore -o "$@"

$(BUILD_DIR)/FeatureControllerTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/FeatureControllerTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $(filter %.m %.o %.a,$^) $(APP_FRAMEWORKS) -o "$@"

$(BUILD_DIR)/ChatAttachmentTests: Source/ChatAttachmentStore.m Source/TalariaModels.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Source/PromptMessages.m Source/PromptBuilder.m Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m Source/design_system/TLMessageInput.m Source/design_system/TLAttachmentChipView.m Source/design_system/TLTransitionCoordinator.m Source/design_system/TLGlassButton.m Tests/ChatAttachmentTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -framework AppKit -framework QuartzCore -framework Security -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -lsqlite3 -o "$@"
$(BUILD_DIR)/TabShortcutTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/TabShortcutTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $(filter %.m %.o %.a,$^) $(APP_FRAMEWORKS) -o "$@"

.PHONY: test-hermes-gateway
test-hermes-gateway:
	python3 -B -m unittest discover -s Tests -p "test_*.py"

$(BUILD_DIR)/AppResetTests: Source/TLAppReset.m Source/TalariaModels.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Tests/AppResetTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework WebKit -framework Foundation -framework Security -lsqlite3 -o "$@"

$(BUILD_DIR)/TerminalClientProbe: Source/TLTerminalClient.m Tests/TerminalClientProbe.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

# Split state, native pane geometry and real chat workspace integration.
$(BUILD_DIR)/SplitWorkspaceTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/SplitWorkspaceTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
$(BUILD_DIR)/BrowserOverlayPolicyTests: Source/TLBrowserOverlayPolicy.m Tests/BrowserOverlayPolicyTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -o "$@"

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
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserPreferencesIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserPreferencesProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserPreferencesProbe.app"
	python3 Scripts/test-browser-preferences.py

.PHONY: test-browser-navigation
test-browser-navigation: build
	mkdir -p "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserNavigationProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserNavigationIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserNavigationProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserNavigationProbe.app"
	python3 Scripts/test-browser-navigation.py

test: $(BUILD_DIR)/WheelScrollAnimationTests

$(BUILD_DIR)/WheelScrollAnimationTests: Tests/WheelScrollAnimationTests.m Source/TLWheelScrollAnimation.m Source/TLBrowserWheelSmoother.m Source/TLWheelScrollAnimation.h Source/TLBrowserWheelSmoother.h
	xcrun clang $(OBJCFLAGS) -ISource $(filter %.m,$^) -framework AppKit -framework WebKit -framework QuartzCore -o "$@"

.PHONY: test-browser-smooth-scrolling
test-browser-smooth-scrolling: build $(BUILD_DIR)/WheelScrollAnimationTests
	"$(BUILD_DIR)/WheelScrollAnimationTests"
	mkdir -p "$(BUILD_DIR)/BrowserSmoothScrollingProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserSmoothScrollingProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserSmoothScrollingProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserSmoothScrollingIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserSmoothScrollingProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserSmoothScrollingProbe.app"
	python3 Scripts/test-browser-smooth-scrolling.py

.PHONY: test-browser-wheel-routing
test-browser-wheel-routing: build
	mkdir -p "$(BUILD_DIR)/BrowserWheelRoutingProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserWheelRoutingProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserWheelRoutingProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserWheelRoutingWebKitTests.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserWheelRoutingProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserWheelRoutingProbe.app"
	python3 Scripts/test-browser-wheel-routing.py

.PHONY: test-browser-user-agent
test-browser-user-agent: build
	mkdir -p "$(BUILD_DIR)/BrowserUserAgentProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserUserAgentProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserUserAgentProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserUserAgentIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserUserAgentProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserUserAgentProbe.app"
	python3 Scripts/test-browser-user-agent.py

# Native conversation attachment viewer, including transcript integration.
test: $(BUILD_DIR)/AttachmentViewerTests

$(BUILD_DIR)/AttachmentViewerTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/AttachmentViewerTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

$(BUILD_DIR)/BrowserDownloadTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/BrowserDownloadTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $(filter %.m %.o %.a,$^) $(APP_FRAMEWORKS) -o "$@"

.PHONY: test-browser-images
test-browser-images: build
	mkdir -p "$(BUILD_DIR)/BrowserImageProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserImageProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserImageProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserImageIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserImageProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserImageProbe.app"
	python3 Scripts/test-browser-images.py

.PHONY: test-browser-links
test-browser-links: build
	mkdir -p "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserLinkProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserLinkIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserLinkProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserLinkProbe.app"
	python3 Scripts/test-browser-links.py

# Shared browser/markdown link-menu parity and native context routing.
$(BUILD_DIR)/MarkdownLinkContextTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/MarkdownLinkContextTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

test: $(BUILD_DIR)/BrowserFindTests

test-browser-find: $(BUILD_DIR)/BrowserFindTests
	"$(BUILD_DIR)/BrowserFindTests"

$(BUILD_DIR)/BrowserFindTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/BrowserFindTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

.PHONY: test-browser-find test-browser-find-webkit
test-browser-find-webkit: build
	mkdir -p "$(BUILD_DIR)/BrowserFindProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserFindProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserFindProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserFindWebKitTests.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserFindProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserFindProbe.app"
	python3 Scripts/test-browser-find.py

$(BUILD_DIR)/AgentVMLockTests: Source/TLAgentVMLock.m Source/AgentVMService.m Source/TalariaModels.m Tests/AgentVMLockTests.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang $(OBJCFLAGS) -ISource $^ -framework Foundation -framework AppKit -framework Virtualization -o "$@"

# Native transcript search plus real WebKit rendering, without network or an AI runtime.
test: $(BUILD_DIR)/ChatFindTests
$(BUILD_DIR)/ChatFindTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/ChatFindTests.m | $(MARKDOWN_RESOURCES_STAMP)
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

$(BUILD_DIR)/BookmarkTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/BookmarkTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
# Browsing history migration, persistence and native navigation callback routing.
test: $(BUILD_DIR)/BrowserHistoryTests

$(BUILD_DIR)/BrowserHistoryTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/BrowserHistoryTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

include Scripts/browser-import.mk

# Empty chat sky rendering, responsive tips and loading/message transitions.
test: $(BUILD_DIR)/StarryEmptyStateTests
$(BUILD_DIR)/StarryEmptyStateTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/StarryEmptyStateTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"

# Private windows use independent memory-only state and dispose their runtimes on close.
test: $(BUILD_DIR)/IncognitoTests
$(BUILD_DIR)/IncognitoTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/IncognitoTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
.PHONY: test-incognito-browser
test-incognito-browser: build
	mkdir -p "$(BUILD_DIR)/IncognitoBrowserProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/IncognitoBrowserProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/IncognitoBrowserProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/IncognitoBrowserIntegration.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/IncognitoBrowserProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/IncognitoBrowserProbe.app"
	python3 Scripts/test-incognito-browser.py

# Saved browser controls must reach the native WebKit APIs, including guarded SPI.
test: $(BUILD_DIR)/BrowserSettingsTests
test: $(BUILD_DIR)/WebKitDownloadLifecycleTests
test-webkit-download-lifecycle: $(BUILD_DIR)/WebKitDownloadLifecycleTests
	"$(BUILD_DIR)/WebKitDownloadLifecycleTests"
$(BUILD_DIR)/WebKitDownloadLifecycleTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/WebKitDownloadLifecycleTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
$(BUILD_DIR)/BrowserSettingsTests: $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) Tests/BrowserSettingsTests.m
	xcrun clang++ $(OBJCFLAGS) -ISource $^ $(APP_FRAMEWORKS) -o "$@"
