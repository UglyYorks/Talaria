# Narrow module sets are shared by the app objects and native tests.
THEME_SOURCES := Source/Theme.m Source/design_system/ThemeSharedColors.m Source/design_system/ThemeLightColors.m Source/design_system/ThemeDarkColors.m
STORAGE_SOURCES := Source/TalariaModels.m Source/SQLiteConnection.m Source/DatabaseMigrator.m Source/TLCredentialStore.m Source/Database.m Source/TLTranscriptReconciler.m
WORKSPACE_SOURCES := Source/WorkspaceState.m Source/AppStateManager.m
MARKDOWN_SOURCES := Source/MarkdownRenderer.m Source/design_system/TLMarkdownContentWebView.m

TEST_OBJECT_DIR := $(BUILD_DIR)/test-objects
test_objects = $(patsubst Source/%.m,$(APP_OBJECT_DIR)/%.m.o,$(filter Source/%.m,$(1))) $(patsubst Tests/%.m,$(TEST_OBJECT_DIR)/%.m.o,$(filter Tests/%.m,$(1)))
$(TEST_OBJECT_DIR)/%.m.o: Tests/%.m $(COMPILE_CONFIG)
	mkdir -p "$(dir $@)"
	xcrun clang $(OBJCFLAGS) -ISource -MMD -MP -MF "$@.d" -c "$<" -o "$@"

# One link recipe for narrow tests, one shared dependency set for app integration.
define native_test
$(BUILD_DIR)/$(1): $(call test_objects,$(TEST_$(1)_SOURCES)) $(TEST_$(1)_EXTRA) Scripts/tests.mk $(COMPILE_CONFIG)
	xcrun clang++ $$(filter %.o %.a,$$^) $(TEST_$(1)_LIBS) -o "$$@"
endef

TEST_ScreenCaptureTests_SOURCES := Source/TLScreenCapture.m Tests/ScreenCaptureTests.m
TEST_ScreenCaptureTests_LIBS := -framework AppKit -framework ScreenCaptureKit
$(eval $(call native_test,ScreenCaptureTests))

TEST_MarkdownCodeTests_SOURCES := Tests/MarkdownCodeTests.m $(THEME_SOURCES) $(MARKDOWN_SOURCES)
TEST_MarkdownCodeTests_LIBS := -framework AppKit -framework WebKit
TEST_MarkdownCodeTests_EXTRA := $(MARKDOWN_RESOURCES_STAMP)
$(eval $(call native_test,MarkdownCodeTests))

TEST_MarkdownTableTests_SOURCES := Tests/MarkdownTableTests.m $(THEME_SOURCES) $(MARKDOWN_SOURCES)
TEST_MarkdownTableTests_LIBS := -framework AppKit -framework WebKit
TEST_MarkdownTableTests_EXTRA := $(MARKDOWN_RESOURCES_STAMP)
$(eval $(call native_test,MarkdownTableTests))

TEST_MarkdownMathTests_SOURCES := Tests/MarkdownMathTests.m $(THEME_SOURCES) $(MARKDOWN_SOURCES)
TEST_MarkdownMathTests_LIBS := -framework AppKit -framework WebKit
TEST_MarkdownMathTests_EXTRA := Tests/Fixtures/latex-formulas.md $(MARKDOWN_RESOURCES_STAMP)
$(eval $(call native_test,MarkdownMathTests))

TEST_GlassPaneTests_SOURCES := Source/design_system/TLButton.m Source/design_system/UIComponents.m Source/design_system/TLMessageInput.m Source/design_system/TLAttachmentChipView.m Source/design_system/TLGlassButton.m Source/design_system/TLTransitionCoordinator.m Source/design_system/TLBrowserChatPane.m Source/design_system/TLToolActivityView.m Source/design_system/TLApprovalCardView.m Source/design_system/TLThemedButton.m Source/BrowserPageContext.m Source/PromptBuilder.m Source/InputSuggestions.m Source/TLBrowserHeightTransition.m Tests/GlassPaneTests.m $(THEME_SOURCES) $(MARKDOWN_SOURCES)
TEST_GlassPaneTests_LIBS := -framework AppKit -framework QuartzCore -framework CoreText -framework WebKit -framework QuickLookThumbnailing -framework UniformTypeIdentifiers
TEST_GlassPaneTests_EXTRA := $(MARKDOWN_RESOURCES_STAMP)
$(eval $(call native_test,GlassPaneTests))

