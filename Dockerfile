# Build arguments (must be before FROM to use in FROM statements)
ARG ROCM_VERSION=7.1-complete
ARG LLAMACPP_VERSION=b7079
ARG LLAMACPP_ROCM_ARCH=gfx803,gfx900,gfx906,gfx908,gfx90a,gfx942,gfx1010,gfx1030,gfx1032,gfx1100,gfx1101,gfx1102

# Base image from AMD ROCm
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION}

# Re-declare build arguments for use in this stage
ARG LLAMACPP_VERSION
ARG LLAMACPP_ROCM_ARCH
ARG BUILD_DATE
ARG VCS_REF

# OCI Labels
LABEL org.opencontainers.image.title="llama-server-rocm" \
      org.opencontainers.image.description="llama.cpp server with AMD ROCm GPU support" \
      org.opencontainers.image.version="${LLAMACPP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="cmooreio" \
      org.opencontainers.image.url="https://github.com/cmooreio/rocm-llama.cpp" \
      org.opencontainers.image.source="https://github.com/cmooreio/rocm-llama.cpp" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="cmooreio" \
      io.cmooreio.llama.version="${LLAMACPP_VERSION}" \
      io.cmooreio.llama.rocm_arch="${LLAMACPP_ROCM_ARCH}"

# Set working directory
WORKDIR /workspace

# Install dependencies, build llama.cpp, and cleanup in single layer to reduce image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nano \
        libcurl4-openssl-dev \
        cmake \
        git \
        ca-certificates && \
    git clone --depth 1 --branch ${LLAMACPP_VERSION} \
        https://github.com/ggml-org/llama.cpp.git /workspace/llama.cpp && \
    cd /workspace/llama.cpp && \
    HIPCXX="$(hipconfig -l)/clang" \
    HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS=${LLAMACPP_ROCM_ARCH} \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_CURL=ON && \
    cmake --build build --config Release -j$(nproc) && \
    cp build/bin/llama-* /usr/local/bin/ && \
    cp build/bin/*.so* /usr/local/lib/ && \
    echo "Validating shared libraries were copied..." && \
    ls -lh /usr/local/lib/libllama.so* /usr/local/lib/libggml*.so* /usr/local/lib/libmtmd.so* && \
    ldconfig && \
    echo "Validating ldconfig loaded libraries..." && \
    ldconfig -p | grep -E 'libllama|libggml' && \
    chmod +x /usr/local/bin/llama-* && \
    llama-server --version || llama-cli --version && \
    cd /workspace && \
    rm -rf /workspace/llama.cpp && \
    apt-get remove -y cmake git && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache && \
    mkdir -p /data && chmod 777 /data

# Set working directory back to /workspace
WORKDIR /workspace

# Expose default llama-server port
EXPOSE 8080

# Default command runs llama-server
ENTRYPOINT ["/usr/local/bin/llama-server"]
CMD ["--help"]
