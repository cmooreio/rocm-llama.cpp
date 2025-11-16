# llama.cpp with ROCm Support

Docker image for running llama-server (llama.cpp) with AMD ROCm GPU support.

## Features

- Based on official AMD ROCm image (rocm/dev-ubuntu-24.04:7.1-complete)
- Built from official llama.cpp repository (ggml-org/llama.cpp)
- Wide AMD GPU microarchitecture support (gfx803-gfx1102)
- Includes llama-server for HTTP API access
- Includes llama-cli for command-line inference
- Security scanning with Trivy/Grype
- SBOM and provenance support
- Automated builds with comprehensive testing

## Supported AMD GPU Architectures

This image is compiled for broad AMD GPU compatibility:

- GCN 3rd Gen: gfx803 (Fiji, Polaris)
- GCN 4th Gen: gfx900 (Vega)
- GCN 5th Gen: gfx906 (Vega 7nm)
- CDNA: gfx908 (MI100)
- CDNA 2: gfx90a (MI200 series)
- CDNA 3: gfx942 (MI300 series)
- RDNA 1: gfx1010, gfx1012
- RDNA 2: gfx1030, gfx1032
- RDNA 3: gfx1100, gfx1101, gfx1102

## Quick Start

### Prerequisites

- AMD GPU with ROCm support
- Docker with ROCm support installed
- ROCm drivers installed on host

### Pull the image

```bash
docker pull cmooreio/rocm-llama.cpp:latest
```

### Run llama-server

```bash
# Download a model (example: Llama 2 7B GGUF)
mkdir -p models
wget https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf -O models/model.gguf

# Run llama-server with GPU access
docker run -d --rm \
  --name llamaserver \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --ipc=host \
  --shm-size 16G \
  -v $(pwd)/models:/data:ro \
  -p 8080:8080 \
  cmooreio/rocm-llama.cpp:latest \
  --model /data/model.gguf \
  --host 0.0.0.0 \
  --port 8080

# Test the API
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Run llama-cli

```bash
# Interactive chat
docker run -it --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --ipc=host \
  --shm-size 16G \
  -v $(pwd)/models:/data:ro \
  --entrypoint llama-cli \
  cmooreio/rocm-llama.cpp:latest \
  --model /data/model.gguf \
  --color \
  --interactive

# Single prompt
docker run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --ipc=host \
  --shm-size 16G \
  -v $(pwd)/models:/data:ro \
  --entrypoint llama-cli \
  cmooreio/rocm-llama.cpp:latest \
  --model /data/model.gguf \
  --prompt "Explain quantum computing in simple terms"
```

## Usage

### Docker Run Flags Explained

Required flags for ROCm GPU access:

- `--device=/dev/kfd` - ROCm compute device
- `--device=/dev/dri` - Direct Rendering Infrastructure
- `--group-add video` - Access to video group for GPU
- `--ipc=host` - Host IPC namespace for ROCm
- `--shm-size 16G` - Shared memory (adjust based on model size)

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `HSA_OVERRIDE_GFX_VERSION` | Override GPU architecture detection | (auto-detected) |

### Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./models` | `/data` | Model files (.gguf, .bin) |

### llama-server Options

Common llama-server options:

```bash
--model /data/model.gguf     # Path to model file
--host 0.0.0.0               # Bind to all interfaces
--port 8080                  # Server port
--ctx-size 4096              # Context size
--n-gpu-layers 35            # Number of layers to offload to GPU
--threads 8                  # CPU threads
```

### llama-cli Options

Common llama-cli options:

```bash
--model /data/model.gguf     # Path to model file
--prompt "Your prompt"       # Prompt text
--interactive                # Interactive mode
--color                      # Colorize output
--ctx-size 4096              # Context size
--n-gpu-layers 35            # GPU layer offloading
```

## Building

### Prerequisites

- Docker with buildx support
- Git
- Make (optional, for using Makefile targets)
- 50+ GB free disk space
- Patience (build takes 30-60 minutes)

### Build Commands

```bash
# Build for AMD64 platform
make build

# Build without cache
make build-nc

# Show build command without executing
make dry-run

# Run complete build pipeline
make all
```

### Using build.sh directly

```bash
# Build for AMD64
./build.sh

# Build and push
./build.sh --push

# Build with security scan
./build.sh --scan

# Dry run
./build.sh --dry-run
```

## Testing