TEST_NotchOverlayViewTests_SOURCES := Source/design_system/TLNotchSurfaceView.m Source/NotchOverlayState.m Source/NotchOverlayController.m Tests/NotchOverlayViewTests.m $(THEME_SOURCES)
TEST_NotchOverlayViewTests_LIBS := -framework AppKit -framework QuartzCore
$(eval $(call native_test,NotchOverlayViewTests))

TEST_TabLayoutTests_SOURCES := Source/WorkspaceState.m Source/design_system/TLTabIconView.m Source/design_system/TLChromeTabView.m Source/design_system/TLTransitionCoordinator.m Source/TLWorkspaceTabsController.m Tests/TabLayoutTests.m $(THEME_SOURCES)
TEST_TabLayoutTests_LIBS := -framework AppKit -framework QuartzCore -framework CoreText
$(eval $(call native_test,TabLayoutTests))

TEST_PromptBuilderTests_SOURCES := Source/ChatAttachmentStore.m Source/PromptBuilder.m Source/PromptMessages.m Source/BrowserPageContext.m Source/BrowserConversation.m Source/StreamingBlockBuffer.m Source/AgentModel.m Source/ChatIconGenerator.m Source/AgentClient.m Source/TLAgentProtocol.m Source/AgentVMService.m Source/TLAgentVMLock.m Source/AgentOrchestrator.m Source/AssistantTurnRunner.m Source/NotchOverlayState.m Tests/PromptBuilderTests.m $(STORAGE_SOURCES) $(WORKSPACE_SOURCES)
TEST_PromptBuilderTests_LIBS := $(TEST_FRAMEWORKS)
$(eval $(call native_test,PromptBuilderTests))

TEST_CredentialStoreTests_SOURCES := Tests/CredentialStoreTests.m $(STORAGE_SOURCES)
TEST_CredentialStoreTests_LIBS := -framework Foundation -framework Security -lsqlite3
$(eval $(call native_test,CredentialStoreTests))

TEST_AssistantTurnResultTests_SOURCES := Source/TalariaModels.m Source/PromptMessages.m Source/PromptBuilder.m Source/StreamingBlockBuffer.m Source/AssistantTurnRunner.m Tests/AssistantTurnResultTests.m
TEST_AssistantTurnResultTests_LIBS := -framework Foundation
$(eval $(call native_test,AssistantTurnResultTests))

TEST_AppStateManagerTests_SOURCES := Tests/AppStateManagerTests.m $(WORKSPACE_SOURCES)
TEST_AppStateManagerTests_LIBS := -framework Foundation
$(eval $(call native_test,AppStateManagerTests))

TEST_WorkspaceSessionTests_SOURCES := Source/TLWorkspaceSessionStore.m Tests/WorkspaceSessionTests.m $(WORKSPACE_SOURCES)
TEST_WorkspaceSessionTests_LIBS := -framework Foundation
$(eval $(call native_test,WorkspaceSessionTests))

TEST_TransitionCoordinatorTests_SOURCES := Source/design_system/TLTransitionCoordinator.m Tests/TransitionCoordinatorTests.m
TEST_TransitionCoordinatorTests_LIBS := -framework Foundation -framework QuartzCore
$(eval $(call native_test,TransitionCoordinatorTests))

TEST_ChatAttachmentTests_SOURCES := Source/ChatAttachmentStore.m Source/PromptMessages.m Source/PromptBuilder.m Source/design_system/TLMessageInput.m Source/design_system/TLAttachmentChipView.m Source/design_system/TLTransitionCoordinator.m Source/design_system/TLGlassButton.m Tests/ChatAttachmentTests.m $(THEME_SOURCES) $(STORAGE_SOURCES)
TEST_ChatAttachmentTests_LIBS := -framework Foundation -framework AppKit -framework QuartzCore -framework Security -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -lsqlite3
$(eval $(call native_test,ChatAttachmentTests))

TEST_AppResetTests_SOURCES := Source/TLAppReset.m Tests/AppResetTests.m $(STORAGE_SOURCES)
TEST_AppResetTests_LIBS := -framework Foundation -framework Security -lsqlite3
$(eval $(call native_test,AppResetTests))

