#!/usr/bin/env bash
set -e

# Clean up previous directory if re-running
if [ -d "HERMEX-SIM" ]; then
    echo "==> Cleaning up existing HERMEX-SIM directory..."
    rm -rf HERMEX-SIM
fi

echo "==> Cloning repository into HERMEX-SIM subfolder..."
git clone -b SetupDownload git@github.com:HudsonTran1/HERMEX-SIM.git HERMEX-SIM

cd HERMEX-SIM

echo "==> Building and starting Docker container..."
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up -d --build

echo "==> Executing setup inside container..."
docker exec -i sst bash -c '
set -e

# Force entrypoint execution so git clones run reliably
/entrypoint.sh true

# Verify Ramulator clone succeeded
if [ ! -f "/workspace/ramulator2/CMakeLists.txt" ]; then
    echo "==> Ramulator2 missing or incomplete. Cloning directly..."
    rm -rf /workspace/ramulator2/*
    git clone https://github.com/CMU-SAFARI/ramulator2.git /workspace/ramulator2
fi

# Run Ramulator setup script
/workspace/project/scripts/setup_ramulator.sh

# Build SST Core
cd /workspace/sst-core
./autogen.sh
mkdir -p build && cd build
../configure --prefix=/workspace/sst-core/sst-core-install
make -j$(nproc) install

# Patch SST Elements
cd /workspace/sst-elements
./autogen.sh
patch -p1 --ignore-whitespace < /workspace/patchfiles/patch_sst-elements.patch

# Build SST Elements
/workspace/project/scripts/build_sst-elements.sh
'

echo "==> Setup finished successfully! Opening container terminal..."
docker exec -it sst bash
