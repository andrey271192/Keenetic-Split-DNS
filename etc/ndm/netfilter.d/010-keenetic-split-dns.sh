#!/bin/sh
# Keenetic-Split-DNS — redirect LAN DNS to SmartDNS (fallback if dns-override unavailable)
# Installed to /opt/etc/ndm/netfilter.d/010-keenetic-split-dns.sh

KSD_ETC="/opt/etc/keenetic-split-dns"
DNS_PORT="53"

[ -f "$KSD_ETC/config.yaml" ] || exit 0

# Skip if Entware dns-override is active
if [ -f /opt/etc/dns-override.conf ] && grep -q '^enabled=1' /opt/etc/dns-override.conf 2>/dev/null; then
  exit 0
fi

LAN_IP="$(grep '^lan_ip:' "$KSD_ETC/config.yaml" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/')"
[ -n "$LAN_IP" ] || LAN_IP="192.168.1.1"

DNS_PORT="$(grep '^dns_port:' "$KSD_ETC/config.yaml" 2>/dev/null | awk '{print $2}')"
[ -n "$DNS_PORT" ] || DNS_PORT="53"

case "$1" in
  start|restart)
    iptables -t nat -C PREROUTING -i br0 -p udp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT" 2>/dev/null \
      || iptables -t nat -A PREROUTING -i br0 -p udp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT"
    iptables -t nat -C PREROUTING -i br0 -p tcp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT" 2>/dev/null \
      || iptables -t nat -A PREROUTING -i br0 -p tcp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT"
    ;;
  stop)
    iptables -t nat -D PREROUTING -i br0 -p udp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i br0 -p tcp --dport 53 ! -d "$LAN_IP" -j REDIRECT --to-port "$DNS_PORT" 2>/dev/null || true
    ;;
esac

exit 0