TEST_BrowserOverlayPolicyTests_SOURCES := Source/TLBrowserOverlayPolicy.m Tests/BrowserOverlayPolicyTests.m
TEST_BrowserOverlayPolicyTests_LIBS := -framework Foundation
$(eval $(call native_test,BrowserOverlayPolicyTests))

TEST_AgentVMLockTests_SOURCES := Source/TLAgentVMLock.m Source/AgentVMService.m Source/TalariaModels.m Tests/AgentVMLockTests.m
TEST_AgentVMLockTests_LIBS := -framework Foundation -framework AppKit -framework Virtualization
$(eval $(call native_test,AgentVMLockTests))

TEST_AgentProtocolTests_SOURCES := Source/TLAgentProtocol.m Tests/AgentProtocolTests.m
TEST_AgentProtocolTests_LIBS := -framework Foundation
$(eval $(call native_test,AgentProtocolTests))

INTEGRATION_TESTS := HistoryQueryTests AutomationsTests QuickInputTests WorkspaceRestoreTests AppStartupTests FeatureControllerTests TabShortcutTests SplitWorkspaceTests AttachmentViewerTests BrowserDownloadTests MarkdownLinkContextTests BrowserFindTests ChatFindTests BookmarkTests BrowserHistoryTests StarryEmptyStateTests
$(addprefix $(BUILD_DIR)/,$(INTEGRATION_TESTS)): $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) $(CEF_WRAPPER_LIB) Scripts/tests.mk $(COMPILE_CONFIG)
	xcrun clang++ $(filter %.o,$^) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$@"
$(foreach test,$(INTEGRATION_TESTS),$(eval $(BUILD_DIR)/$(test): $(call test_objects,Tests/$(test).m)))
$(addprefix $(BUILD_DIR)/,$(INTEGRATION_TESTS)): | $(MARKDOWN_RESOURCES_STAMP)

TEST_RepositoryTests_SOURCES := $(STORAGE_SOURCES) Source/TLHistoryRepository.m Tests/RepositoryTests.m
TEST_RepositoryTests_LIBS := -framework Foundation -framework Security -lsqlite3
$(eval $(call native_test,RepositoryTests))

CORE_TESTS := RepositoryTests PromptBuilderTests CredentialStoreTests AssistantTurnResultTests AppStateManagerTests WorkspaceSessionTests AppResetTests BrowserOverlayPolicyTests AgentVMLockTests AgentProtocolTests
NATIVE_TESTS := HistoryQueryTests RepositoryTests AutomationsTests QuickInputTests MarkdownCodeTests MarkdownTableTests MarkdownMathTests GlassPaneTests NotchOverlayViewTests TabLayoutTests PromptBuilderTests CredentialStoreTests AssistantTurnResultTests AppStateManagerTests WorkspaceSessionTests WorkspaceRestoreTests AppStartupTests TransitionCoordinatorTests FeatureControllerTests ChatAttachmentTests TabShortcutTests AppResetTests SplitWorkspaceTests BrowserOverlayPolicyTests AttachmentViewerTests BrowserDownloadTests MarkdownLinkContextTests BrowserFindTests AgentVMLockTests ChatFindTests BookmarkTests BrowserHistoryTests StarryEmptyStateTests AgentProtocolTests
.PHONY: test test-core test-integration
# GUI suites run sequentially: AppKit focus and the pasteboard are shared resources.
test: $(addprefix $(BUILD_DIR)/,$(NATIVE_TESTS)) $(BUILD_DIR)/TerminalClientProbe test-hermes-gateway test-browser-overlay audit-theme-colors
	@set -e; for test in $(NATIVE_TESTS); do "$(BUILD_DIR)/$$test"; done
	python3 -B Tests/TerminalServiceTests.py
	python3 -B Tests/AgentRuntimeTests.py

test-core: $(addprefix $(BUILD_DIR)/,$(CORE_TESTS)) test-hermes-gateway
	@set -e; for test in $(CORE_TESTS); do "$(BUILD_DIR)/$$test"; done

test-integration: $(addprefix $(BUILD_DIR)/,$(INTEGRATION_TESTS))
	@set -e; for test in $(INTEGRATION_TESTS); do "$(BUILD_DIR)/$$test"; done

-include $(wildcard $(TEST_OBJECT_DIR)/*.d)
