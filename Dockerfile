FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Build arguments for host user alignment (default to 1000:1000)
ARG USER_ID=1000
ARG GROUP_ID=1000

# Install dependencies for SST Core, SST Elements, Ramulator 2, RISC-V toolchain, and Picolibc
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    g++ \
    gcc-riscv64-unknown-elf \
    gfortran \
    git \
    graphviz \
    libopenmpi-dev \
    libtool \
    libtool-bin \
    meson \
    ninja-build \
    openmpi-bin \
    openmpi-common \
    picolibc-riscv64-unknown-elf \
    python3 \
    python3-dev \
    python3-pip \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create a group and non-root user matching the host UID/GID
RUN groupadd -g ${GROUP_ID} sstgroup || true && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash sstuser || true

WORKDIR /workspace

# Entry script to clone repositories into mounted subfolders if not already present
RUN printf '#!/usr/bin/env bash\n\
set -e\n\
mkdir -p /workspace/sst-core /workspace/sst-elements /workspace/ramulator2\n\
\n\
if [ -z "$(ls -A /workspace/sst-core)" ]; then\n\
  echo "Cloning SST-Core..."\n\
  git clone https://github.com/sstsimulator/sst-core.git /workspace/sst-core\n\
fi\n\
\n\
if [ -z "$(ls -A /workspace/sst-elements)" ]; then\n\
  echo "Cloning SST-Elements..."\n\
  git clone https://github.com/sstsimulator/sst-elements.git /workspace/sst-elements\n\
fi\n\
\n\
if [ -z "$(ls -A /workspace/ramulator2)" ]; then\n\
  echo "Cloning Ramulator 2..."\n\
  git clone https://github.com/CMU-SAFARI/ramulator2.git /workspace/ramulator2\n\
fi\n\
\n\
exec "$@"\n' > /entrypoint.sh && chmod +x /entrypoint.sh

# Ensure the non-root user owns workspace and entrypoint execution path
RUN chown -R ${USER_ID}:${GROUP_ID} /workspace /entrypoint.sh

USER sstuser

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]