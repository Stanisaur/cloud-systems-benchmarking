#!/bin/bash
# Default and static configuration values for the NATS benchmark.

# --- Default Modifiable Configuration ---
PUB_LIMIT=200
PUB_BATCH_SIZE=20
PUB_BATCH_INTERVAL_SECONDS=60
SUB_LIMIT=850
SUB_BATCH_SIZE=30
NUM_SUBJECTS=50
NUM_IPS=35
SPREAD=15
ALLOWED_TIMEOUT=20s #seconds, need this with high volume cause host machine struggles to assign networking stuff to container
# Attempt to auto-detect the default network interface.
PARENT_INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1 || echo "")
LOG_FILENAME="latency_$(date +%Y%m%d_%H%M%S).log"
NO_SERVER=false

# --- Paths (to be set by arguments) ---
BUS_CREDS_FILE_PATH=""
CLIENT_CREDS_FILE_PATH=""
CA_FILE_PATH=""
LOADBALANCER_IP=""
TARGET_SUBNET="" # Will be derived in helpers.sh
NATS_SERVER_HOSTNAME="nats.local"

# --- Static Configuration ---
readonly SUBJECT_BASE="FG.FGLA."
readonly CLIENT_CREDS_LINK="https://bus-infra-demo.com/client.creds"
readonly BUS_CREDS_LINK="https://bus-infra-demo.com/client.creds"
readonly MOBILE_NETWORK_PREFIX="mobile_net"
# --- Latency Metrics ---
readonly U_LATENCY=120; readonly U_JITTER=25; readonly U_LOSS=1.5;
readonly D_LATENCY=100; readonly D_JITTER=15; readonly D_LOSS=0.5;
readonly CORRELATION=0.25;
