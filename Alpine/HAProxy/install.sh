#!/usr/bin/env sh
set -e

apk add --no-cache haproxy
rc-update add haproxy

cat <<EOF | tee /etc/iptables/rules-save
*filter
:INPUT ACCEPT [1:52]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [1:52]
-A INPUT -i lo -j ACCEPT
-A INPUT -d 127.0.0.0/8 ! -i lo -j REJECT --reject-with icmp-port-unreachable
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 6443 -j ACCEPT
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-port-unreachable
-A FORWARD -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -j ACCEPT
COMMIT
EOF

cat <<EOF | tee /etc/haproxy/haproxy.cfg

global
  chroot      /var/lib/haproxy
  pidfile     /var/run/haproxy.pid
  maxconn     4000
  user        haproxy
  group       haproxy
  daemon

  stats socket /var/lib/haproxy/stats

defaults
  mode http
  option dontlognull
  timeout http-request 5s
  timeout connect 5000
  timeout client 2000000 # ddos protection
  timeout server 2000000 # stick-table type ip size 100k expire 30s store conn_cur

frontend stats
  bind *:8404
  stats enable
  stats uri /stats
  stats refresh 10s
  stats admin if LOCALHOST

frontend k8s-control
  bind *:6443
  mode tcp
  default_backend k8s-control

backend k8s-control
  mode tcp
  server k8s-control 10.10.1.10:6443 check 

frontend main_https
  bind	*:80
  bind 	*:443 ssl crt /etc/haproxy/ssl/
  http-request redirect scheme https unless { ssl_fc }
  mode	http	
  option	httplog
  
  #acl host_sub hdr(host) -i sub.mydomain.com
  #use_backend sub if host_sub
  
  default_backend k8s

# backend sub
#   mode http
#   server sub-1 10.10.15.251:8080 check


backend k8s
  mode http 
  balance leastconn
  option httpchk GET /healthz
  server k8s-1 10.10.1.11:80 check
  server k8s-2 10.10.1.12:80 check
  server k8s-3 10.10.1.13:80 check

EOF

iptables-restore < /etc/iptables/rules-save

/etc/init.d/iptables save