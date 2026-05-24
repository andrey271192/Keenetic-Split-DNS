#!/bin/sh
# Keenetic-Split-DNS REST API (CGI)

export KSD_ETC="${KSD_ETC:-/opt/etc/keenetic-split-dns}"
export KSD_SHARE="${KSD_SHARE:-/opt/share/keenetic-split-dns}"
. "${KSD_SHARE}/scripts/api.sh"
api_route
