#!/bin/sh
# Keenetic-Split-DNS uninstaller
# curl -fsSL https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main/uninstall.sh | sh
# Add --purge to remove Entware packages (smartdns, lighttpd)

set -e

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
  esac
done

KSD_ETC="/opt/etc/keenetic-split-dns"
KSD_SHARE="/opt/share/keenetic-split-dns"
REPO_RAW="${KSD_REPO_RAW:-https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main}"

log() { printf '[keenetic-split-dns] %s\n' "$*"; }

# Allow curl pipe: fetch self not needed

log "Stopping services..."
for s in S99ksd-web S98smartdns S97ksd-compile; do
  [ -x "/opt/etc/init.d/$s" ] && /opt/etc/init.d/$s stop 2>/dev/null || true
done

NF="/opt/etc/ndm/netfilter.d/010-keenetic-split-dns.sh"
if [ -x "$NF" ]; then
  "$NF" stop 2>/dev/null || true
fi
ndm -p netfilter restart 2>/dev/null || true

# Restore dns-override if we touched it
STATE="${KSD_ETC}/dns-override.state"
if [ -f "$STATE" ]; then
  case "$(cat "$STATE" 2>/dev/null)" in
    enabled|before-install)
      if [ -f /opt/etc/dns-override.conf.ksd-bak ]; then
        cp /opt/etc/dns-override.conf.ksd-bak /opt/etc/dns-override.conf
        log "Restored dns-override.conf from backup"
      else
        opkg dns-override disable 2>/dev/null || true
      fi
      ;;
  esac
fi

log "Removing init scripts..."
for s in S99ksd-web S98smartdns S97ksd-compile; do
  rm -f "/opt/etc/init.d/$s"
done

rm -f /opt/etc/ndm/netfilter.d/010-keenetic-split-dns.sh

log "Removing files..."
rm -rf "$KSD_ETC" "$KSD_SHARE"
rm -rf /opt/var/log/keenetic-split-dns /opt/var/run/keenetic-split-dns

killall smartdns 2>/dev/null || true
killall lighttpd 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
  log "Purging Entware packages (--purge)..."
  opkg remove smartdns lighttpd lighttpd-mod-cgi 2>/dev/null || true
else
  log "Entware packages kept (use --purge to remove smartdns/lighttpd)"
fi

log "Keenetic-Split-DNS uninstalled."
exit 0
