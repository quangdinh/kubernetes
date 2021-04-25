#!/usr/bin/env sh
SERVER_PORT=5432

set -eux

apk add --no-cache postgresql

rc-update add postgresql

cat <<EOF | tee /etc/iptables/rules-save
*filter
:INPUT ACCEPT [1:52]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [1:52]
-A INPUT -i lo -j ACCEPT
-A INPUT -d 127.0.0.0/8 ! -i lo -j REJECT --reject-with icmp-port-unreachable
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport ${SERVER_PORT} -j ACCEPT
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-port-unreachable
-A FORWARD -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -j ACCEPT
COMMIT
EOF

iptables-restore < /etc/iptables/rules-save
/etc/init.d/iptables save

# Generating dhparams
mkdir -p /etc/ssl
openssl dhparam -out /etc/ssl/dhparams.pem 2048

cat <<EOF
###################################################################
Edit /etc/postgresql/pg_hba.conf
hostssl all             all             all                     md5

Edit /etc/postgresql/postgresql.conf
listen_addresses = '*'
port = 25432
ssl = on
ssl_cert_file = '/etc/ssl/postgres.crt'
ssl_key_file = '/etc/ssl/postgres.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL' # allowed SSL ciphers
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
ssl_dh_params_file = '/etc/ssl/dhparams.pem'
password_encryption = scram-sha-256 
EOF