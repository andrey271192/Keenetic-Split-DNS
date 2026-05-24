#!/bin/sh
# Keenetic-Split-DNS — one-line installer for Keenetic + Entware
# curl -fsSL https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main/install.sh | sh

set -e

KSD_VERSION="1.0.0"
KSD_ETC="/opt/etc/keenetic-split-dns"
KSD_SHARE="/opt/share/keenetic-split-dns"
KSD_VAR_LOG="/opt/var/log/keenetic-split-dns"
KSD_VAR_RUN="/opt/var/run/keenetic-split-dns"
REPO_RAW="${KSD_REPO_RAW:-https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main}"

log() { printf '[keenetic-split-dns] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

# --- Entware check ---
[ -x /opt/bin/opkg ] || die "Entware not found. Install Entware on USB first."
[ -d /opt/etc ] || die "/opt/etc missing — Entware broken?"

# --- resolve source tree ---
SRC_DIR=""
case "$0" in
  /*|./*|*/install.sh)
    _d="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
    [ -f "${_d}/etc/config.yaml.example" ] && SRC_DIR="$_d"
    ;;
esac
if [ -z "$SRC_DIR" ]; then
  TMP="$(mktemp -d /tmp/ksd-install.XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT INT HUP
  log "Downloading repository..."
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/andrey271192/Keenetic-Split-DNS.git "$TMP/repo"
    SRC_DIR="$TMP/repo"
  else
    die "git not found. On router: opkg install git git-http. Or clone repo manually and run install.sh from it."
  fi
fi

log "Installing Keenetic-Split-DNS v${KSD_VERSION}..."

# --- packages ---
log "Installing Entware packages..."
opkg update >/dev/null 2>&1 || true
for pkg in smartdns lighttpd lighttpd-mod-cgi ca-certificates curl grep sed bind-dig; do
  opkg list-installed 2>/dev/null | grep -q "^${pkg} " || opkg install "$pkg" >/dev/null 2>&1 || {
    case "$pkg" in
      bind-dig) opkg install bind-tools >/dev/null 2>&1 || opkg install dig >/dev/null 2>&1 || true ;;
      *) log "Warning: package $pkg may be missing" ;;
    esac
  }
done

mkdir -p "$KSD_ETC" "$KSD_SHARE" "$KSD_VAR_LOG" "$KSD_VAR_RUN" \
  "${KSD_ETC}/domain-sets" "${KSD_SHARE}/www" "${KSD_SHARE}/scripts" \
  "${KSD_SHARE}/cgi-bin" "${KSD_SHARE}/smartdns" "${KSD_SHARE}/lighttpd" \
  "${KSD_SHARE}/domain-sets"

# --- copy files ---
if [ ! -f "${KSD_ETC}/config.yaml" ]; then
  cp "$SRC_DIR/etc/config.yaml.example" "${KSD_ETC}/config.yaml"
fi

cp -rf "$SRC_DIR/scripts/"* "${KSD_SHARE}/scripts/"
cp -rf "$SRC_DIR/www/"* "${KSD_SHARE}/www/"
cp -f "$SRC_DIR/cgi-bin/api.cgi" "${KSD_SHARE}/cgi-bin/"
cp -rf "$SRC_DIR/etc/domain-sets/"* "${KSD_SHARE}/domain-sets/" 2>/dev/null || true
cp -f "$SRC_DIR/etc/smartdns/"* "${KSD_SHARE}/smartdns/" 2>/dev/null || true
cp -f "$SRC_DIR/etc/lighttpd/lighttpd.conf" "${KSD_SHARE}/lighttpd/"

# symlink API CGI into web root
ln -sf "${KSD_SHARE}/cgi-bin/api.cgi" "${KSD_SHARE}/www/api.cgi"
mkdir -p "${KSD_SHARE}/www/api"
ln -sf "${KSD_SHARE}/cgi-bin/api.cgi" "${KSD_SHARE}/www/api/index.cgi"

chmod +x "${KSD_SHARE}/scripts/"*.sh "${KSD_SHARE}/cgi-bin/api.cgi"

