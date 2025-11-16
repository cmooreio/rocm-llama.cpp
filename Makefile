.PHONY: help all check-deps validate lint build build-nc build-amd64 dry-run test smoke-test scan scan-all sbom sign verify verify-key push push-signed clean clean-all update-versions version ci release release-signed

# Load version configuration (can be overridden via command line)
include versions.env

# Export variables so they can be used by build.sh
export ROCM_VERSION
export LLAMACPP_VERSION
export LLAMACPP_ROCM_ARCH

# Detect single vs multi-architecture build
# If LLAMACPP_ROCM_ARCH contains comma, it's multi-arch (no prefix)
# If no comma, it's single-arch (use arch as prefix: gfx1151-latest)
ARCH_PREFIX := $(shell echo "$(LLAMACPP_ROCM_ARCH)" | grep -q ',' && echo "" || echo "$(LLAMACPP_ROCM_ARCH)-")

# Docker image configuration
IMAGE_REPO := cmooreio/rocm-llama.cpp
IMAGE_TAG := $(ARCH_PREFIX)$(LLAMACPP_VERSION)
IMAGE_NAME := $(IMAGE_REPO):$(IMAGE_TAG)
IMAGE_LATEST := $(IMAGE_REPO):$(ARCH_PREFIX)latest

# Platform configuration (ROCm only supports AMD64)
NATIVE_PLATFORM := linux/amd64
BUILD_PLATFORM := linux/amd64

# Build arguments
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Docker buildx configuration
BUILDER_NAME := llama-rocm-builder

# Scan tool preference
SCAN_TOOL := $(shell command -v trivy 2>/dev/null || command -v grype 2>/dev/null || echo "")

# Dockerfile
DOCKERFILE := Dockerfile

# ============================================================================
# General Targets
# ============================================================================

help: ## Display this help message
	@echo "ROCm llama.cpp Docker Image Build System"
	@echo ""
	@echo "Current Configuration:"
	@echo "  ROCm Version:     $(ROCM_VERSION)"
	@echo "  llama.cpp Version: $(LLAMACPP_VERSION)"
	@echo "  ROCm Arch:        $(LLAMACPP_ROCM_ARCH)"
	@echo "  Dockerfile:       $(DOCKERFILE)"
	@echo "  Image:            $(IMAGE_NAME)"
	@echo "  Platform:         $(BUILD_PLATFORM)"
	@echo "  Build Date:       $(BUILD_DATE)"
	@echo "  VCS Ref:          $(VCS_REF)"
	@echo ""
	@echo "Quick Start:"
	@echo "  make build              # Build image for AMD64 platform"
	@echo "  make test               # Run tests"
	@echo "  make scan               # Security scan"
	@echo "  make push               # Build and push image"
	@echo ""
	@echo "\033[1mAvailable Targets:\033[0m"
	@echo ""
	@awk '/^# General Targets/,/^# Development Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mGeneral:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Development Targets/,/^# Building Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mDevelopment:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Building Targets/,/^# Testing Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mBuilding:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Testing Targets/,/^# Security Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mTesting:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Security Targets/,/^# Publishing Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mSecurity:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Publishing Targets/,/^# Maintenance Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mPublishing:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Maintenance Targets/,/^# Documentation Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mMaintenance:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Documentation Targets/,/^# CI\/CD Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mDocumentation:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# CI\/CD Targets/,0 { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mCI/CD:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@echo ""

all: validate lint build test scan ## Run complete build pipeline (validate, lint, build, test, scan)

check-deps: ## Check required dependencies
	@echo "Checking dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git is required but not installed"; exit 1; }
	@docker buildx version >/dev/null 2>&1 || { echo "Error: docker buildx is required"; exit 1; }
	@echo "All required dependencies are installed"

# ============================================================================
# Development Targets
# ============================================================================

validate: ## Validate versions.env and configuration
	@echo "Validating configuration..."
	@test -n "$(ROCM_VERSION)" || { echo "Error: ROCM_VERSION not set in versions.env"; exit 1; }
	@test -n "$(LLAMACPP_VERSION)" || { echo "Error: LLAMACPP_VERSION not set in versions.env"; exit 1; }
	@test -n "$(LLAMACPP_ROCM_ARCH)" || { echo "Error: LLAMACPP_ROCM_ARCH not set in versions.env"; exit 1; }
	@test -f "$(DOCKERFILE)" || { echo "Error: $(DOCKERFILE) not found"; exit 1; }
	@echo "✓ Configuration valid"

