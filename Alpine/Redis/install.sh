#!/usr/bin/env sh

USERNAME=main
PASSWORD=mysupersecretpassword
SERVER_IP=10.10.1.22
SERVER_PORT=6379
REDIS_VERSION=6.2.2
REDIS_DOWNLOAD_URL=http://download.redis.io/releases/redis-6.2.2.tar.gz
REDIS_DOWNLOAD_SHA=7a260bb74860f1b88c3d5942bf8ba60ca59f121c6dce42d3017bed6add0b9535

set -eux

# Install required packages
apk add --no-cache --virtual .build-deps coreutils dpkg-dev dpkg gcc linux-headers make musl-dev openssl-dev wget
	
wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"
echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -
mkdir -p /usr/src/redis; 
tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1
rm redis.tar.gz
	
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
extraJemallocConfigureFlags="--build=$gnuArch"
dpkgArch="$(dpkg --print-architecture)"
case "${dpkgArch##*-}" in 
  amd64 | i386 | x32) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=12" ;; 
  *) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=16" ;; 
esac
extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-hugepage=21"
grep -F 'cd jemalloc && ./configure ' /usr/src/redis/deps/Makefile
sed -ri 's!cd jemalloc && ./configure !&'"$extraJemallocConfigureFlags"' !' /usr/src/redis/deps/Makefile
grep -F "cd jemalloc && ./configure $extraJemallocConfigureFlags " /usr/src/redis/deps/Makefile

export BUILD_TLS=yes
make -C /usr/src/redis -j "$(nproc)" all
make -C /usr/src/redis install
cp /usr/src/redis/redis.conf /etc/redis.conf

# Generating dhparams
mkdir -p /etc/ssl
openssl dhparam -out /etc/ssl/dhparams.pem 2048

# Create redis user
adduser -D redis

cat << EOF | tee /etc/init.d/redis-hugepages
#!/sbin/openrc-run

description="Disable transparent hugepages for Redis"

depend()
{
  before redis
}

start()
{
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
}
EOF
chmod +x /etc/init.d/redis-hugepages
rc-update add redis-hugepages


cat <<EOF >> /etc/redis.conf
################ Settings by install scripts ################
bind ${SERVER_IP}
protected-mode yes
tcp-backlog 511
unixsocket /run/redis/redis.sock
unixsocketperm 770
timeout 0
tcp-keepalive 300
port 0
tls-port ${SERVER_PORT}
tls-cert-file /etc/ssl/redis.crt 
tls-key-file /etc/ssl/redis.key
tls-dh-params-file /etc/ssl/dhparams.pem
tls-auth-clients no
tls-protocols "TLSv1.2 TLSv1.3"
tls-ciphers DEFAULT:!MEDIUM
tls-prefer-server-ciphers yes

# Add user
user ${USERNAME} on +@all ~* >${PASSWORD}
EOF
	
rm -r /usr/src/redis
	
runDeps="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local | tr ',' '\n' | sort -u | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }')"

apk add --no-network $runDeps
apk del --no-network .build-deps

apk add --no-cache redis-openrc
ln -s /usr/local/bin/redis-server /usr/bin/redis-server
rc-update add redis

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