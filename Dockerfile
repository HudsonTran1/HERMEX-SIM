FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for SST Core, SST Elements, and Ramulator 2
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    g++ \
    gfortran \
    git \
    graphviz \
    libopenmpi-dev \
    libtool \
    libtool-bin \
    openmpi-bin \
    openmpi-common \
    python3 \
    python3-dev \
    python3-pip \
    vim \
    && rm -rf /var/lib/apt/lists/*

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

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]