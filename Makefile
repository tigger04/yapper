# ABOUTME: Build, test, install, and release targets for yapper.
# ABOUTME: Standard entry points per project conventions.

# xcodebuild is required (not swift build) because MLX Swift needs
# Metal shader compilation, which only Xcode's build system supports.

.PHONY: build test test-framework test-cli test-one-off lint install uninstall clean help release release-models

SCHEME := yapper-Package
DESTINATION := platform=OS X
INSTALL_DIR := $(HOME)/.local/bin
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData

build: ## Build the project
	xcodebuild build -scheme yapper -destination '$(DESTINATION)' -quiet
	@# Copy MisakiSwift resource bundle into its framework (needed for CLI and tests)
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true

lint: ## Run linter
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "swiftlint not found, skipping lint"; \
	fi

test: test-framework test-cli ## Run all regression tests

test-framework: lint ## Run framework tests only
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperKitTests \
		-parallel-testing-enabled NO \
		-skip-testing:YapperKitTests/SpeakCommandTests \
		-skip-testing:YapperKitTests/VoicesCommandTests \
		2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

test-cli: lint ## Run CLI command tests only
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperKitTests/SpeakCommandTests \
		-only-testing:YapperKitTests/VoicesCommandTests \
		-parallel-testing-enabled NO \
		2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

test-one-off: lint ## Run one-off tests (not part of regression)
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperOneOffTests \
		-parallel-testing-enabled NO \
		2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

install: build ## Install yapper (and yap shortcut) to ~/.local/bin
	$(eval PRODDIR := $(shell find $(DERIVED_DATA)/yapper-*/Build/Products/Debug -name yapper -type f 2>/dev/null | head -1 | xargs dirname))
	@if [ -z "$(PRODDIR)" ]; then \
		echo "Error: could not find yapper binary. Run 'make build' first."; \
		exit 1; \
	fi
	@mkdir -p "$(INSTALL_DIR)"
	@# Both yapper and yap are symlinks to the same Mach-O. macOS resolves
	@# symlinks via _NSGetExecutablePath so Bundle.main lookups find the .bundle
	@# resources next to the real binary. The binary inspects CommandLine.arguments[0]
	@# at startup and routes `yap` invocations to the speak subcommand automatically.
	@ln -sf "$(PRODDIR)/yapper" "$(INSTALL_DIR)/yapper"
	@ln -sf "$(PRODDIR)/yapper" "$(INSTALL_DIR)/yap"
	@echo "Installed yapper and yap to $(INSTALL_DIR)"

uninstall: ## Remove yapper and yap from ~/.local/bin
	@rm -f "$(INSTALL_DIR)/yapper" "$(INSTALL_DIR)/yap"
	@echo "Removed yapper and yap from $(INSTALL_DIR)"

clean: ## Remove build artefacts
	swift package clean
	@xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet 2>/dev/null || true

release-models: ## Package and upload model weights + English voices to models-v1 release
	@bash scripts/release-models.sh

release: ## Bump version, tag, push, update Homebrew formula (usage: make release [VERSION])
	@bash scripts/release.sh $(VERSION)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
