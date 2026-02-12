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
EOF

    # 2. Generate the CA and Signed Server Cert
    cat > "$CERT_DIR/rootCA.key" <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDLuGBgO5fidsO4
hJYHKdJqXhj13SKlk9rFjP70Iwf5HkCUJTi+829syUia8aR/EZAlGemYExm8MshK
0meACT2QB1y/ve+Haiku3ihxZzwWl4HTjcosHII4lVFOEAbddpVfs7V9VhEvhwpu
hAvsLt5QNLJr31y4kl7iuUehJYbe70gJE1qI/ES/eg5tswAcNetYSRrfhhoh16MZ
eysvleFhT9r+3JS+K0w5hYejuLYYKrJTo1NLAHaPA6FKDeWP6t9e9ZIDVaSkKzXm
4QkQ0m0Paj31ZBsc7UJsQS989m5ptIdKZkQtDoesOfp2a3aojQhnlmhbkv4oj6b1
x8w5LDilAgMBAAECggEAITI5+Cx1z0gRlBV82g15VW5gbF38uZT6iwLy/6bes3w3
wzw+fzUtZMF29JKoPrGGttj+XNLN+IIg67pV9cHrt3bPqQoDCGKm89VtKy+KldbZ
57Z86Yu6t4wzW8BWUguzAw2GZzZZZhCABWq8g5/Oh6zSnyveUNA/KHxPHQX/sH9s
VlR5NyGu0Sq4tr4dkoYn7wlmOO34S0VWNlt3xDdH3Rqt8K0sOC6S46dWgelG1QGq
ZglPZlxzcfl/hZ76kNkrpnHub1saSgZ7cXEVvOYBPISU2o64FiD5Y83R8fSO7RBU
PkxJntjjXTGNvACzZYltCwl6FB1krUopcxU4uO99qQKBgQDtjiErMk8q3oteH9tw
cH/m1ft1gTVC/eiqKkX/vsXYJkxLR2XAFnQJ/QLHBBBZOGpN6UqtNQP4Wpu3HcUA
rHgxvz5O+Gr9CXX4CCmKXAS0XdAw7bqJ1DGmCPVq13++OVoxiZU4f3nl1DWdM7a3
7k9Ju51v7s2ispzvK9HcUmqVLQKBgQDbibYOh9/kdIyfjHdcc6pngfEVvvcUM9qD
UABNlwjPqMFi6r4z9tVfGtfP7fwErN8h2+zfmhePy7X188V6BUveN8EqQs/QnGKv
D27BI2c+v8Ls/pA4T4uc8c2FZv/NpzduR3obrpNBN8SgDnF4htBp81qWI31z/cy6
n6obdElMWQKBgQC1j2CIbE4XnLl1+fE0kbcfjUJAP72ecwNlMyQG4B7EIhlDm9EH
q+GKVMbPpqp8FmMhIwHBOfjL0yyaGvWbmzXOB7Wuk6zpslZoeIyPQ98Qn3bkPn3I
o9ZCaSxxOT1X/OuTWu0inkNjRfqoKIMpNsmAuBUPHLwr8kmBfsNJme/+DQKBgCkO
N92/yz8ODL5JpojDmLqCsnM+ozZD/DlSXLwl4p/zDzdQbwGIx55hhrp75wV4zsGm
P0YRqxZZIk48qFGJbAbCpn0gwXxhwpK6cBvuYwB5HBr2AEKHnbRcA/NOr8fl3Zfi
BhPnMeKga0UDbnT7wT4PJIGvYWavr/m2ojlAJfUBAoGBAJITIFx5qOOY33jnv9x3
27Db3ttuof8+NXeMs5ShkgNzMQe2TAHeiQxeS4Qh/cjFLPlF8aV7+1+kfMKiGoKA
iwrddmxUjfSs+FBN1GTZxiz5QAYVahlCb5O4gq92mCDSzcmReoDkWXZmj0T9jEcI
SFs3S+Y1PDM5iP2TgG0iAXpF
-----END RSA PRIVATE KEY-----
EOF

    openssl req -x509 -new -nodes -key "$CERT_DIR/rootCA.key" -sha256 -days 365 \
        -set_serial 1 -out "$CERT_DIR/rootCA.crt" \
        -subj "/CN=NATS-Simulation-CA" >/dev/null 2>&1

    cat > "$CERT_DIR/nats-server.key" <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCbom5EsNnpfVwH
