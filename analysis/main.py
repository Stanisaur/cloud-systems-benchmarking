import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import json
import numpy as np
import sys
import warnings

# --- SETTINGS & THEME ---
plt.style.use('seaborn-v0_8-whitegrid')
plt.rcParams['figure.figsize'] = (12, 6)
# Suppress annoying warnings
warnings.filterwarnings("ignore")

# --- CONFIGURATION ---
# Colors for consistent plotting
COLOR_BM = '#4c72b0'  # Blue (Bare Metal)
COLOR_VM = '#c44e52'  # Red (VM/GCP)

def load_latency_logs(filename, label):
    """
    Loads latency logs, filters out negative values, and tags them with an environment label.
    """
    try:
        df = pd.read_csv(filename, sep=" ", header=None, 
                         names=["bus_id", "user_ip", "latency", "ts_ns"])
        
        # 1. Convert timestamp
        df['timestamp'] = pd.to_datetime(df['ts_ns'], unit='ns').dt.tz_localize(None)
        
        # 2. FILTER: Remove negative latency values (sanitization)
        initial_count = len(df)
        df = df[df['latency'] >= 0]
        dropped_count = initial_count - len(df)
        if dropped_count > 0:
            print(f"[{label}] Dropped {dropped_count} records with negative latency.")

        # 3. Add label
        df['env'] = label
        return df
    except Exception as e:
        print(f"Error loading {filename}: {e}")
        sys.exit(1)

def load_lean_resource_stats(filename, label):
    """
    Loads resource usage logs (CPU/Mem) and tags them.
    """
    data = []
    try:
        with open(filename, 'r') as f:
            for line in f:
                try:
                    j = json.loads(line)
                    required = ['cpu_total', 'pre_cpu', 'sys_total', 'pre_sys', 'mem', 'cpus', 'time']
                    if not all(k in j and j[k] is not None for k in required):
                        continue

                    cpu_delta = j['cpu_total'] - j['pre_cpu']
                    sys_delta = j['sys_total'] - j['pre_sys']
                    
                    cpu_perc = 0.0
                    if sys_delta > 0:
                        # Calculate CPU percentage based on total system ticks
                        cpu_perc = (cpu_delta / sys_delta) * j['cpus'] * 100.0
                    
                    data.append({
                        'timestamp': pd.to_datetime(j['time']).tz_localize(None),
                        'cpu_raw': cpu_perc,
                        'mem_mb': j['mem'] / (1024 * 1024),
                        'env': label
                    })
                except (json.JSONDecodeError, KeyError, TypeError):
                    continue
    except FileNotFoundError:
        print(f"Error: File {filename} not found.")
        sys.exit(1)
        
    return pd.DataFrame(data)

def align_time(df):
    """
    Adds an 'elapsed_sec' column starting at 0. 
    Allows comparing two tests that ran at different actual times.
    """
    if not df.empty:
        start_time = df['timestamp'].min()
        df['elapsed_sec'] = (df['timestamp'] - start_time).dt.total_seconds()
    return df

# --- SECTION 1: BASELINE ---

def plot_sysbench_results(bm_score, vm_score):
    """
    Visualizes the raw CPU power difference to establish a normalization factor.
    """
    norm_factor = vm_score / bm_score
    print(f"\n--- Sysbench Normalization ---")
    print(f"Bare Metal Score: {bm_score}")
    print(f"VM Score:         {vm_score}")
    print(f"Normalization Factor (VM/BM): {norm_factor:.4f}")
    
    plt.figure(figsize=(8, 5))
    bars = plt.bar(['Bare Metal', 'VM (GCP)'], [bm_score, vm_score], color=[COLOR_BM, COLOR_VM])
    plt.bar_label(bars, fmt='%.0f')
    plt.title(f'Sysbench CPU Score (Factor: {norm_factor:.2f})')
    plt.ylabel('Events Per Second')
    plt.tight_layout()
    plt.show()
    return norm_factor

# --- SECTION 2: USER EXPERIENCE ---

