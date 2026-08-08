import ramulator

# 1. SST Frontend setup
frontend = ramulator.frontend.SST()

# 2. HBM3 Device Setup
dram = ramulator.dram.HBM3(
    org_preset="HBM3_16Gb_8hi",
    timing_preset="HBM3_6400Mbps"
)

# 3. Create controllers for 16 HBM3 Pseudo-Channels
ctrls = [
    ramulator.controller.GenericDDR(
        dram=dram,
        scheduler=ramulator.scheduler.FRFCFS(),
        refresh_manager=ramulator.refresh_manager.AllBank(),
        row_policy=ramulator.row_policy.Open(),
        addr_mapper=ramulator.addr_mapper.RoBaRaCoCh()
    )
    for _ in range(16)
]

# 4. Memory System Interleave Setup
mem = ramulator.memory_system.GenericDRAM(
    clock_ratio=1,
    controllers=ctrls,
    channel_mapper=ramulator.channel_mapper.CacheLineInterleave()
)

# 5. Simulation Setup
sim = ramulator.Simulation(
    frontend=frontend, 
    memory_system=mem
)