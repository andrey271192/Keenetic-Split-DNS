#!/bin/sh
# Keenetic-Split-DNS REST API (CGI)

export KSD_ETC="${KSD_ETC:-/opt/etc/keenetic-split-dns}"
. /opt/share/keenetic-split-dns/scripts/api.sh
api_route
