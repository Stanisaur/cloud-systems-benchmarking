#!/bin/bash
# Main controller script for the NATS benchmark.
# It sources component scripts and manages the main execution flow.

set -uo pipefail

# --- SCRIPT DIR and SOURCING ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source all component scripts in order
source "${SCRIPT_DIR}/config.bash"
source "${SCRIPT_DIR}/helpers.bash"
source "${SCRIPT_DIR}/cleanup.bash"
source "${SCRIPT_DIR}/setup.bash"
source "${SCRIPT_DIR}/run_publishers.bash"
source "${SCRIPT_DIR}/run_subscribers.bash"
source "${SCRIPT_DIR}/stats_functions.bash"

# --- STATE MANAGEMENT ---
# Create a temporary directory to store state like container IDs
STATE_DIR=$(mktemp -d)
# Export it so it's available in sourced scripts or subshells
export STATE_DIR

# --- TRAP SETUP ---
# Set up a trap to call the cleanup function on script exit, interrupt, or error
trap cleanup SIGINT SIGTERM ERR

# --- MAIN EXECUTION ---

# 1. Parse arguments passed to the script
parse_args "$@"


# 2. Validate inputs and environment
validate_inputs

# 3. Print the configuration and wait a moment
print_config

# 4. Run the setup process
setup

# 5. Run publishers and subscribers in the background
echo "--- Launching Publishers and Subscribers ---"
init_status_display
start_publishers &
start_subscribers &

# Wait for background jobs to finish. Since they are infinite loops,
# this keeps the main script alive so the trap works correctly.
echo " Benchmark is running. Press Ctrl+C to stop and cleanup."
wait