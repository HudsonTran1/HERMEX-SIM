#!/usr/bin/env python3
import sst
import os

# ------------------------------------------------------------------------------
# Configuration & Constants
# ------------------------------------------------------------------------------
NUM_CORES = 8
EXE_PATH = "./workload_files/elf/workload_8_core.elf"
CONFIG_PATH = "ramulator_config.yaml"

if not os.path.exists(EXE_PATH):
    raise FileNotFoundError(f"Workload binary not found at {EXE_PATH}")
if not os.path.exists(CONFIG_PATH):
    raise FileNotFoundError(f"Ramulator 2 configuration not found at {CONFIG_PATH}")

MEM_SIZE_BYTES = 8 * 1024 * 1024 * 1024  # 8GiB
ADDR_RANGE_END = MEM_SIZE_BYTES - 1

sst.setStatisticOutput("sst.statOutputCSV", {
    "filepath": "sim_stats.csv",
    "separator": ","
})
sst.setStatisticLoadLevel(10)

# ------------------------------------------------------------------------------
# 1. OS & Central MMU Setup
# ------------------------------------------------------------------------------
os_node = sst.Component("os", "vanadis.VanadisNodeOS")

os_params = {
    "cores": NUM_CORES,
    "hardwareThreadCount": 1,
    "physMemSize": "8GiB",
    "page_size": 4096,
    "useMMU": True,
    "processDebugLevel": 0,
    "dbgLevel": 0,
    "dbgMask": 0,
}

# processN maps to coreN implicitly by index order - no initial_core param exists
for i in range(NUM_CORES):
    os_params[f"process{i}.exe"] = EXE_PATH
    os_params[f"process{i}.arg0"] = EXE_PATH
    os_params[f"process{i}.arg1"] = str(i)
    os_params[f"process{i}.argc"] = 2

os_node.addParams(os_params)

os_mem_if = os_node.setSubComponent("mem_interface", "memHierarchy.standardInterface")
os_mem_if.addParams({
    "cache_line_size": 64,
    "max_bytes_per_request": 64
})

os_mmu = os_node.setSubComponent("mmu", "mmu.simpleMMU")
os_mmu.addParams({
    "num_cores": NUM_CORES,
    "num_threads": 1,
    "page_size": 4096,
    "debug_level": 0
})

# ------------------------------------------------------------------------------
# 2. Bus
# ------------------------------------------------------------------------------
bus = sst.Component("memory_bus", "memHierarchy.Bus")
bus.addParams({
    "bus_frequency": "1.2GHz",
    "bus_delay": "100ps",
    "broadcast": 0
})
bus.enableAllStatistics()

bus_port_idx = 0

link_os_mem_bus = sst.Link("link_os_mem_bus")
link_os_mem_bus.connect(
    (os_mem_if, "lowlink", "100ps"),
    (bus, f"highlink{bus_port_idx}", "100ps")
)
bus_port_idx += 1

