generate_certs() {
    local USER_SPECIFIED_IP=$1  # Pass the IP you want as an argument
    log_info "Generating TLS certificates for Host and IP: $USER_SPECIFIED_IP..."
    
    local CERT_DIR="./certificates"
    mkdir -p "$CERT_DIR"

    # 1. Create a SAN config with unique indices
    cat > "$CERT_DIR/san.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = nats-server

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = host.docker.internal
DNS.3 = nats.local
IP.1 = 127.0.0.1
IP.2 = 172.17.0.1
IP.3 = 10.11.0.1
IP.4 = 10.11.0.2
IP.5 = ${USER_SPECIFIED_IP}
EOF

    # 2. Generate the CA and Signed Server Cert
    openssl genrsa -out "$CERT_DIR/rootCA.key" 2048 >/dev/null 2>&1
    openssl req -x509 -new -nodes -key "$CERT_DIR/rootCA.key" -sha256 -days 365 \
        -out "$CERT_DIR/rootCA.crt" -subj "/CN=NATS-Simulation-CA" >/dev/null 2>&1

    openssl genrsa -out "$CERT_DIR/nats-server.key" 2048 >/dev/null 2>&1
    openssl req -new -key "$CERT_DIR/nats-server.key" -out "$CERT_DIR/nats-server.csr" \
        -config "$CERT_DIR/san.cnf" >/dev/null 2>&1

    openssl x509 -req -in "$CERT_DIR/nats-server.csr" -CA "$CERT_DIR/rootCA.crt" \
        -CAkey "$CERT_DIR/rootCA.key" -CAcreateserial -out "$CERT_DIR/nats-server.crt" \
        -days 365 -sha256 -extensions v3_req -extfile "$CERT_DIR/san.cnf" >/dev/null 2>&1
    
    log_success "Certificates updated with IP ${USER_SPECIFIED_IP} in $CERT_DIR"
}

setup() {
    log_info "--- Running Simplified Setup ---"
    local GATEWAY_ID_FILE="$STATE_DIR/gateway_ids.txt"

    server_network="nats_backbone"
    # 1. Create the backbone network
    log_info "Setting up backbone network for gateways"
    docker network create nats_backbone --subnet 10.11.0.0/24 >/dev/null 2>&1 || true

    if [ "$NO_SERVER" = true ]; then
        log_info "Skipping server setup (--noserver flag set)."
    else
        log_info "Setting up server"
        NATS_SERVER_HOSTNAME="10.11.0.2"
        server_id=$(docker run --rm -d --network nats_backbone --ip 10.11.0.2 -v "$(pwd)":/etc/nats -p 443:443 nats:latest -c /etc/nats/server.conf)

        echo "$server_id" > "$STATE_DIR/server.txt"
    fi

    generate_certs "$NATS_SERVER_HOSTNAME"

    # 2. start the almighty global clock
    clock_id=$(docker run -d \
    --name global_clock_master \
    --privileged \
    -v ./timing/global_time:/usr/local/bin/global_time \
    -v /dev/shm:/dev/shm \
    natsio/nats-box:latest global_time)

    echo "$clock_id" > "$STATE_DIR/global_clock_master.txt";

    log_info "2. Starting up $NUM_IPS SNAT gateway containers..."
    for (( i=1; i<=NUM_IPS; i++ ));
    do
        local mobile_subnet="10.10.${i}.0/24"
        local network_name="${MOBILE_NETWORK_PREFIX}_${i}"
        local gateway_name="snat_gateway_${i}"
        
        # This is the IP clients will use as their default gateway
        local gateway_ip_on_mobile="10.10.${i}.2"

        # Create the simulated cellular network
        docker network create --subnet="$mobile_subnet" "$network_name" >/dev/null

        # Start gateway on the backbone network
        local new_gateway_id
        new_gateway_id=$(docker run -d \
            --network "$server_network" \
            --user root --cap-add NET_ADMIN \
            --name "$gateway_name" \
            --hostname "$gateway_name" \
            nicolaka/netshoot /bin/sh -c "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; \
            tc qdisc replace dev eth0 root netem delay ${U_LATENCY}ms ${U_JITTER}ms ${CORRELATION}% loss ${U_LOSS}%; sleep infinity")
        
        echo "$new_gateway_id" >> "$GATEWAY_ID_FILE"

        # Connect the gateway to the mobile network with a SPECIFIC IP
        docker network connect --ip "$gateway_ip_on_mobile" "$network_name" "$gateway_name"
        
        # Apply download latency to the mobile interface (eth1)
        docker exec -d "$new_gateway_id" tc qdisc replace dev eth1 root netem delay ${D_LATENCY}ms ${D_JITTER}ms ${CORRELATION}% loss ${D_LOSS}% >/dev/null
    done

    log_success "--- Setup Complete ---"
}
