# Included only for CEF builds, after the distribution has been extracted.
.DEFAULT_GOAL := all
SOURCES := $(shell find "$(CEF_ROOT)/libcef_dll" -type f \( -name '*.cc' -o -name '*.mm' \) | sort)
OBJECTS := $(patsubst $(CEF_ROOT)/libcef_dll/%,$(CEF_WRAPPER_OBJ_DIR)/%.o,$(SOURCES))
.PHONY: all
all: $(CEF_WRAPPER_LIB)
$(CEF_WRAPPER_OBJ_DIR)/%.o: $(CEF_ROOT)/libcef_dll/% $(CEF_COMPILE_CONFIG) Scripts/cef-wrapper.mk
	mkdir -p "$(dir $@)"
	xcrun clang++ $(CEF_CXXFLAGS) -DWRAPPING_CEF_SHARED -MMD -MP -MF "$@.d" -c "$<" -o "$@"
$(CEF_WRAPPER_LIB): $(OBJECTS)
	xcrun ar rcs "$@" $(OBJECTS)
-include $(OBJECTS:=.d)
