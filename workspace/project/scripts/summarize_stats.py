#!/usr/bin/env python3
import csv
import os

def generate_summary():
    # Resolve paths dynamically based on where the script is located
    # This assumes the script is in ./scripts/ and the stats are in the root directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    
    csv_file = os.path.join(parent_dir, "sim_stats.csv")
    yaml_file = os.path.join(parent_dir, "ramulator_native_stats.yaml")

    # Fallbacks just in case the script is run directly in the root directory
    if not os.path.exists(csv_file) and os.path.exists("sim_stats.csv"):
        csv_file = "sim_stats.csv"
    if not os.path.exists(yaml_file):
        if os.path.exists("../ramulator_native_stats.yaml"):
            yaml_file = "../ramulator_native_stats.yaml"
        elif os.path.exists("ramulator_native_stats.yaml"):
            yaml_file = "ramulator_native_stats.yaml"

    if not os.path.exists(csv_file):
        print(f"Error: {csv_file} not found. Ensure SST ran with CSV statistic output.")
        return

    print("=" * 50)
    print("        SST + RAMULATOR SIMULATION SUMMARY        ")
    print("=" * 50)

    # --------------------------------------------------------------------------
    # 1. Parse SST CSV Stats
    # --------------------------------------------------------------------------
    with open(csv_file, mode='r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header is None:
            print("Empty CSV file.")
            return

        print(f"[Detected columns] {header}")
        print("-" * 50)

        def col_idx(*candidates):
            for name in candidates:
                if name in header:
                    return header.index(name)
            return None

        name_idx = col_idx("ComponentName")
        stat_idx = col_idx("StatisticName")
        val_idx = col_idx("Sum.u64", "Sum.f64", "Sum", "Value")

        if name_idx is None or stat_idx is None or val_idx is None:
            print("Could not find expected columns. Please inspect [Detected columns] above")
            print("and adjust col_idx(...) candidates in this script to match.")
        else:
            for row in reader:
                if len(row) <= max(name_idx, stat_idx, val_idx):
                    continue
                comp_name, stat_name, val = row[name_idx], row[stat_idx], row[val_idx]
                print(f"[{comp_name}] {stat_name}: {val}")

    print("=" * 50)

    # --------------------------------------------------------------------------
    # 2. Append Ramulator YAML Stats
    # --------------------------------------------------------------------------
    if os.path.exists(yaml_file):
        print(f"        RAMULATOR NATIVE STATS ({os.path.basename(yaml_file)})        ")
        print("=" * 50)
        with open(yaml_file, 'r') as yf:
            print(yf.read().strip())
        print("=" * 50)
    else:
        print(f"Warning: {yaml_file} not found. Skipping Ramulator stats.")

if __name__ == "__main__":
    generate_summary()