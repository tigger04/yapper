# ABOUTME: Build, test, install, and release targets for yapper.
# ABOUTME: Standard entry points per project conventions.

# xcodebuild is required (not swift build) because MLX Swift needs
# Metal shader compilation, which only Xcode's build system supports.

.PHONY: build test lint install uninstall clean help

SCHEME := yapper-Package
DESTINATION := platform=OS X
INSTALL_DIR := $(HOME)/.local/bin
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData

build: ## Build the project
	xcodebuild build -scheme yapper -destination '$(DESTINATION)' -quiet

lint: ## Run linter
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "swiftlint not found, skipping lint"; \
	fi

test: lint ## Run regression tests (includes lint)
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@# MisakiSwift resource bundle must be copied into its framework for test discovery
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperKitTests 2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

install: build ## Install yapper to ~/.local/bin
	@mkdir -p "$(INSTALL_DIR)"
	$(eval BIN := $(shell find $(DERIVED_DATA)/yapper-*/Build/Products/Debug -name yapper -type f 2>/dev/null | head -1))
	@if [ -n "$(BIN)" ] && [ -f "$(BIN)" ]; then \
		ln -sf "$(BIN)" "$(INSTALL_DIR)/yapper"; \
		echo "Installed yapper to $(INSTALL_DIR)/yapper"; \
	else \
		echo "Error: could not find yapper binary. Run 'make build' first."; \
		exit 1; \
	fi

uninstall: ## Remove yapper from ~/.local/bin
	@rm -f "$(INSTALL_DIR)/yapper"
	@echo "Removed yapper from $(INSTALL_DIR)/yapper"

clean: ## Remove build artefacts
	swift package clean
	@xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet 2>/dev/null || true

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
