#!/bin/sh
# Detect Keenetic LAN IP (br0 / ndm)

set -e

detect_lan_ip() {
  ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 addr show br0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
  fi
  if [ -z "$ip" ] && [ -f /proc/net/route ]; then
    ip="$(awk '$1=="br0" && $3=="00000000" {print; exit}' /proc/net/route 2>/dev/null | \
      awk '{printf "%d.%d.%d.%d\n", strtonum("0x" substr($2,7,2)), strtonum("0x" substr($2,5,2)), strtonum("0x" substr($2,3,2)), strtonum("0x" substr($2,1,2))}' 2>/dev/null || true)"
  fi
  if [ -z "$ip" ] && command -v ndm >/dev/null 2>&1; then
    ip="$(ndm -p ip address 2>/dev/null | awk '/inet / && /br0/ {gsub(/\/.*/,"",$2); print $2; exit}')"
  fi
  if [ -z "$ip" ]; then
    ip="192.168.1.1"
  fi
  printf '%s' "$ip"
}

detect_isp_dns() {
  dns=""
  if command -v ndm >/dev/null 2>&1; then
    dns="$(ndm -p show dns-proxy 2>/dev/null | awk '/server/ {print $3; exit}' | tr -d "'\"")"
  fi
  if [ -z "$dns" ]; then
    dns="$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1)"
  fi
  if [ -z "$dns" ]; then
    dns="$(detect_lan_ip)"
  fi
  printf '%s' "$dns"
}

case "${1:-lan}" in
  lan) detect_lan_ip ;;
  isp) detect_isp_dns ;;
  *) detect_lan_ip ;;
esac
