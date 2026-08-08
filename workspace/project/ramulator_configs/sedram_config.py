import ramulator

# 1. SST Frontend setup (removed unsupported clock_ratio argument)
frontend = ramulator.frontend.SST()

# 2. SeDRAM Device Setup (using the custom preset defined in your SeDRAM.cpp)
dram = ramulator.dram.SeDRAM(
    org_preset="SeDRAM_8Gb",
    timing_preset="SeDRAM_4Gbps"
)

# 3. Memory Controller configured for SeDRAM
ctrl = ramulator.controller.GenericDDR(
    dram=dram,
    scheduler=ramulator.scheduler.FRFCFS(),
    refresh_manager=ramulator.refresh_manager.AllBank(),
    row_policy=ramulator.row_policy.Open(),
    addr_mapper=ramulator.addr_mapper.RoBaRaCoCh()
)

# 4. Memory System Interleave Setup
mem = ramulator.memory_system.GenericDRAM(
    clock_ratio=1,
    controllers=[ctrl],
    channel_mapper=ramulator.channel_mapper.CacheLineInterleave()
)

# 5. Build Simulation
sim = ramulator.Simulation(
    frontend=frontend,
    memory_system=mem
)