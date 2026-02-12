#!/bin/bash
# Manages the lifecycle of subscriber containers to simulate churn.

start_subscribers() {
    local SUB_ID_FILE="$STATE_DIR/subscriber_ids.txt"
    touch "$SUB_ID_FILE"

    while true; do
        local subs_to_add=$(( RANDOM % (SUB_BATCH_SIZE + 1) ))
        for (( i=1; i<=subs_to_add; i++ )); do
            current_container_count=$(wc -l < "$SUB_ID_FILE")
            if [ "$current_container_count" -ge "$SUB_LIMIT" ]; then
                local id_to_remove
                id_to_remove=$(shuf -n 1 "$SUB_ID_FILE")
                docker rm -f "$id_to_remove" > /dev/null
                sed -i "/^${id_to_remove}$/d" "$SUB_ID_FILE"
            fi

            local ip_bucket=$(( (RANDOM % NUM_IPS) + 1 ))
            local route_number; route_number=$(pick_bucket_configurable "$NUM_SUBJECTS" "$SPREAD")

            local awk_logic='
            {
                if ((getline clock < "/dev/shm/global_clock") > 0) {
                    close("/dev/shm/global_clock");
                    split(clock, parts, ".");
                    now_ns = (parts[1] parts[2]);
                }
                split($0, fields, ",");
                bus_id = fields[6]
                pub_ns = fields[4];
                latency_ms = int((now_ns - pub_ns) / 1000000);
                print bus_id, ip, latency_ms, now_ns;
                fflush();
            }'

            local sub_cmd="MY_IP=\$(hostname -i); nats sub --raw 'FG.FGLA.${route_number}' --server wss://${NATS_SERVER_HOSTNAME}:443 --tlsca /data/ca.crt | awk -v ip=\"\$MY_IP\" '$awk_logic' >> /logs/${LOG_FILENAME}"

            local gateway_ip_on_mobile_net="10.10.${ip_bucket}.2"
            local new_id
            new_id=$(docker run -d \
                --network "${MOBILE_NETWORK_PREFIX}_$ip_bucket" \
                --user root \
                --cap-add NET_ADMIN \
                --add-host "$NATS_SERVER_HOSTNAME":"$LOADBALANCER_IP" \
                -v "$CA_FILE_PATH":/data/ca.crt:ro \
                -v "$(pwd)/bench_logs:/logs" \
                -v /dev/shm:/dev/shm:ro \
                natsio/nats-box:latest \
                sh -c "ip route add $TARGET_SUBNET via $gateway_ip_on_mobile_net; $sub_cmd")

            echo "$new_id" >> "$SUB_ID_FILE"
        done

        count=$(wc -l < "$SUB_ID_FILE")
        update_status 2 "${BOLD}Subscribers :${NC} ${GREEN}${count}${NC} / ${SUB_LIMIT}"

        sleep 5
    done
}