#!/usr/bin/env bash
# ROCm llama.cpp Docker Image Build Script
# Security-hardened build script with validation and ROCm support
# NO eval() usage - security best practice

set -euo pipefail

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build ROCm llama.cpp Docker image with AMD GPU support.

OPTIONS:
    --platform PLATFORM    Platform to build (default: linux/amd64)
                          Note: ROCm only supports AMD64
    --push                Push image to registry after build
    --no-cache            Build without using cache
    --dry-run             Show build command without executing
    --scan                Run security scan after build
    --sign                Sign image with cosign after build
    --help                Display this help message

EXAMPLES:
    # Build for AMD64 platform (default)
    $(basename "$0")

    # Build and push
    $(basename "$0") --push

    # Build with security scan
    $(basename "$0") --scan

    # Dry run (show command without executing)
    $(basename "$0") --dry-run

ENVIRONMENT:
    DEBUG=true            Enable debug output

VERSION:
    The script reads version information from versions.env

WARNING:
    Building this image takes a LONG time due to compilation for
    multiple AMD GPU architectures (gfx803, gfx900, gfx906, etc.)

EOF
}

# Validate version/tag format
validate_version() {
    local version="$1"
    if [[ -z "$version" ]]; then
        log_error "Version/tag cannot be empty"
        return 1
    fi
    # Accept any non-empty string (tags, branches, commit hashes)
    return 0
}

# Load and validate versions.env
load_versions() {
    local versions_file="${SCRIPT_DIR}/versions.env"

    if [[ ! -f "$versions_file" ]]; then
        log_error "versions.env not found at: $versions_file"
        exit 1
    fi

    # Save any existing environment variables (from Makefile)
    local env_rocm_version="${ROCM_VERSION:-}"
    local env_llamacpp_version="${LLAMACPP_VERSION:-}"
    local env_llamacpp_rocm_arch="${LLAMACPP_ROCM_ARCH:-}"

    log_info "Loading versions from: $versions_file"

    # Source the file to load default values
    # shellcheck source=/dev/null
    source "$versions_file"

    # Prefer environment variables over versions.env
    ROCM_VERSION="${env_rocm_version:-$ROCM_VERSION}"
    LLAMACPP_VERSION="${env_llamacpp_version:-$LLAMACPP_VERSION}"
    LLAMACPP_ROCM_ARCH="${env_llamacpp_rocm_arch:-$LLAMACPP_ROCM_ARCH}"

    # Validate ROCm version
    if [[ -z "${ROCM_VERSION:-}" ]]; then
        log_error "ROCM_VERSION not set"
        exit 1
    fi

    # Validate llama.cpp version
    if [[ -z "${LLAMACPP_VERSION:-}" ]]; then
        log_error "LLAMACPP_VERSION not set"
        exit 1
    fi

    # Validate version format
    validate_version "$LLAMACPP_VERSION" || exit 1

    # Validate ROCm arch
    if [[ -z "${LLAMACPP_ROCM_ARCH:-}" ]]; then
        log_error "LLAMACPP_ROCM_ARCH not set"
        exit 1
    fi

    log_info "ROCm version: $ROCM_VERSION"
    log_info "llama.cpp version: $LLAMACPP_VERSION"
    log_info "ROCm architectures: $LLAMACPP_ROCM_ARCH"
}

# Parse command-line arguments
parse_args() {
    PLATFORM="linux/amd64"
    PUSH=false
    NO_CACHE=false
    DRY_RUN=false
    SCAN=false
    SIGN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --platform)
                PLATFORM="$2"
                if [[ "$PLATFORM" != "linux/amd64" ]]; then
                    log_warn "ROCm only supports AMD64 platform, using linux/amd64"
                    PLATFORM="linux/amd64"
                fi
                shift 2
                ;;
            --push)
                PUSH=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --scan)
                SCAN=true
                shift
                ;;
            --sign)
                SIGN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Export for use in build functions
    export PLATFORM PUSH NO_CACHE DRY_RUN SCAN SIGN
}

# Create or ensure buildx builder exists
ensure_builder() {
    local builder_name="llama-rocm-builder"

    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        log_info "Creating buildx builder: $builder_name" >&2
        docker buildx create --name "$builder_name" --driver docker-container --bootstrap >&2
    else
        log_debug "Builder $builder_name already exists" >&2
    fi

    echo "$builder_name"
}

