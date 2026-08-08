## To get started
```git clone -b SetupDownload https://github.com/HudsonTran1/SST_Container/```

# Setting up SST and Ramulator

## Docker
1. Ensure dependencies are installed (docker, docker-compose, etc.).
2. Set mount paths (defaults to ./workspace)
3. Start container

    ```HOST_UID=$UID HOST_GID=$(id -g) docker compose up -d --build```

4. Open terminal to container

```docker exec -it sst bash```

## Ramulator
### Automated setup (experimental)

Run the setup script:

```/workspace/project/scripts/setup_ramulator.sh```

### Manual setup
1. Add/modify files

    I. Add ```sst_frontend.cpp``` to ```ramulator2/src/ramulator/frontend/impl/external_wrapper```
    
    II. Modify ```CMakeLists.txt``` to inclue ```ramulator2/impl/external_wrapper/sst_frontend.cpp```

    ```diff
        i_frontend.h

        impl/external.cpp
    +   impl/external_wrapper/sst_frontend.cpp   
        impl/memory_trace/loadstore_trace.cpp
        impl/memory_trace/readwrite_trace.cpp
        impl/memory_trace/latency_throughput_trace.cpp
    ```

    III. Add ```sedram.py``` in ```ramulator2/python/ramulator/dram```
        (Recommended to double check the included latencies, as this was generated from the .cpp file provided to me)
    
    IV. Modify ```ramulator2/src/ramulator/dram/CMakeLists.txt``` to include SeDRAM.cpp
    ```diff
        commands/VRR.h
        commands/populate.h

    +    impl/SeDRAM.cpp
        impl/DDR3.cpp
        impl/DDR4.cpp
        impl/DDR4_VRR.cpp
    ```

    V. Modify ```ramulator2/src/ramulator/controller/refresh/impl/all_bank.cpp``` to include SeDRAM
    ```diff
    -    constexpr std::array<std::pair<std::string_view, std::string_view>, 11> all_bank_refresh_scopes = {{
    +    constexpr std::array<std::pair<std::string_view, std::string_view>, 12> all_bank_refresh_scopes = {{
            {"DDR3", "Rank"},
            {"DDR4", "Rank"},
            {"DDR5", "Rank"},
    ```

    ```diff
            {"HBM2", "PseudoChannel"},
            {"HBM3", "PseudoChannel"},
            {"HBM4", "PseudoChannel"},
        +   {"SeDRAM", "BankGroup"},
        }};
    ```

2. Build ramulator

    ```mkdir -p /workspace/ramulator2/build && cd /workspace/ramulator2/build```

    ```cmake .. && make -j$(nproc)```

    ```pip install -e /workspace/ramulator2```

## SST Core

Install SST-Core (instructions from https://github.com/sstsimulator/sst-core)

```cd /workspace/sst-core```

```./autogen.sh```

```mkdir -p build && cd build```

```../configure --prefix=/workspace/sst-core/sst-core-install```

```make -j$(nproc) install```

## SST Elements

Apply the included patchfile (details on this file included in ```patchfiles/sst_elements_patch_details.md```)

```cd /workspace/sst-elements/```

```./autogen.sh```

```patch -p1 --ignore-whitespace < /workspace/patchfiles/patch_sst-elements.patch```

Run the selective build script

```/workspace/project/scripts/build_sst-elements.sh```

## Using SST

1. Compile your ramulator configuration

    ```/workspace/project/scripts/generate_ramulator_config.sh```

2. Compile your workload file. Ex:

    ```cd /workspace/project```

    ```/workspace/project/scripts/singlecore_compile.sh workloads/source/graph.c```

3. Run sst config. Ex:

    ```cd /workspace/project```

    ```sst /workspace/project/sst_configs/singlecore.py```

View statistics by examining ```/workspace/project/ramulator_native_stats.yaml``` and ```/workspace/project/sim_stats.csv```, or run

    ```python3 /workspace/project/scripts/summarize_stats.sh```

