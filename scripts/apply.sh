#!/bin/sh
# Apply configuration: compile, restart services, netfilter

set -e

KSD_ETC="${KSD_ETC:-/opt/etc/keenetic-split-dns}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/compile-config.sh"

if [ -x /opt/etc/init.d/S98smartdns ]; then
  /opt/etc/init.d/S98smartdns restart || /opt/etc/init.d/S98smartdns start
elif [ -x /opt/etc/init.d/S56smartdns ]; then
  /opt/etc/init.d/S56smartdns restart || true
fi

if [ -x /opt/etc/init.d/S99ksd-web ]; then
  /opt/etc/init.d/S99ksd-web restart || /opt/etc/init.d/S99ksd-web start
fi

NF="/opt/etc/ndm/netfilter.d/010-keenetic-split-dns.sh"
if [ -x "$NF" ]; then
  "$NF" restart 2>/dev/null || true
  ndm -p netfilter restart 2>/dev/null || true
fi

echo "Applied keenetic-split-dns configuration."
exit 0