def compare_ux_metrics(df_bm, df_vm):
    print("\n--- Generating UX Metrics ---")
    
    # 1. Percentiles Comparison (Side-by-Side Bars)
    plt.figure()
    p_vals = [50, 95, 99]
    stats = []
    
    for label, df in [('Bare Metal', df_bm), ('VM', df_vm)]:
        vals = np.percentile(df['latency'], p_vals)
        for p, v in zip(p_vals, vals):
            stats.append({'Environment': label, 'Percentile': f'P{p}', 'Latency (ms)': v})
    
    stat_df = pd.DataFrame(stats)
    sns.barplot(data=stat_df, x='Percentile', y='Latency (ms)', hue='Environment', 
                palette={'Bare Metal': COLOR_BM, 'VM': COLOR_VM})
    plt.title('Latency Percentiles: Bare Metal vs VM')
    plt.show()

    # 2. CDF Comparison
    plt.figure()
    for df, color, label in [(df_bm, COLOR_BM, 'Bare Metal'), (df_vm, COLOR_VM, 'VM')]:
        sorted_lat = np.sort(df['latency'])
        y = np.arange(len(sorted_lat)) / float(len(sorted_lat))
        plt.plot(sorted_lat, y, color=color, linewidth=2, label=label)
    
    plt.title('Cumulative Latency Distribution (CDF)')
    plt.xlabel('Latency (ms)')
    plt.ylabel('Probability')
    plt.legend()
    plt.grid(True, which='both', linestyle='--', linewidth=0.5)
    plt.show()

    # 3. Age of Information (AoI) Trend
    # Using 'elapsed_sec' to overlay them perfectly
    plt.figure()
    for df, color, label in [(df_bm, COLOR_BM, 'Bare Metal'), (df_vm, COLOR_VM, 'VM')]:
        # Sort by time to ensure rolling works correctly
        df = df.sort_values('elapsed_sec')
        # Rolling mean of 50 points for a smoother trend line
        plt.plot(df['elapsed_sec'], df['latency'].rolling(50).mean(), 
                 color=color, label=label, alpha=0.9, linewidth=1.5)
        
    plt.title('Latency Trend Over Time (Age of Information)')
    plt.xlabel('Test Duration (seconds)')
    plt.ylabel('Latency Moving Average (ms)')
    plt.legend()
    plt.show()

    # 4. Jitter Comparison (KDE)
    plt.figure()
    for df, color, label in [(df_bm, COLOR_BM, 'Bare Metal'), (df_vm, COLOR_VM, 'VM')]:
        # Sort by Stream (Bus+User) then Time
        temp = df.sort_values(['bus_id', 'user_ip', 'timestamp'])
        # Calculate Inter-Arrival Time (IAT)
        temp['iat'] = temp.groupby(['bus_id', 'user_ip'])['timestamp'].diff().dt.total_seconds() * 1000 
        
        # Filter NaNs and unrealistic jumps (<0.1ms)
        jitter_data = temp['iat'].dropna()
        jitter_data = jitter_data[jitter_data > 0.1] 
        
        sns.kdeplot(jitter_data, color=color, fill=True, alpha=0.2, label=label, linewidth=2)

    plt.title('Jitter Distribution (Stability)')
    plt.xlabel('Inter-arrival Delay (ms)')
    plt.xlim(0, 500) # Limit x-axis to focus on the core distribution
    plt.legend()
    plt.show()

# --- SECTION 3: RESOURCES ---

def compare_resource_metrics(res_bm, res_vm, norm_factor):
    print("\n--- Generating Resource Metrics ---")
    
    # 1. CPU Normalization
    # We multiply VM CPU by the norm_factor to see what it "would have cost" on Bare Metal
    res_vm['cpu_norm'] = res_vm['cpu_raw'] * norm_factor
    
    plt.figure()
    plt.plot(res_bm['elapsed_sec'], res_bm['cpu_raw'], label='Bare Metal (Actual)', color=COLOR_BM)
    plt.plot(res_vm['elapsed_sec'], res_vm['cpu_norm'], label=f'VM (Normalized x{norm_factor:.2f})', color=COLOR_VM, linestyle='--')
    
    plt.title('CPU Utilization: Bare Metal vs. Normalized VM')
    plt.xlabel('Test Duration (seconds)')
    plt.ylabel('CPU % (Normalized to Hardware)')
    plt.legend()
    plt.show()

    # 2. Memory Footprint
    plt.figure()
    plt.plot(res_bm['elapsed_sec'], res_bm['mem_mb'], label='Bare Metal', color=COLOR_BM)
    plt.plot(res_vm['elapsed_sec'], res_vm['mem_mb'], label='VM', color=COLOR_VM)
    plt.title('Memory Usage Comparison')
    plt.ylabel('Memory (MB)')
    plt.xlabel('Test Duration (seconds)')
    plt.legend()
    plt.show()

# --- MAIN EXECUTION ---
if __name__ == "__main__":
    # Expecting 4 arguments now
    if len(sys.argv) < 5:
        print("Usage: uv run main.py <lat_bm> <res_bm> <lat_vm> <res_vm>")
        print("Example: uv run main.py bm_lat.log bm_res.json vm_lat.log vm_res.json")
        sys.exit(1)

    file_lat_bm = sys.argv[1]
    file_res_bm = sys.argv[2]
    file_lat_vm = sys.argv[3]
    file_res_vm = sys.argv[4]

    # --- CONFIGURATION: SYSBENCH ---
    # Edit these values based on your `sysbench cpu run` results
    BM_EVENTS_PER_SEC = 4500.5
    VM_EVENTS_PER_SEC = 4088.4
    
    # 1. Calculate Normalization
    N_FACTOR = plot_sysbench_results(bm_score=BM_EVENTS_PER_SEC, vm_score=VM_EVENTS_PER_SEC)

    # 2. Load Data (Negative Latency Filter applied automatically)
    print("Loading Bare Metal Data...")
    lat_bm = align_time(load_latency_logs(file_lat_bm, 'Bare Metal'))
    res_bm = align_time(load_lean_resource_stats(file_res_bm, 'Bare Metal'))

    print("Loading VM Data...")
    lat_vm = align_time(load_latency_logs(file_lat_vm, 'VM'))
    res_vm = align_time(load_lean_resource_stats(file_res_vm, 'VM'))

    # 3. Generate Plots
    compare_ux_metrics(lat_bm, lat_vm)
    compare_resource_metrics(res_bm, res_vm, N_FACTOR)