lint: ## Lint Dockerfile and shell scripts
	@echo "Linting Dockerfile..."
	@command -v hadolint >/dev/null 2>&1 && hadolint $(DOCKERFILE) || echo "hadolint not installed, skipping"
	@echo "Linting shell scripts..."
	@command -v shellcheck >/dev/null 2>&1 && find . -name "*.sh" -exec shellcheck {} + || echo "shellcheck not installed, skipping"

# ============================================================================
# Building Targets
# ============================================================================

build: check-deps ## Build Docker image for AMD64 platform
	@echo "Building llama-server-rocm image for: $(BUILD_PLATFORM)"
	@echo "WARNING: This build will take a long time due to compilation for multiple GPU architectures"
	@./build.sh --platform $(BUILD_PLATFORM)

build-nc: check-deps ## Build without cache
	@echo "Building without cache for: $(BUILD_PLATFORM)"
	@echo "WARNING: This will take significantly longer"
	@./build.sh --platform $(BUILD_PLATFORM) --no-cache

build-amd64: build ## Alias for build (ROCm only supports AMD64)

dry-run: check-deps validate ## Show build command without executing
	@echo "Dry run mode - showing command that would be executed:"
	@./build.sh --platform $(BUILD_PLATFORM) --dry-run

# ============================================================================
# Testing Targets
# ============================================================================

test: smoke-test ## Run all tests (smoke tests)

smoke-test: ## Run smoke tests (basic functionality)
	@echo "Running smoke tests..."
	@echo "Testing llama-server version..."
	@docker run --rm $(IMAGE_LATEST) --version || docker run --rm --entrypoint llama-cli $(IMAGE_LATEST) --version
	@echo "Testing help command..."
	@docker run --rm $(IMAGE_LATEST) --help
	@echo "✓ Smoke tests passed"

# ============================================================================
# Security Targets
# ============================================================================

scan: ## Security scan with available tool (trivy or grype)
	@if [ -z "$(SCAN_TOOL)" ]; then \
		echo "No security scanner found. Install trivy or grype:"; \
		echo "  brew install trivy"; \
		echo "  brew install grype"; \
		exit 1; \
	fi
	@echo "Scanning $(IMAGE_LATEST) with $(notdir $(SCAN_TOOL))..."
	@if [ "$(notdir $(SCAN_TOOL))" = "trivy" ]; then \
		trivy image --severity HIGH,CRITICAL $(IMAGE_LATEST); \
	else \
		grype $(IMAGE_LATEST); \
	fi

scan-all: ## Deep security scan with all severity levels
	@if [ -z "$(SCAN_TOOL)" ]; then \
		echo "No security scanner found"; \
		exit 1; \
	fi
	@echo "Deep scanning $(IMAGE_LATEST)..."
	@if [ "$(notdir $(SCAN_TOOL))" = "trivy" ]; then \
		trivy image --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL $(IMAGE_LATEST); \
	else \
		grype $(IMAGE_LATEST); \
	fi

sbom: ## Generate Software Bill of Materials
	@echo "Generating SBOM for $(IMAGE_LATEST)..."
	@if command -v syft >/dev/null 2>&1; then \
		syft $(IMAGE_LATEST) -o json > sbom-$(LLAMACPP_VERSION).json; \
		echo "SBOM saved to sbom-$(LLAMACPP_VERSION).json"; \
	else \
		echo "syft not installed. Install with: brew install syft"; \
		exit 1; \
	fi

