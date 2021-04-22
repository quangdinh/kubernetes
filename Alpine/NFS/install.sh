#!/usr/bin/env sh
set -e
LOCALSUBNET=10.10.0.0/20

apk add --no-cache nfs-utils
rc-update add nfs

cat <<EOF | tee /etc/exports
/nfs_share	$LOCALSUBNET(rw,no_root_squash,async,no_subtree_check)
EOF

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

# Allow Local
-A INPUT -s $LOCALSUBNET -j ACCEPT

# Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# Reject all other inbound - default deny unless explicitly allowed policy:
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOF

iptables-restore < /etc/iptables/rules-save

/etc/init.d/iptables save