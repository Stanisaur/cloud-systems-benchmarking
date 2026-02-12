import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import json
import numpy as np
import sys

# --- SETTINGS & THEME ---
plt.style.use('seaborn-v0_8-whitegrid')
plt.rcParams['figure.figsize'] = (12, 6)
# Suppress annoying warnings about timezone-naive merges
import warnings
warnings.filterwarnings("ignore")

def load_latency_logs(filename):
    df = pd.read_csv(filename, sep=" ", header=None, 
                     names=["bus_id", "user_ip", "latency", "ts_ns"])
    # Convert nanoseconds to datetime and ensure it is naive for merging
    df['timestamp'] = pd.to_datetime(df['ts_ns'], unit='ns').dt.tz_localize(None)
    return df

def load_lean_resource_stats(filename):
    data = []
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
                    cpu_perc = (cpu_delta / sys_delta) * j['cpus'] * 100.0
                
                data.append({
                    'timestamp': pd.to_datetime(j['time']).tz_localize(None),
                    'cpu_raw': cpu_perc,
                    'mem_mb': j['mem'] / (1024 * 1024)
                })
            except (json.JSONDecodeError, KeyError, TypeError):
                continue
    return pd.DataFrame(data)

# --- SECTION 1: BASELINE ---

def plot_sysbench_results(bm_score, vm_score):
    norm_factor = vm_score / bm_score
    plt.figure(figsize=(8, 5))
    plt.bar(['Bare Metal', 'VM (GCP)'], [bm_score, vm_score], color=['#4c72b0', '#c44e52'])
    plt.title('Sysbench CPU Calibration (Normalization Baseline)')
    plt.ylabel('Events Per Second')
    plt.tight_layout()
    plt.show()
    return norm_factor

# --- SECTION 2: USER EXPERIENCE ---

def plot_ux_metrics(df):
    # 1. Percentiles (P50, P55, P95, P99)
    plt.figure()
    p_vals = [50, 55, 95, 99]
    values = np.percentile(df['latency'], p_vals)
    bars = plt.bar([f'P{p}' for p in p_vals], values, color='#8172b3')
    plt.bar_label(bars, padding=3, fmt='%.0f ms')
    plt.title('Latency Percentiles: Typical vs Worst-Case')
    plt.ylabel('ms')
    plt.show()

    # 2. CDF
    plt.figure()
    sorted_lat = np.sort(df['latency'])
    y = np.arange(len(sorted_lat)) / float(len(sorted_lat))
    plt.plot(sorted_lat, y, color='#c44e52', linewidth=2)
    plt.title('Cumulative Latency Distribution (Timing Target Proof)')
    plt.xlabel('Latency (ms)')
    plt.ylabel('Probability')
    plt.show()

    # 3. Age of Information (AoI)
    plt.figure()
    plt.plot(df['timestamp'], df['latency'], color='#64b5cd', alpha=0.3, label='Raw Latency')
    plt.plot(df['timestamp'], df['latency'].rolling(window=20).mean(), color='#4c72b0', label='20-pt Trend')
    plt.title('Age of Information (Data Freshness Over Time)')
    plt.ylabel('Latency (ms)')
    plt.legend()
    plt.show()

    # --- THE JITTER FIX ---
    # We must sort by Bus AND User IP so we track the timing of a single connection
    df = df.sort_values(['bus_id', 'user_ip', 'timestamp'])
    
    # Calculate IAT within the specific Bus-User group
    df['iat'] = df.groupby(['bus_id', 'user_ip'])['timestamp'].diff().dt.total_seconds() * 1000 
    
    # Filter: 
    # 1. Drop NaNs (first message of each stream)
    # 2. Remove IATs < 0.1ms (removes logs of the same broadcast to different users)
    # 3. (Optional) Remove massive outliers if you just want to see the "core" jitter
    jitter_data = df['iat'].dropna()
    jitter_data = jitter_data[jitter_data > 0.1] 

    # Clean jitter distribution
    plt.figure()
    if not jitter_data.empty:
        sns.histplot(jitter_data, bins=50, color='#4c72b0', kde=False, stat="density", alpha=0.6)
        sns.kdeplot(jitter_data, color='#c44e52', linewidth=2)
    plt.title('Inter-arrival Jitter Distribution (Per-Subscriber Stream)')
    plt.xlabel('Inter-arrival Delay (ms)')
    plt.show()

    # Jitter Variance Boxplot
    plt.figure(figsize=(8, 4))
    if not jitter_data.empty:
        sns.boxplot(x=jitter_data, color='#ccb974', fliersize=2)
    plt.title('Jitter Variance (Statistical Spread of Arrival Gaps)')
    plt.xlabel('Jitter (ms)')
    plt.show()
# --- SECTION 3: RESOURCES ---

def plot_resource_metrics(res_df, latency_df, norm_factor):
    # 1. Normalized CPU
    res_df['cpu_norm'] = res_df['cpu_raw'] * norm_factor
    plt.figure()
    plt.plot(res_df['timestamp'], res_df['cpu_raw'], label='VM Raw Usage', color='#c44e52', alpha=0.4, linestyle='--')
    plt.plot(res_df['timestamp'], res_df['cpu_norm'], label='Hardware Normalized (BM Equivalent)', color='#4c72b0', linewidth=2)
    plt.fill_between(res_df['timestamp'], res_df['cpu_raw'], res_df['cpu_norm'], color='gray', alpha=0.15)
    plt.title('Normalized CPU Utilization: Identifying Virtualization Tax')
    plt.ylabel('CPU %')
    plt.legend()
    plt.show()

    # 2. Memory Footprint
    plt.figure()
    plt.fill_between(res_df['timestamp'], res_df['mem_mb'], color='#55a868', alpha=0.3)
    plt.plot(res_df['timestamp'], res_df['mem_mb'], color='#55a868', linewidth=2)
    plt.title('Memory Footprint: Chungus Container Overhead')
    plt.ylabel('Memory Usage (MB)')
    plt.show()

    # 3. Noisy Neighbor (Dual Axis)
    combined = pd.merge_asof(latency_df.sort_values('timestamp'), 
                             res_df.sort_values('timestamp'), 
                             on='timestamp', direction='nearest')
    
    fig, ax1 = plt.subplots()
    ax1.set_xlabel('Time')
    ax1.set_ylabel('Latency (ms)', color='#c44e52', fontweight='bold')
    ax1.plot(combined['timestamp'], combined['latency'], color='#c44e52', alpha=0.8, label='Latency')
    
    ax2 = ax1.twinx()
    ax2.set_ylabel('CPU Usage %', color='#4c72b0', fontweight='bold')
    ax2.plot(combined['timestamp'], combined['cpu_raw'], color='#4c72b0', alpha=0.4, linestyle='--', label='CPU')
    plt.title('Resource Isolation: Latency vs. CPU (Noisy Neighbor Analysis)')
    plt.show()

# --- MAIN EXECUTION ---
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uv run main.py <latency_log> <resource_json>")
        sys.exit(1)

    # Change these to your actual sysbench numbers!
    N_FACTOR = plot_sysbench_results(bm_score=5200, vm_score=3900)

    bus_df = load_latency_logs(sys.argv[1])
    res_df = load_lean_resource_stats(sys.argv[2])

    print("Generating Section 2: UX and Latency...")
    plot_ux_metrics(bus_df)

    print("Generating Section 3: Resource Overhead...")
    plot_resource_metrics(res_df, bus_df, N_FACTOR)