# ------------------------------------------------------------------------------
# 3. Per-Core Construction (no L1/L2 - TLBs go straight to bus)
# ------------------------------------------------------------------------------
for i in range(NUM_CORES):
    core = sst.Component(f"node{i}", "vanadis.core")
    core.addParams({
        "core_id": i,
        "clock": "2.4GHz",
        "hardware_threads": 1,
        "verbose": 8,
        "debug_level": 0,
        "debug_output_file": f"vanadis_core_{i}.log"
    })
    core.enableAllStatistics()

    decoder = core.setSubComponent("decoder", "vanadis.VanadisRISCV64Decoder", 0)
    os_handler = decoder.setSubComponent("os_handler", "vanadis.VanadisRISCV64OSHandler")

    branch_unit = decoder.setSubComponent("branch_unit", "vanadis.VanadisBasicBranchUnit")
    branch_unit.addParams({"branch_entries": 2048})
    branch_unit.enableAllStatistics()

    icache_if = core.setSubComponent("mem_interface_inst", "memHierarchy.standardInterface", 0)
    icache_if.addParams({
        "cache_line_size": 64,
        "max_bytes_per_request": 64
    })

    lsq = core.setSubComponent("lsq", "vanadis.VanadisBasicLoadStoreQueue", 0)
    dcache_if = lsq.setSubComponent("memory_interface", "memHierarchy.standardInterface")
    dcache_if.addParams({
        "cache_line_size": 64,
        "max_bytes_per_request": 64
    })
    lsq.enableAllStatistics()

    itlbWrapper = sst.Component(f"itlb_wrapper_c{i}", "mmu.tlb_wrapper")
    itlbWrapper.addParams({"exe": True, "page_size": 4096})
    itlb = itlbWrapper.setSubComponent("tlb", "mmu.simpleTLB")
    itlb.enableAllStatistics()

    dtlbWrapper = sst.Component(f"dtlb_wrapper_c{i}", "mmu.tlb_wrapper")
    dtlbWrapper.addParams({"exe": False, "page_size": 4096})
    dtlb = dtlbWrapper.setSubComponent("tlb", "mmu.simpleTLB")
    dtlb.enableAllStatistics()

    link_core_os = sst.Link(f"link_core{i}_os")
    link_core_os.connect(
        (os_node, f"core{i}", "100ps"),
        (core, "os_link", "100ps")
    )

    link_mmu_itlb = sst.Link(f"link_mmu_itlb_c{i}")
    link_mmu_itlb.connect(
        (os_mmu, f"core{i}.itlb", "1ns"),
        (itlb, "mmu", "1ns")
    )

    link_mmu_dtlb = sst.Link(f"link_mmu_dtlb_c{i}")
    link_mmu_dtlb.connect(
        (os_mmu, f"core{i}.dtlb", "1ns"),
        (dtlb, "mmu", "1ns")
    )

    link_cpu_itlb = sst.Link(f"link_cpu_itlb_c{i}")
    link_cpu_itlb.connect(
        (icache_if, "lowlink", "100ps"),
        (itlbWrapper, "highlink", "100ps")
    )

    link_cpu_dtlb = sst.Link(f"link_cpu_dtlb_c{i}")
    link_cpu_dtlb.connect(
        (dcache_if, "lowlink", "100ps"),
        (dtlbWrapper, "highlink", "100ps")
    )

    link_itlb_to_bus = sst.Link(f"link_itlb_to_bus_c{i}")
    link_itlb_to_bus.connect(
        (itlbWrapper, "lowlink", "100ps"),
        (bus, f"highlink{bus_port_idx}", "100ps")
    )
    bus_port_idx += 1

    link_dtlb_to_bus = sst.Link(f"link_dtlb_to_bus_c{i}")
    link_dtlb_to_bus.connect(
        (dtlbWrapper, "lowlink", "100ps"),
        (bus, f"highlink{bus_port_idx}", "100ps")
    )
    bus_port_idx += 1

# ------------------------------------------------------------------------------
# 4. Directory & Memory Controller
# ------------------------------------------------------------------------------
directory = sst.Component("memory_directory", "memHierarchy.DirectoryController")
directory.addParams({
    "clock": "1.2GHz",
    "coherence_protocol": "MESI",
    "entry_cache_size": 32768,
    "addr_range_end": ADDR_RANGE_END,
    "addr_range_start": 0
})
directory.enableAllStatistics()

memctrl = sst.Component("memory_controller", "memHierarchy.MemController")
memctrl.addParams({
    "clock": "1.2GHz",
    "addr_range_end": ADDR_RANGE_END,
    "cache_line_size": 64
})
memctrl.enableAllStatistics({"type": "sst.AccumulatorStatistic"})

backend_conv = memctrl.setSubComponent("backendConvertor", "memHierarchy.simpleMembackendConvertor")
backend_conv.addParams({
    "request_width": 64,
    "cache_line_size": 64
})
backend_conv.enableAllStatistics({"type": "sst.AccumulatorStatistic"})

backend = memctrl.setSubComponent("backend", "memHierarchy.ramulator2")
backend.addParams({
    "configFile": CONFIG_PATH,
    "clock": "1.2GHz",
    "mem_size": "8GiB",
    "cache_line_size": 64,
    "max_bytes_per_request": 64
})
backend.enableAllStatistics({"type": "sst.AccumulatorStatistic"})

link_bus_to_dir = sst.Link("link_bus_to_dir")
link_bus_to_dir.connect(
    (bus, "lowlink0", "100ps"),
    (directory, "highlink", "100ps")
)

link_dir_to_mem = sst.Link("link_dir_to_mem")
link_dir_to_mem.connect(
    (directory, "lowlink", "100ps"),
    (memctrl, "highlink", "100ps")
)

print(f"[SST] Direct memory bypass multicore initialized ({NUM_CORES} cores). Running simulation...")