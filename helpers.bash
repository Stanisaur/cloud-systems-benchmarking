#!/bin/bash
# Contains help text, argument parsing, and validation functions.

show_help() {
cat << EOF
Usage: $(basename "$0") --creds <file> --ca <file> --lb-ip <ip> [OPTIONS]

This script runs a NATS benchmark using multiple Docker containers. Not comprehensive, see config.bash for all settings that can be set

REQUIRED ARGUMENTS:
  -a, --ca FILE         Path to the CA certificate file for TLS.
  -p, --lb-ip IP        The IP address of the NATS load balancer.

PUBLISHER OPTIONS:
  --pub-limit INT       Total number of publisher containers. (Default: $PUB_LIMIT)
  --pub-batch INT       Number of publishers to start per interval. (Default: $PUB_BATCH_SIZE)
  --interval SECS       Seconds between starting publisher batches. (Default: $PUB_BATCH_INTERVAL_SECONDS)

SUBSCRIBER OPTIONS:
  --sub-limit INT       Max number of concurrent subscriber containers. (Default: $SUB_LIMIT)
  --sub-batch INT       Max subscribers to add/remove each second. (Default: $SUB_BATCH_SIZE)

GENERAL OPTIONS:
  -n, --num-subjects INT Number of unique subjects. (Default: $NUM_SUBJECTS)
  -k, --num-ips INT     Number of unique 'gateway' IPs/networks. (Default: $NUM_IPS)
  -s, --spread SECS     Max random delay (in seconds) before a container starts publishing. (Default: $SPREAD)
  -h, --help            Display this help message and exit.
EOF
}

print_config() {
    echo "=========================== NATS Benchmark Config ==========================="
    echo "CA Certificate:        $CA_FILE_PATH"
    echo "Parent Interface:      $PARENT_INTERFACE (Subnet: $TARGET_SUBNET)"
    echo "NATS Server:           $NATS_SERVER_HOSTNAME ($LOADBALANCER_IP)"
    echo "--- Publishers --------------------------------------------------------------"
    echo "Container Limit:       $PUB_LIMIT"
    echo "Batch Size:            $PUB_BATCH_SIZE"
    echo "Batch Interval:        ${PUB_BATCH_INTERVAL_SECONDS}s"
    echo "--- Subscribers -------------------------------------------------------------"
    echo "Container Limit:       $SUB_LIMIT"
    echo "Churn Rate (per sec):  Up to $SUB_BATCH_SIZE"
    echo "--- General -----------------------------------------------------------------"
    echo "Gateway IPs/Networks:  $NUM_IPS"
    echo "Subjects:              $NUM_SUBJECTS"
    echo "============================================================================="
    sleep 3
}

# Define standard ANSI color codes (the hardcoded fallback)
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_YELLOW='\033[0;33m' # Orange/Yellow
_NC='\033[0m' # No Color (Reset)

# Check if tput is available AND if stdout is a terminal (-t 1)
if command -v tput &>/dev/null && [ -t 1 ]; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); ORANGE=$(tput setaf 3)
    BLUE=$(tput setaf 4); NC=$(tput sgr0); BOLD=$(tput bold)
else
    RED="$_RED"; GREEN="$_GREEN"; ORANGE="$_YELLOW"; BLUE="$_BLUE"; NC="$_NC"; BOLD=""
fi

log_error() { echo -e "${RED}[ERROR]:${NC} $1" >&2; if [ "${2:-1}" -ne 0 ]; then exit "${2:-1}"; fi; }
log_info() { echo -e "${BLUE}[INFO]:${NC} $1"; }
log_warning() { echo -e "${ORANGE}[WARNING]:${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]:${NC} $1"; }

init_status_display() {
    echo -e "\n\n" # Create two empty lines
    tput cuu 2 # Move cursor up 2 lines
}

update_status() {
    local line_num=$1 # 1 for publishers, 2 for subscribers
    local text="$2"
    tput sc # Save cursor position
    tput cup "$((line_num - 1))" 0 # Move to beginning of the specified line (0-indexed)
    tput el # Clear the entire line
    echo -e "$text"
    tput rc # Restore cursor position
}

check_deps() {
    for cmd in docker; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed or not on your PATH." >&2
            exit 1
        fi
    done
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -a|--ca) CA_FILE_PATH="$2"; shift 2 ;;
            -p|--lb-ip) LOADBALANCER_IP="$2"; shift 2 ;;
            --pub-limit) PUB_LIMIT="$2"; shift 2 ;;
            --pub-batch) PUB_BATCH_SIZE="$2"; shift 2 ;;
            --interval) PUB_BATCH_INTERVAL_SECONDS="$2"; shift 2 ;;
            --sub-limit) SUB_LIMIT="$2"; shift 2 ;;
            --sub-batch) SUB_BATCH_SIZE="$2"; shift 2 ;;
            -n|--num-subjects) NUM_SUBJECTS="$2"; shift 2 ;;
            -k|--num-ips) NUM_IPS="$2"; shift 2 ;;
            -s|--spread) SPREAD="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option '$1'" >&2; show_help; exit 1 ;;
        esac
    done
}

validate_inputs() {
    check_deps

    # if [ "$EUID" -ne 0 ]; then
    #     log_error "This script must be run with 'sudo' in order to do docker network creation." >&2
    #     exit 1
    # fi

    if [ -z "$CA_FILE_PATH" ] || [ -z "$LOADBALANCER_IP" ]; then
        log_error "Missing required arguments: --ca and --lb-ip." >&2
        show_help
        exit 1
    fi

    CA_FILE_PATH=$(realpath "$CA_FILE_PATH")
    if [ ! -f "$CA_FILE_PATH" ]; then log_error "CA certificate file '$CA_FILE_PATH' not found." >&2; exit 1; fi

    if ! echo "$LOADBALANCER_IP" | grep -qE "^([0-9]{1,3}\.){3}[0-9]{1,3}$"; then
        log_error "'$LOADBALANCER_IP' is not a valid IPv4 address." >&2; exit 1
    fi

    TARGET_SUBNET="10.11.0.0/24"
    log_info "Using bridge mode. Target subnet set to $TARGET_SUBNET"
}