#!/bin/bash
# Manages the lifecycle of publisher containers.

HEALTH_CHECK_INTERVAL=5

check_publisher_status() {
    sleep $HEALTH_CHECK_INTERVAL
    # log_info "Performing health check on new publisher containers..."
    local check_passed=true
    for container_id in "$@"; do
        if ! docker ps --filter "id=${container_id}" --filter "status=running" -q | grep -q .; then
            docker logs "$container_id" >&2
            log_error "Publisher Container ${container_id:0:12} failed to start or has exited." >&2
            log_error "Dumping its logs:" >&2
            docker logs "$container_id" >&2
            check_passed=false
        fi
    done
    if [ "$check_passed" = true ]; then
        # Just pass silently no need to say every time
        :
        # log_success "Health check passed for new publisher batch."
    else
        log_info "Exiting script due to container failure." >&2
        exit 1 # This will trigger the ERR trap in the main controller
    fi
}

start_publishers() {
    local PUB_ID_FILE="$STATE_DIR/publisher_ids.txt"
    touch "$PUB_ID_FILE"

    while true; do
        local current_container_count
        current_container_count=$(wc -l < "$PUB_ID_FILE")
        # log_info "$(date): Starting publisher batch. Current count: $current_container_count / $PUB_LIMIT."

        local new_ids_in_batch=()
        for (( i=1; i<=PUB_BATCH_SIZE; i++ )); do
            current_container_count=$(wc -l < "$PUB_ID_FILE")
            if [ "$current_container_count" -ge "$PUB_LIMIT" ]; then
                local id_to_remove
                id_to_remove=$(shuf -n 1 "$PUB_ID_FILE")
                docker rm -f "$id_to_remove" > /dev/null
                sed -i "/^${id_to_remove}$/d" "$PUB_ID_FILE"
            fi

            local route_number; route_number=$(pick_bucket_configurable "$NUM_SUBJECTS" "$SPREAD")
            local ip_bucket; ip_bucket=$(pick_bucket_configurable "$NUM_IPS" "$SPREAD")
            local subject="${SUBJECT_BASE}${route_number}"

            local publisher_loop
            printf -v publisher_loop \
            '
            while true; do
                RAND_NUM=$(od -An -N2 -tu2 /dev/urandom)
                lat=55.$((RAND_NUM %% 9000))
                RAND_NUM=$(od -An -N2 -tu2 /dev/urandom)
                lon=-4.$((RAND_NUM %% 3000)) 
                RAND_NUM=$(od -An -N2 -tu2 /dev/urandom)
                journey_ref=$((RAND_NUM %% 50))
                TIMESTAMP=$(date +%%s%%N)
                msg="[$journey_ref,$lat,$lon,$TIMESTAMP,%s]"
                echo "${msg}"
                nats --server wss://%s:443 --timeout %s pub %s "$msg" --tlsca /data/ca.crt
                sleep 1
            done
            ' \
            "$subject" "$NATS_SERVER_HOSTNAME" "$ALLOWED_TIMEOUT" "$subject"

            local gateway_ip_on_mobile_net="10.10.${ip_bucket}.2"
            local new_container_id
            new_container_id=$(docker run -d \
                --network "${MOBILE_NETWORK_PREFIX}_$ip_bucket" \
                --user root \
                --cap-add NET_ADMIN \
                --add-host "$NATS_SERVER_HOSTNAME":"$LOADBALANCER_IP" \
                -v "$CA_FILE_PATH":/data/ca.crt:ro \
                natsio/nats-box:latest \
                sh -c "ip route add $TARGET_SUBNET via $gateway_ip_on_mobile_net; $publisher_loop")

            echo "$new_container_id" >> "$PUB_ID_FILE"
            new_ids_in_batch+=("$new_container_id")
            # log_info "  -> Started Publisher (${new_container_id:0:12}) on network ${ip_bucket} -> subject ${subject}"
        done

        check_publisher_status "${new_ids_in_batch[@]}"

        count=$(wc -l < "$PUB_ID_FILE")
        update_status 1 "${BOLD}Publishers :${NC} ${GREEN}${count}${NC} / ${PUB_LIMIT}"

        sleep "$((PUB_BATCH_INTERVAL_SECONDS - HEALTH_CHECK_INTERVAL))"
    done
}