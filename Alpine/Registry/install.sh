#!/usr/bin/env sh
set -e

apk add --no-cache docker-registry
rc-update add docker-registry
mkdir -p /docker-registry
touch /etc/registry
chown -R docker-registry:docker-registry /docker-registry

random_secret=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}')

cat <<EOF | tee /etc/docker-registry/config.yml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /docker-registry
http:
  secret: ${random_secret}
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
auth:
  htpasswd:
    realm: basic-realm
    path: /etc/registry
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

service docker-registry start

cat <<EOF | tee /etc/iptables/rules-save
*filter

# Allows all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

# Accepts all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allows all outbound traffic
-A OUTPUT -j ACCEPT

# Allow SSH
-A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT

# Allow Docker registry
-A INPUT -p tcp -m state --state NEW --dport 5000 -j ACCEPT

# Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# Reject all other inbound - default deny unless explicitly allowed policy:
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOF

iptables-restore < /etc/iptables/rules-save
/etc/init.d/iptables save