UDxqFkYcf2iabZNJmpgn+qjASp+5cPP4he3q0sBKo/7FZl5Gh96RVNAcDaoXBXI/
jVYCSqu9EhoUwvrxYQ0MYOSmfQRP88+UBqPjCiOuCG3aRP7uW1qB0Vb1z9Huvu23
j88RYsBRl3xyxx7sCAH59NtpmmDC7VjYKNzC0mS3YivqogbQTYDAO1LBX8ZYSZB5
Vf89HhmOcENlfL+RMiVPy3hW7EmCCiVESxx7cVtwwkdIqVyX7DtLG34uuvB9Wu5j
xBiuySWNrECUGtbFE8hqHkjNWILyrhYXZHfe8D0ughXdCXZo9O5ZpZki1SfD+/Eq
5GlEirE9AgMBAAECggEAI/pCn2J6nX07Pv2PWb7YalIRrlFSURuJvQQ26mzVy5qO
646aV0Rs61RJ2vw1IvzZuKLwkOufvD6oEITtsw3r8YMzwETqmc4jpA7qDIqt6oWk
IMYAMMXxRZPxQRneDN/VZlksTxrBnv1IGr0F0zEO4E2ymR3qygl32359EkZ7w9OZ
+03bm2+MIyG0j9+T85zhBA4vApNyYryoEBmZk93Jim9Apcc+1UwObtEsWZ0LkjVE
oKsD8hJ2zgiKp6TXpjf+4aZq2ZSWTMmj0rgf6Jvb+fSNRfmirKsxmMM7GauDcHur
CWMkcrw+1I7EBdC3NN3kolvS3x0Y4yU71Frk+w7ZyQKBgQDMwgSqHoVq5shb83Tw
uzAgy9RuL/P5WdBG7RiqMIC8vnsuNIjwIyj84/Y6uSyeKldFkNC0+jbHaZuWSVos
VYMhBk8q/t6xgXNFpjGlo86slhVsljeAntOX6Gng1AXxvaso78gZMQZA36WOrdSU
edkBzRFGr4NirnXLWINaSwGlUwKBgQDClUhGoHZZPdSFJlF8oZ80v5fgzc5DpYG4
/gAiXX9uC1KK4hNmC/JRGJoC7yNhI/pE8//ivPjdfZ1vzYmIAhH1o/pP4ALo85ef
EafmGo/fPC9TbNtQ5+8tbpiplt3Aa1Xvmp0MbGgmrIPoIi7Q39lJt/+rUQSDe692
iDhHWKNtLwKBgHuqmuKceHwuUsima/SROeo08WJzd+kcA50yyfjQPpDAgulPNX3D
3peOn0KsYHROolMTudn0XW1nLV9BgkLQithBVUNkl9+hjZt9WvLt0n+OTfY9a9w1
ERrodjoiFE0C/wNEfxgn8dzwtq9L8d6TESvzTQHiM3pAYEimdv7r2lydAoGADNvm
sdwq1gzy/XWhzvWzWr4KoG2ZYvkOEJaglaTOJgyTgOAd3hGOCvPwQZ9iHCpPgL0L
PQW2AJUrkVbo7tcMLsqOYTbxmkl2zKlTCi7ZMSx+CCpaeAdL1BnJ9vMkZnHxdOsn
08laPKwL74xKwbz5VBjXyY+KF9JVrySja3udGTsCgYEAi9C6U6l3kHJPweWCjRNz
aBbteu2wN6gZf3bj6HCsLsJnN4w9b6vx6JahhcLISi6cGWZjmvZeUJI50G6hh+Ok
TOM36+qjwM9iAvo5nDN4JV9BjYhXPdO0TF/Xucy7uyzXxCup4nnhZUFKJKN0B4O8
gfq8juFJUYpvhDwghfiZE/g=
-----END RSA PRIVATE KEY-----
EOF
    openssl req -new -key "$CERT_DIR/nats-server.key" \
        -set_serial 101 -out "$CERT_DIR/nats-server.csr" \
        -config "$CERT_DIR/san.cnf" >/dev/null 2>&1

    openssl x509 -req -in "$CERT_DIR/nats-server.csr" -CA "$CERT_DIR/rootCA.crt" \
        -CAkey "$CERT_DIR/rootCA.key" -CAcreateserial -out "$CERT_DIR/nats-server.crt" \
        -days 365 -sha256 -extensions v3_req -extfile "$CERT_DIR/san.cnf" >/dev/null 2>&1
    
    log_success "Certificates updated in $CERT_DIR"
}

setup() {
    log_info "--- Running Simplified Setup ---"
    local GATEWAY_ID_FILE="$STATE_DIR/gateway_ids.txt"

    server_network="nats_backbone"
    # 1. Create the backbone network
    log_info "Setting up backbone network for gateways"
    docker network create nats_backbone --subnet 10.11.0.0/24 >/dev/null 2>&1 || true

    generate_certs "placeholder tbh" # need to do this before we set up the darned server

    if [ "$NO_SERVER" = true ]; then
        log_info "Skipping server setup (--noserver flag set)."
    else
        log_info "Setting up server"
        server_id=$(docker run --rm -d --network nats_backbone --ip 10.11.0.2 -v "$(pwd)":/etc/nats -p 443:443 nats:latest -c /etc/nats/server.conf)

        echo "$server_id" > "$STATE_DIR/server.txt"
    fi

    # 2. start the almighty global clock
    clock_id=$(docker run -d \
    --name global_clock_master \
    --privileged \
    -v "$(pwd)/timing/global_time:/usr/local/bin/global_time" \
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
            --sysctl net.ipv4.ip_forward=1 \
            --hostname "$gateway_name" \
            nicolaka/netshoot /bin/sh -c "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; \
            tc qdisc replace dev eth0 root netem \
            delay ${U_LATENCY}ms ${U_JITTER}ms ${CORRELATION}% \
            loss gemodel 2% 25% 50% 0.1%; sleep infinity")

        echo "$new_gateway_id" >> "$GATEWAY_ID_FILE"

        # Connect the gateway to the mobile network with a SPECIFIC IP
        docker network connect --ip "$gateway_ip_on_mobile" "$network_name" "$gateway_name"

        # Apply download latency and bursty loss to the mobile interface (eth1)
        docker exec -d "$new_gateway_id" tc qdisc replace dev eth1 root netem \
            delay ${D_LATENCY}ms ${D_JITTER}ms ${CORRELATION}% \
            loss gemodel 2% 25% 50% 0.1% >/dev/null
    done

    log_success "--- Setup Complete ---"
}