# Build Docker image
build_image() {
    local builder_name
    builder_name="$(ensure_builder)"

    # Generate build metadata
    local build_date
    build_date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local vcs_ref
    vcs_ref="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

    # Image configuration
    local image_repo="cmooreio/rocm-llama.cpp"
    local dockerfile="Dockerfile"

    # Detect single vs multi-architecture build
    local arch_prefix=""
    if [[ "$LLAMACPP_ROCM_ARCH" != *","* ]]; then
        # Single architecture - use arch as tag prefix
        arch_prefix="${LLAMACPP_ROCM_ARCH}-"
        log_info "Single architecture build detected: $LLAMACPP_ROCM_ARCH"
        log_info "Tags will be prefixed with: ${arch_prefix}"
    else
        # Multiple architectures - use standard tags
        log_info "Multi-architecture build detected"
    fi

    # Build tags
    # Single arch: gfx1151-latest, gfx1151-<version>
    # Multi arch: latest, <version>
    local -a tags=(
        "-t" "${image_repo}:${arch_prefix}latest"
        "-t" "${image_repo}:${arch_prefix}${LLAMACPP_VERSION}"
    )

    # Build command as array (NO eval for security)
    local -a build_cmd=(
        "docker" "buildx" "build"
        "--builder" "$builder_name"
        "--platform" "$PLATFORM"
        "--file" "$dockerfile"
        "--build-arg" "ROCM_VERSION=$ROCM_VERSION"
        "--build-arg" "LLAMACPP_VERSION=$LLAMACPP_VERSION"
        "--build-arg" "LLAMACPP_ROCM_ARCH=$LLAMACPP_ROCM_ARCH"
        "--build-arg" "BUILD_DATE=$build_date"
        "--build-arg" "VCS_REF=$vcs_ref"
        "--sbom=true"
        "--provenance=true"
    )

    # Add tags to build command
    build_cmd+=("${tags[@]}")

    # Add optional flags
    if [[ "$NO_CACHE" == "true" ]]; then
        build_cmd+=("--no-cache")
    fi

    if [[ "$PUSH" == "true" ]]; then
        build_cmd+=("--push")
    else
        build_cmd+=("--load")
    fi

    # Add context (current directory)
    build_cmd+=(".")

    # Display build information
    log_info "Build Configuration:"
    log_info "  Platform:         $PLATFORM"
    log_info "  Dockerfile:       $dockerfile"
    log_info "  ROCm Version:     $ROCM_VERSION"
    log_info "  llama.cpp Version: $LLAMACPP_VERSION"
    log_info "  ROCm Archs:       $LLAMACPP_ROCM_ARCH"
    log_info "  Build Date:       $build_date"
    log_info "  VCS Ref:          $vcs_ref"
    log_info "  Tags:"
    for tag in "${tags[@]}"; do
        if [[ "$tag" == "-t" ]]; then
            continue
        fi
        log_info "    - $tag"
    done
    log_info "  SBOM:             enabled"
    log_info "  Provenance:       enabled"

    log_warn "This build will take a LONG time (30+ minutes) due to:"
    log_warn "  - Large ROCm base image download"
    log_warn "  - Compilation for multiple GPU architectures"
    log_warn "  - llama.cpp build with HIP/ROCm support"

    if [[ "$PUSH" == "true" ]]; then
        log_warn "Push enabled - image will be published to Docker Hub"
        read -rp "Continue? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Build cancelled"
            exit 0
        fi
    fi

    # Execute or display command
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Command that would be executed:"
        echo "${build_cmd[*]}"
        return 0
    fi

    log_info "Starting build..."

    # Execute build command
    "${build_cmd[@]}"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_info "Build completed successfully ✓"
    else
        log_error "Build failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Scan image for vulnerabilities
scan_image() {
    # Determine default tag based on architecture
    local default_tag="latest"
    if [[ "$LLAMACPP_ROCM_ARCH" != *","* ]]; then
        default_tag="${LLAMACPP_ROCM_ARCH}-latest"
    fi

    local image="${1:-cmooreio/rocm-llama.cpp:${default_tag}}"

    log_info "Scanning image for vulnerabilities: $image"

    if command -v trivy &> /dev/null; then
        log_info "Using trivy for security scan..."
        trivy image --severity HIGH,CRITICAL "$image"
    elif command -v grype &> /dev/null; then
        log_info "Using grype for security scan..."
        grype "$image"
    else
        log_warn "No security scanner found (trivy or grype)"
        log_warn "Install with: brew install trivy"
        return 1
    fi
}

# Sign image with cosign
sign_image() {
    # Determine default tag based on architecture
    local default_tag="latest"
    if [[ "$LLAMACPP_ROCM_ARCH" != *","* ]]; then
        default_tag="${LLAMACPP_ROCM_ARCH}-latest"
    fi

    local image="${1:-cmooreio/rocm-llama.cpp:${default_tag}}"

    if ! command -v cosign &> /dev/null; then
        log_error "cosign not found. Install with: brew install cosign"
        return 1
    fi

    log_info "Signing image: $image"
    cosign sign "$image"
}

# Main execution
main() {
    log_info "ROCm llama.cpp Docker Build Script"
    log_info "==================================="

    # Parse arguments first
    parse_args "$@"

    # Load versions
    load_versions

    # Build image
    build_image

    # Optional: scan image
    if [[ "$SCAN" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        scan_image
    fi

    # Optional: sign image
    if [[ "$SIGN" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        sign_image
    fi

    log_info "All operations completed successfully ✓"
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
