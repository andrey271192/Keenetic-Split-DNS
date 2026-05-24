#!/bin/sh
# YAML config -> SmartDNS conf + domain sets + lighttpd bind

set -e

KSD_ETC="${KSD_ETC:-/opt/etc/keenetic-split-dns}"
KSD_SHARE="${KSD_SHARE:-/opt/share/keenetic-split-dns}"
CONFIG="${KSD_ETC}/config.yaml"
OUT_SMART="${KSD_ETC}/smartdns.conf"
OUT_LIGHT="${KSD_ETC}/lighttpd.conf"
DOMAIN_DIR="${KSD_ETC}/domain-sets"
HEAD="${KSD_SHARE}/smartdns/smartdns.conf.head"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
DETECT="${SCRIPT_DIR}/detect-lan.sh"

[ -f "$CONFIG" ] || { echo "Missing $CONFIG" >&2; exit 1; }
mkdir -p "$DOMAIN_DIR" "$(dirname "$OUT_SMART")"

# --- simple YAML getters (key: value / nested under upstreams:) ---
yaml_val() {
  key="$1"
  awk -v k="$key" '
    $0 ~ "^" k ": " {
      v = $0; sub("^" k ": ", "", v)
      gsub(/^["'\'']|["'\'']$/, "", v)
      print v; exit
    }
  ' "$CONFIG"
}

yaml_upstream_field() {
  uid="$1"
  field="$2"
  awk -v id="$uid" -v f="$field" '
    $0 ~ "^  " id ":$" { inb=1; next }
    inb && $0 ~ "^  [a-zA-Z0-9_-]+:$" { exit }
    inb && $0 ~ "^    " f ": " {
      v=$0; sub("^    " f ": ", "", v)
      gsub(/^["'\'']|["'\'']$/, "", v)
      print v; exit
    }
  ' "$CONFIG"
}

yaml_group_field() {
  gid="$1"
  field="$2"
  awk -v id="$gid" -v f="$field" '
    $0 ~ "^  " id ":$" { inb=1; next }
    inb && $0 ~ "^  [a-zA-Z0-9_-]+:$" { exit }
    inb && $0 ~ "^    " f ": " {
      v=$0; sub("^    " f ": ", "", v)
      gsub(/^["'\'']|["'\'']$/, "", v)
      print v; exit
    }
  ' "$CONFIG"
}

LAN_IP="$(yaml_val lan_ip)"
[ -n "$LAN_IP" ] || LAN_IP="$("$DETECT" lan)"
WEB_PORT="$(yaml_val web_port)"
[ -n "$WEB_PORT" ] || WEB_PORT="3200"
DNS_PORT="$(yaml_val dns_port)"
[ -n "$DNS_PORT" ] || DNS_PORT="53"
DNS_LISTEN="$(yaml_val dns_listen)"
[ -n "$DNS_LISTEN" ] || DNS_LISTEN="0.0.0.0"
CACHE_TTL="$(yaml_val cache_ttl_max)"
[ -n "$CACHE_TTL" ] || CACHE_TTL="3600"
DEFAULT_UP="$(yaml_val default_upstream)"
[ -n "$DEFAULT_UP" ] || DEFAULT_UP="isp-default"
LOG_Q="$(yaml_val log_queries)"

# --- SmartDNS header ---
{
  [ -f "$HEAD" ] && cat "$HEAD"
  echo "bind ${DNS_LISTEN}:${DNS_PORT}"
  echo "cache-persist no"
  echo "rr-ttl-max ${CACHE_TTL}"
  if [ "$LOG_Q" = "true" ] || [ "$LOG_Q" = "1" ]; then
    echo "log-file /opt/var/log/keenetic-split-dns/smartdns.log"
    echo "log-size 256k"
  fi
  echo ""
} > "$OUT_SMART"

# --- upstream servers ---
list_upstream_ids() {
  awk '
    /^upstreams:$/ { in_s=1; next }
    in_s && /^[^ #]/ { exit }
    in_s && /^  [a-zA-Z0-9_-]+:$/ {
      gsub(/:$/, "", $1)
      print $1
    }
  ' "$CONFIG"
}

for uid in $(list_upstream_ids); do
  typ="$(yaml_upstream_field "$uid" type)"
  addr="$(yaml_upstream_field "$uid" address)"
  port="$(yaml_upstream_field "$uid" port)"
  sni="$(yaml_upstream_field "$uid" sni)"
  [ -n "$port" ] || port="53"

  case "$typ" in
    dot)
      host="${sni:-$addr}"
      echo "server-tls ${host} -address ${addr}:${port} -host-name ${host} -group ${uid} -no-check-certificate" >> "$OUT_SMART"
      ;;
    doh)
      url="$(yaml_upstream_field "$uid" url)"
      [ -n "$url" ] || url="https://${addr}/dns-query"
      echo "server-https ${url} -group ${uid}" >> "$OUT_SMART"
      ;;
    *)
      if [ "$addr" = "auto" ]; then
        addr="$("$DETECT" isp)"
      fi
      echo "server ${addr}:${port} -group ${uid}" >> "$OUT_SMART"
      ;;
  esac
done

echo "" >> "$OUT_SMART"

# --- domain groups ---
list_group_ids() {
  awk '
    /^domain_groups:$/ { in_s=1; next }
    in_s && /^[^ #]/ { exit }
    in_s && /^  [a-zA-Z0-9_-]+:$/ {
      gsub(/:$/, "", $1)
      print $1
    }
  ' "$CONFIG"
}

for gid in $(list_group_ids); do
  upstream="$(yaml_group_field "$gid" upstream)"
  dset="$(yaml_group_field "$gid" domain_set)"
  [ -n "$dset" ] || dset="${gid}.txt"
  dpath="${DOMAIN_DIR}/${dset}"
  if [ ! -f "$dpath" ] && [ -f "${KSD_SHARE}/domain-sets/${dset}" ]; then
    cp "${KSD_SHARE}/domain-sets/${dset}" "$dpath"
  fi
  [ -f "$dpath" ] || continue
  echo "domain-set -name ${gid} -file ${dpath}" >> "$OUT_SMART"
  echo "domain-rules /domain-set:${gid}/ -nameserver ${upstream} -speed-check-mode none" >> "$OUT_SMART"
done

echo "nameserver ${DEFAULT_UP}" >> "$OUT_SMART"
echo "default-nameserver ${DEFAULT_UP}" >> "$OUT_SMART"

# --- lighttpd ---
LIGHT_SRC="${KSD_SHARE}/lighttpd/lighttpd.conf"
if [ -f "$LIGHT_SRC" ]; then
  sed "s/LAN_IP_PLACEHOLDER/${LAN_IP}/g; s/server.port = 3200/server.port = ${WEB_PORT}/" "$LIGHT_SRC" > "$OUT_LIGHT"
fi

echo "Compiled: $OUT_SMART"
exit 0
