#!/usr/bin/env python3
import sst
import os

# ------------------------------------------------------------------------------
# Constants & Paths
# ------------------------------------------------------------------------------
EXE_PATH = "workload_files/elf/workload_1_core.elf"
CONFIG_PATH = "ramulator_config.yaml"

if not os.path.exists(EXE_PATH):
    raise FileNotFoundError(f"Workload binary not found at {EXE_PATH}")
if not os.path.exists(CONFIG_PATH):
    raise FileNotFoundError(f"Ramulator 2 configuration not found at {CONFIG_PATH}")

MEM_SIZE_BYTES = 8 * 1024 * 1024 * 1024  # 8GiB
ADDR_RANGE_END = MEM_SIZE_BYTES - 1

# ------------------------------------------------------------------------------
# 0. Global Statistics Configuration
# ------------------------------------------------------------------------------
sst.setStatisticOutput("sst.statOutputCSV", {
    "filepath": "sim_stats.csv",
    "separator": ","
})
sst.setStatisticLoadLevel(10)

# ------------------------------------------------------------------------------
# 1. Operating System & Central Page Table (MMU) Setup
# ------------------------------------------------------------------------------
os_node = sst.Component("os", "vanadis.VanadisNodeOS")
os_node.addParams({
    "cores": 1,
    "hardwareThreadCount": 1,
    "physMemSize": "8GiB",
    "heap_size": "2GiB",
    "stack_size": "16MiB",
    "heap_start": "0x40000000",
    "stack_start": "0x7FFFF000",
    "useMMU": True,
    "process0.exe": EXE_PATH,
    "process0.arg0": "workload.elf",
    "process0.argc": 1,
    "verbose": 0
})

os_mem_if = os_node.setSubComponent("mem_interface", "memHierarchy.standardInterface")
os_mem_if.addParams({
    "cache_line_size": 64,
    "max_bytes_per_request": 64
})

os_mmu = os_node.setSubComponent("mmu", "mmu.simpleMMU")
os_mmu.addParams({
    "num_cores": 1,
    "num_threads": 1,
    "page_size": 4096,
    "debug_level": 0
})

# ------------------------------------------------------------------------------
# 2. CPU Core, Decoder & Memory Interfaces
# ------------------------------------------------------------------------------
core = sst.Component("node0", "vanadis.core")
core.addParams({
    "clock": "2.4GHz",
    "hardware_threads": 1,
    "verbose": 0
})
core.enableAllStatistics()

decoder = core.setSubComponent("decoder", "vanadis.VanadisRISCV64Decoder", 0)
os_handler = decoder.setSubComponent("os_handler", "vanadis.VanadisRISCV64OSHandler")

branch_unit = decoder.setSubComponent("branch_unit", "vanadis.VanadisBasicBranchUnit")
branch_unit.addParams({
    "branch_entries": 2048
})
branch_unit.enableAllStatistics()

# Core Instruction Standard Interface
icache_if = core.setSubComponent("mem_interface_inst", "memHierarchy.standardInterface", 0)
icache_if.addParams({
    "cache_line_size": 64,
    "max_bytes_per_request": 64
})

# Core Data Standard Interface via LSQ
lsq = core.setSubComponent("lsq", "vanadis.VanadisBasicLoadStoreQueue", 0)
dcache_if = lsq.setSubComponent("memory_interface", "memHierarchy.standardInterface")
dcache_if.addParams({
    "cache_line_size": 64,
    "max_bytes_per_request": 64
})
lsq.enableAllStatistics()

# Setup translation wrappers (TLBs)
itlbWrapper = sst.Component("itlb_wrapper", "mmu.tlb_wrapper")
itlbWrapper.addParams({"exe": True})
itlb = itlbWrapper.setSubComponent("tlb", "mmu.simpleTLB")
itlb.enableAllStatistics()

dtlbWrapper = sst.Component("dtlb_wrapper", "mmu.tlb_wrapper")
dtlbWrapper.addParams({"exe": False})
dtlb = dtlbWrapper.setSubComponent("tlb", "mmu.simpleTLB")
dtlb.enableAllStatistics()

# ------------------------------------------------------------------------------
# 3. Interconnect Bus (Configured to simulate ultra-fast Hybrid Bonding)
# ------------------------------------------------------------------------------
bus = sst.Component("memory_bus", "memHierarchy.Bus")
bus.addParams({
    "bus_frequency": "1.2GHz",
    # Cu-Cu hybrid bonds have sub-nanosecond travel times (<10-20ps physical delay)
    "bus_delay": "10ps",
    # Set high fanout/width limits if supported by your memHierarchy version
    "broadcast": 0 
})
bus.enableAllStatistics()

# ------------------------------------------------------------------------------
# 4. Directory & Memory Controller Setup
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

# ------------------------------------------------------------------------------
# 5. Direct Interconnect Links (Updated with 3D Hybrid Bond Latency)
# ------------------------------------------------------------------------------
# Physical distance across face-to-face (F2F) or face-to-back (F2B) hybrid bonds 
# is measured in micrometers, yielding ~10ps to 25ps wire delays.

link_core_os = sst.Link("link_core_os")
link_core_os.connect((os_node, "core0", "10ps"), (core, "os_link", "10ps"))

link_mmu_itlb = sst.Link("link_mmu_itlb")
link_mmu_itlb.connect((os_mmu, "core0.itlb", "50ps"), (itlb, "mmu", "50ps"))

link_mmu_dtlb = sst.Link("link_mmu_dtlb")
link_mmu_dtlb.connect((os_mmu, "core0.dtlb", "50ps"), (dtlb, "mmu", "50ps"))

# Core interfaces -> TLB wrappers
link_cpu_itlb = sst.Link("link_cpu_itlb")
link_cpu_itlb.connect((icache_if, "lowlink", "10ps"), (itlbWrapper, "highlink", "10ps"))

link_cpu_dtlb = sst.Link("link_cpu_dtlb")
link_cpu_dtlb.connect((dcache_if, "lowlink", "10ps"), (dtlbWrapper, "highlink", "10ps"))

# TLB wrappers -> Bus
link_itlb_to_bus = sst.Link("link_itlb_to_bus")
link_itlb_to_bus.connect((itlbWrapper, "lowlink", "10ps"), (bus, "highlink0", "10ps"))

link_dtlb_to_bus = sst.Link("link_dtlb_to_bus")
link_dtlb_to_bus.connect((dtlbWrapper, "lowlink", "10ps"), (bus, "highlink1", "10ps"))

# OS Memory Interface -> Bus
link_os_mem_bus = sst.Link("link_os_mem_bus")
link_os_mem_bus.connect((os_mem_if, "lowlink", "10ps"), (bus, "highlink2", "10ps"))

# Bus -> Directory -> Memory Controller
link_bus_to_dir = sst.Link("link_bus_to_dir")
link_bus_to_dir.connect((bus, "lowlink0", "10ps"), (directory, "highlink", "10ps"))

link_dir_to_mem = sst.Link("link_dir_to_mem")
link_dir_to_mem.connect((directory, "lowlink", "10ps"), (memctrl, "highlink", "10ps"))

print("[SST] Direct memory bypass initialized. Running simulation...")