sign: ## Sign image with cosign (requires image to be pushed first)
	@echo "Signing image $(IMAGE_LATEST)..."
	@if command -v cosign >/dev/null 2>&1; then \
		COSIGN_VERSION=$$(cosign version 2>&1 | grep GitVersion | cut -d: -f2 | tr -d ' ' | cut -d. -f1 | tr -d 'v'); \
		if [ "$$COSIGN_VERSION" -ge 2 ] 2>/dev/null; then \
			cosign sign --yes $(IMAGE_LATEST); \
		else \
			echo "ERROR: cosign v1.x does not support keyless signing"; \
			echo "Please either:"; \
			echo "  1. Upgrade to cosign v2.x: brew upgrade cosign"; \
			echo "  2. Generate a key pair: cosign generate-key-pair"; \
			echo "     Then sign with: cosign sign --key cosign.key $(IMAGE_LATEST)"; \
			exit 1; \
		fi; \
	else \
		echo "cosign not installed. Install with: brew install cosign"; \
		exit 1; \
	fi

verify: ## Verify image signature
	@echo "Verifying image signature..."
	@if command -v cosign >/dev/null 2>&1; then \
		cosign verify $(IMAGE_LATEST); \
	else \
		echo "cosign not installed"; \
		exit 1; \
	fi

verify-key: ## Verify image signature with public key
	@echo "Verifying with public key..."
	@if command -v cosign >/dev/null 2>&1; then \
		cosign verify --key cosign.pub $(IMAGE_LATEST); \
	else \
		echo "cosign not installed"; \
		exit 1; \
	fi

# ============================================================================
# Publishing Targets
# ============================================================================

push: check-deps ## Build and push to registry
	@echo "This will build and push $(IMAGE_REPO) to Docker Hub"
	@echo "Platform: $(BUILD_PLATFORM)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./build.sh --platform $(BUILD_PLATFORM) --push; \
	else \
		echo "Push cancelled"; \
		exit 1; \
	fi

push-signed: push sign ## Push and sign image (requires push confirmation)

# ============================================================================
# Maintenance Targets
# ============================================================================

clean: ## Remove local images
	@echo "Removing local images..."
	@docker rmi $(IMAGE_REPO):latest 2>/dev/null || true
	@docker rmi $(IMAGE_REPO):$(LLAMACPP_VERSION) 2>/dev/null || true
	@echo "Cleanup complete"

clean-all: clean ## Remove all build artifacts and builder
	@echo "Removing build artifacts..."
	@rm -f sbom-*.json
	@docker buildx rm $(BUILDER_NAME) 2>/dev/null || true
	@echo "Deep cleanup complete"

update-versions: ## Update BUILD_DATE and VCS_REF in versions.env
	@echo "Updating versions.env with current build info..."
	@sed -i.bak "s/^BUILD_DATE=.*/BUILD_DATE=$(BUILD_DATE)/" versions.env
	@sed -i.bak "s/^VCS_REF=.*/VCS_REF=$(VCS_REF)/" versions.env
	@rm -f versions.env.bak
	@echo "✓ Updated BUILD_DATE=$(BUILD_DATE)"
	@echo "✓ Updated VCS_REF=$(VCS_REF)"

# ============================================================================
# Documentation Targets
# ============================================================================

version: ## Show version information
	@echo "ROCm llama.cpp Docker Image Version Information"
	@echo "================================================"
	@echo ""
	@echo "ROCm Version:      $(ROCM_VERSION)"
	@echo "llama.cpp Version: $(LLAMACPP_VERSION)"
	@echo "ROCm Archs:        $(LLAMACPP_ROCM_ARCH)"
	@echo "Image Repository:  $(IMAGE_REPO)"
	@echo "Tags:              $(ARCH_PREFIX)latest, $(IMAGE_TAG)"
	@echo ""
	@echo "Build Information:"
	@echo "  Build Date:      $(BUILD_DATE)"
	@echo "  VCS Revision:    $(VCS_REF)"
	@echo "  Platform:        $(BUILD_PLATFORM)"
	@echo ""

# ============================================================================
# CI/CD Targets
# ============================================================================

ci: validate lint build test scan ## CI pipeline (validate, lint, build, test, scan)
	@echo "CI pipeline complete ✓"

release: validate lint build test scan ## Build release (tested, scanned)
	@echo "Release build complete. Ready to push."
	@echo "Run 'make push' to publish to registry."

release-signed: release push-signed ## Full release with signing
	@echo "Signed release complete ✓"
