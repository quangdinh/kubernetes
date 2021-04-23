#!/usr/bin/env sh
set -e

adduser -D node

apk add --no-cache su-exec util-linux nfs-utils lvm2 python2 g++ make bash git automake autoconf libtool gettext-dev pkgconf fuse-dev fuse yarn nodejs npm gettext cifs-utils openssl redis
rc-update add redis
service redis start

cd /home/node

# Install libvhhi
git clone --depth 1 https://github.com/libyal/libvhdi.git
cd /home/node/libvhdi
./synclibs.sh
./autogen.sh
./configure
make
make install
cd /home/node
rm -rf libvhdi

# Compile xen orchestra
su node -c 'npm install url-loader --save-dev'
su node -c 'git clone -b master --depth 1 https://github.com/vatesfr/xen-orchestra/'
cd /home/node/xen-orchestra
su node -c 'yarn config set network-timeout 300000'
su node -c 'yarn'
su node -c 'yarn build'

cat <<EOF | tee /home/node/xen-orchestra/packages/xo-server/link_plugins.sh
#!/bin/ash

# link listed plugins
PACKAGES_DIR=/home/node/xen-orchestra/packages

# official plugins directories
PLUGINS="xo-server-auth-github \
xo-server-auth-google \
xo-server-auth-ldap \
xo-server-auth-saml \
xo-server-backup-reports \
xo-server-load-balancer \
xo-server-perf-alert \
xo-server-sdn-controller \
xo-server-transport-email \
xo-server-transport-icinga2 \
xo-server-transport-nagios \
xo-server-transport-slack \
xo-server-transport-xmpp \
xo-server-usage-report \
xo-server-web-hooks"

# NB: this list is manually updated, feel free to make a pull request if new
# plugins are added/removed.

cd ${PACKAGES_DIR}/xo-server/node_modules

for elem in ${PLUGINS}; do
    ln -s ${PACKAGES_DIR}/$elem $elem
done;
EOF

chmod +x /home/node/xen-orchestra/packages/xo-server/link_plugins.sh
su node -c '/home/node/xen-orchestra/packages/xo-server/link_plugins.sh'

su node -c 'mkdir -p ~/.config/xo-server'
mkdir -p /storage/data
chown -R node:node /storage

cat <<EOF | tee ~/.config/xo-server/config.toml

datadir = '/storage/data'
resourceCacheDelay = '5m'
createUserOnFirstSignin = true
guessVhdSizeOnImport = true
verboseApiLogsOnErrors = false
xapiMarkDisconnectedDelay = '5 minutes'

[apiWebSocketOptions]
perMessageDeflate = { threshold = 524288 } # 512kiB

[authentication]
defaultTokenValidity = '30 days'
maxTokenValidity = '0.5 year'
mergeProvidersUsers = true
defaultSignInPage = '/signin'
throttlingDelay = '2 seconds'

[backups]
dirMode = 0o700
snapshotNameLabelTpl = '[XO Backup {job.name}] {vm.name_label}'
listingDebounce = '1 min'

[backups.defaultSettings]
reportWhen = 'failure'

[backups.metadata.defaultSettings]
retentionPoolMetadata = 0
retentionXoMetadata = 0

[backups.vm.defaultSettings]
bypassVdiChainsCheck = false
checkpointSnapshot = false
concurrency = 2
copyRetention = 0
deleteFirst = false
exportRetention = 0
fullInterval = 0
offlineBackup = false
offlineSnapshot = false
snapshotRetention = 0
timeout = 0
vmTimeout = 0

maxMergedDeltasPerRun = 2

[blockedAtOptions]
enabled = false
threshold = 1000


[[http.listen]]
port = 8080

# These options are applied to all listen entries.
[http.listenOptions]

[http.mounts]
'/' = '/home/node/xen-orchestra/packages/xo-web/dist'

[plugins]

[remoteOptions]
mountsDir = '/run/xo-server/mounts'
timeout = 600e3


[selfService]
ignoreVmSnapshotResources = false

[xapiOptions]
ignoreNobakVdis = false
restartHostTimeout = '20 minutes'
maxUncoalescedVdis = 1
vdiExportConcurrency = 12
vmExportConcurrency = 2
vmSnapshotConcurrency = 2

["xo-proxy"]
callTimeout = '1 min'
channel = 'xo-proxy-appliance'
namespace = 'xoProxyAppliance'
proxyName = 'Proxy {date}'
licenseProductId = 'xo-proxy'
vmName = 'XOA Proxy {date}'
vmNetworksTimeout = '5 min'
vmTag = 'XOA Proxy'
xoaUpgradeTimeout = '5 min'
EOF

cat <<EOF | tee /etc/init.d/xen-orchestra
#!/sbin/openrc-run

user="node"
group="node"
command="/usr/bin/yarn"
directory="/home/node/xen-orchestra/package/xo-server"
command_args="start"
command_user="${user}:${group}"
command_background="yes"
pidfile="/run/$RC_SVCNAME}.pid"

depend() {
  use net
}
EOF

chmod +x /etc/init.d/xen-orchestra
rc-update add xen-orchestra