```bash
# Run smoke tests
make test

# Run security scan
make scan

# Run comprehensive scan
make scan-all

# Generate SBOM
make sbom
```

## Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable build |
| `<version-tag>` | Specific llama.cpp release tag |

Example: `cmooreio/rocm-llama.cpp:b7079`

## Configuration

### Updating Versions

Edit `versions.env`:

```bash
# ROCm base image version
ROCM_VERSION=7.1-complete

# llama.cpp version/tag from ggml-org/llama.cpp repository
LLAMACPP_VERSION=b7079

# AMD GPU architectures to compile for
LLAMACPP_ROCM_ARCH=gfx803,gfx900,gfx906,gfx908,gfx90a,gfx942,...
```

Then rebuild:

```bash
make build
```

### Reducing Build Time

To compile for fewer GPU architectures (faster build):

1. Edit `versions.env`
2. Set `LLAMACPP_ROCM_ARCH` to only your GPU architecture
3. Rebuild

Example for MI200 series only:

```bash
LLAMACPP_ROCM_ARCH=gfx90a
```

## Security

This image includes security hardening features:

- Based on official AMD ROCm image
- Regular security updates
- SBOM (Software Bill of Materials) generation
- Image signing with cosign support
- Security scanning with Trivy/Grype
- Minimal attack surface

### Security Scanning

```bash
# Scan for HIGH and CRITICAL vulnerabilities
make scan

# Comprehensive scan (all severity levels)
make scan-all
```

### Image Signing

```bash
# Sign image with cosign
make sign

# Verify signature
make verify
```

## Development

### Project Structure

```text
.
├── Dockerfile              # Docker image definition
├── Makefile               # Build automation
├── build.sh               # Build script
├── versions.env           # Version configuration
├── .pre-commit-config.yaml # Pre-commit hooks
├── .gitignore            # Git ignore rules
├── .dockerignore         # Docker ignore rules
└── README.md             # This file
```

### Version Management

The `versions.env` file contains the single source of truth for version information.

To update to a newer llama.cpp version:

1. Visit https://github.com/ggml-org/llama.cpp/releases
2. Copy the release tag (e.g., b7079, b7080)
3. Update `LLAMACPP_VERSION` in `versions.env`
4. Rebuild: `make build`

### Pre-commit Hooks

```bash
# Install pre-commit hooks
pre-commit install

# Run hooks manually
pre-commit run --all-files
```

## CI/CD

```bash
# Run CI pipeline
make ci

# Build release
make release

# Push to registry
make push

# Full release with signing
make release-signed
```

## Troubleshooting

### GPU Not Detected

If ROCm doesn't detect your GPU:

```bash
# Check GPU is visible
docker run --rm --device=/dev/kfd --device=/dev/dri cmooreio/rocm-llama.cpp:latest rocminfo

# Override GPU architecture (if needed)
docker run ... -e HSA_OVERRIDE_GFX_VERSION=10.3.0 ...
```

### Out of Memory

Reduce GPU layer offloading:

```bash
# Reduce layers offloaded to GPU
--n-gpu-layers 20  # Instead of 35
```

Or increase shared memory:

```bash
--shm-size 32G  # Instead of 16G
```

### Build Fails

Common issues:

1. **Insufficient disk space**: Need 50+ GB free
2. **Network timeout**: ROCm image is 10+ GB, may take time to download
3. **Invalid version tag**: Ensure tag exists in ggml-org/llama.cpp repo

## Performance

### Benchmarking

```bash
# Run llama-bench
docker run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --ipc=host \
  --shm-size 16G \
  -v $(pwd)/models:/data:ro \
  --entrypoint llama-bench \
  cmooreio/rocm-llama.cpp:latest \
  -m /data/model.gguf
```

## Resources

- [llama.cpp Repository](https://github.com/ggml-org/llama.cpp)
- [llama.cpp Documentation](https://github.com/ggerganov/llama.cpp)
- [AMD ROCm Documentation](https://rocm.docs.amd.com/)
- [GGUF Models on HuggingFace](https://huggingface.co/models?search=gguf)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- Report issues at GitHub Issues
- Docker Hub: [cmooreio/rocm-llama.cpp](https://hub.docker.com/r/cmooreio/rocm-llama.cpp)

## Acknowledgments

- Built from [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov
- Based on [AMD ROCm](https://github.com/RadeonOpenCompute/ROCm) official images
- ROCm HIP backend support for AMD GPUs
