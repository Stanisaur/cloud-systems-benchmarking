setup() {
    log_info "--- Running Simplified Setup ---"
    local GATEWAY_ID_FILE="$STATE_DIR/gateway_ids.txt"

    # 1. Create the backbone network
    docker network create nats_backbone --subnet 10.11.0.0/24 >/dev/null 2>&1 || true

    docker run -it --rm --network nats_backbone --ip 10.11.0.2 nats:latest

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
            --network nats_backbone \
            --user root --cap-add NET_ADMIN \
            --sysctl net.ipv4.ip_forward=1 \
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