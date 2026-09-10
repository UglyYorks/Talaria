# Pinned, vendored readers; no external package manager or runtime dependency.
IMPORT_VENDOR := Vendor/browser-import
LEVELDB := $(IMPORT_VENDOR)/leveldb-1.23
SNAPPY := $(IMPORT_VENDOR)/snappy-1.1.9
IMPORT_SOURCES := $(wildcard $(LEVELDB)/db/*.cc) $(wildcard $(LEVELDB)/table/*.cc) $(wildcard $(LEVELDB)/util/*.cc) $(wildcard $(SNAPPY)/*.cc)
IMPORT_OBJECTS := $(patsubst $(IMPORT_VENDOR)/%.cc,$(BUILD_DIR)/browser-import/%.o,$(IMPORT_SOURCES))
IMPORT_FLAGS := -I$(LEVELDB)/include -I$(LEVELDB) -I$(SNAPPY) -DLEVELDB_PLATFORM_POSIX=1 -DHAVE_CONFIG_H=1
APP_OBJCXXFLAGS += $(IMPORT_FLAGS)
APP_FRAMEWORKS += $(BUILD_DIR)/libbrowser_import.a
$(APP_BUILD_STAMP) $(APP_LINK_EXECUTABLE) $(HELPER_BUILD_STAMP) $(addprefix $(BUILD_DIR)/,$(INTEGRATION_TESTS)): $(BUILD_DIR)/libbrowser_import.a
# Existing integration tests link APP_FRAMEWORKS and therefore need this archive.
$(BUILD_DIR)/libcef_dll_wrapper.a: | $(BUILD_DIR)/libbrowser_import.a
IMPORT_COMPILE_CONFIG := $(BUILD_DIR)/.browser-import-config
$(IMPORT_COMPILE_CONFIG): FORCE
	@mkdir -p "$(BUILD_DIR)"
	@printf '%s\n' '$(IMPORT_FLAGS)' > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi
$(BUILD_DIR)/browser-import/%.o: $(IMPORT_VENDOR)/%.cc Scripts/browser-import.mk $(IMPORT_COMPILE_CONFIG)
	@mkdir -p "$(@D)"
	xcrun clang++ -std=c++17 -O2 -fvisibility=hidden -mmacosx-version-min=13.0 $(IMPORT_FLAGS) -MMD -MP -MF "$@.d" -c $< -o $@
$(BUILD_DIR)/libbrowser_import.a: $(IMPORT_OBJECTS)
	xcrun ar rcs $@ $^
.PHONY: test-browser-import
test-browser-import: $(BUILD_DIR)/BrowserProfileImportTests
	"$<"
$(BUILD_DIR)/BrowserProfileImportTests: Source/TLBrowserProfileImporter.mm Tests/BrowserProfileImportTests.mm $(BUILD_DIR)/libbrowser_import.a
	xcrun clang++ $(OBJCFLAGS) $(IMPORT_FLAGS) -std=c++17 -ISource $(filter %.mm,$^) -framework AppKit -framework Security -lsqlite3 $(BUILD_DIR)/libbrowser_import.a -o $@
test: test-browser-import

.PHONY: test-browser-import-cef
test-browser-import-cef: build
	mkdir -p "$(BUILD_DIR)/BrowserImportProbe.app/Contents/MacOS"
	cp Info.plist "$(BUILD_DIR)/BrowserImportProbe.app/Contents/Info.plist"
	python3 Scripts/prepare-browser-test-bundle.py "$(APP_BUNDLE)" "$(BUILD_DIR)/BrowserImportProbe.app"
	xcrun clang++ $(APP_OBJCXXFLAGS) -ISource Tests/BrowserProfileImportCEFTests.mm $(filter-out $(APP_OBJECT_DIR)/main.mm.o,$(APP_OBJECTS)) "$(CEF_WRAPPER_LIB)" $(APP_FRAMEWORKS) -o "$(BUILD_DIR)/BrowserImportProbe.app/Contents/MacOS/Talaria"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(APP_ENTITLEMENTS)" "$(BUILD_DIR)/BrowserImportProbe.app"
	python3 Scripts/test-browser-import.py

.PHONY: test-browser-import-ui
test-browser-import-ui: $(BUILD_DIR)/FeatureControllerTests
	TL_TEST_BROWSER_IMPORT_ONLY=1 "$(BUILD_DIR)/FeatureControllerTests"

-include $(IMPORT_OBJECTS:=.d)