# --- detect LAN ---
DETECT="${KSD_SHARE}/scripts/detect-lan.sh"
LAN_IP="$("$DETECT" lan 2>/dev/null || echo "192.168.1.1")"
if grep -q 'lan_ip: "192.168.1.1"' "${KSD_ETC}/config.yaml" 2>/dev/null; then
  if sed -i "s/lan_ip: \"192.168.1.1\"/lan_ip: \"${LAN_IP}\"/" "${KSD_ETC}/config.yaml" 2>/dev/null; then
    :
  else
    sed "s/lan_ip: \"192.168.1.1\"/lan_ip: \"${LAN_IP}\"/" "${KSD_ETC}/config.yaml" > "${KSD_ETC}/config.yaml.tmp" \
      && mv "${KSD_ETC}/config.yaml.tmp" "${KSD_ETC}/config.yaml"
  fi
fi

# --- API token ---
if [ ! -f "${KSD_ETC}/token" ]; then
  if [ -r /dev/urandom ]; then
    TOKEN="$(head -c 24 /dev/urandom | hexdump -ve '1/1 "%02x"' 2>/dev/null | head -c 48)"
  else
    TOKEN="$(date +%s)$(uname -n)"
  fi
  [ -n "$TOKEN" ] || TOKEN="change-me-$(date +%s)"
  echo "$TOKEN" > "${KSD_ETC}/token"
  chmod 600 "${KSD_ETC}/token"
fi

# --- init.d ---
for s in S97ksd-compile S98smartdns S99ksd-web; do
  cp -f "$SRC_DIR/init.d/$s" "/opt/etc/init.d/$s"
  chmod +x "/opt/etc/init.d/$s"
done

# --- netfilter fallback ---
mkdir -p /opt/etc/ndm/netfilter.d
cp -f "$SRC_DIR/etc/ndm/netfilter.d/010-keenetic-split-dns.sh" /opt/etc/ndm/netfilter.d/
chmod +x /opt/etc/ndm/netfilter.d/010-keenetic-split-dns.sh

# --- domain sets to etc (seed defaults only) ---
for _ds in "${KSD_SHARE}/domain-sets/"*.txt; do
  [ -f "$_ds" ] || continue
  _base="$(basename "$_ds")"
  [ -f "${KSD_ETC}/domain-sets/${_base}" ] || cp -f "$_ds" "${KSD_ETC}/domain-sets/${_base}"
done

# --- compile & start ---
export KSD_ETC KSD_SHARE
"${KSD_SHARE}/scripts/compile-config.sh"

# --- dns-override (HydraRoute Neo compatible path) ---
DNS_OVERRIDE_STATE="${KSD_ETC}/dns-override.state"
if opkg dns-override 2>/dev/null | grep -q enable; then
  log "Configuring opkg dns-override..."
  if ! grep -q '^enabled=1' /opt/etc/dns-override.conf 2>/dev/null; then
    cp /opt/etc/dns-override.conf /opt/etc/dns-override.conf.ksd-bak 2>/dev/null || true
    echo "before-install" > "$DNS_OVERRIDE_STATE"
  fi
  opkg dns-override enable 2>/dev/null || true
  echo "enabled" > "$DNS_OVERRIDE_STATE"
  log "dns-override enabled — clients use Entware SmartDNS"
else
  log "dns-override not available — using netfilter.d redirect (if br0 DNS used)"
  echo "netfilter" > "$DNS_OVERRIDE_STATE"
fi

/opt/etc/init.d/S97ksd-compile start
/opt/etc/init.d/S98smartdns start
/opt/etc/init.d/S99ksd-web start

ndm -p netfilter restart 2>/dev/null || true

WEB_PORT="$(grep '^web_port:' "${KSD_ETC}/config.yaml" | awk '{print $2}')"
[ -n "$WEB_PORT" ] || WEB_PORT="3200"
TOKEN_SHOW="$(cat "${KSD_ETC}/token")"

log "=============================================="
log "Keenetic-Split-DNS installed successfully."
log "Web UI:  http://${LAN_IP}:${WEB_PORT}"
log "API token (save it): ${TOKEN_SHOW}"
log "Config:  ${KSD_ETC}/config.yaml"
log ""
log "IMPORTANT: Disable global DoT in Keenetic UI"
log "(Интернет-фильтры -> DNS) to avoid conflicts."
log "HydraRoute Neo: keep DHCP DNS = router IP."
log "=============================================="
exit 0
