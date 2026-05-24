#!/bin/sh
# CGI API helpers for Keenetic-Split-DNS

KSD_ETC="${KSD_ETC:-/opt/etc/keenetic-split-dns}"
KSD_SHARE="${KSD_SHARE:-/opt/share/keenetic-split-dns}"
CONFIG="${KSD_ETC}/config.yaml"
TOKEN_FILE="${KSD_ETC}/token"
LOG_FILE="${KSD_ETC}/apply.log"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

api_send_json() {
  code="${1:-200}"
  body="$2"
  printf 'Status: %s\r\n' "$code"
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '%s' "$body"
}

api_unauthorized() {
  api_send_json "401" '{"ok":false,"error":"unauthorized"}'
  exit 0
}

api_check_auth() {
  expected=""
  [ -f "$TOKEN_FILE" ] && expected="$(cat "$TOKEN_FILE" | tr -d '\n\r ')"
  [ -n "$expected" ] || return 0

  got=""
  case "$HTTP_AUTHORIZATION" in
    Bearer*) got="${HTTP_AUTHORIZATION#Bearer }" ;;
  esac
  [ -z "$got" ] && got="$HTTP_X_KSD_TOKEN"
  [ -z "$got" ] && got="$HTTP_X_DNS_SPLIT_TOKEN"

  if [ "$got" != "$expected" ]; then
    api_unauthorized
  fi
}

api_read_body() {
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null
  fi
}

smartdns_running() {
  if pidof smartdns >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

smartdns_pid() {
  pidof smartdns 2>/dev/null | awk '{print $1}'
}

count_domains() {
  n=0
  if [ -d "${KSD_ETC}/domain-sets" ]; then
    for f in "${KSD_ETC}"/domain-sets/*.txt; do
      [ -f "$f" ] || continue
      n=$((n + $(grep -cve '^\s*$' -e '^\s*#' "$f" 2>/dev/null || echo 0)))
    done
  fi
  echo "$n"
}

api_status() {
  lan="$(grep '^lan_ip:' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/')"
  port="$(grep '^web_port:' "$CONFIG" 2>/dev/null | awk '{print $2}')"
  [ -n "$port" ] || port="3200"
  domains="$(count_domains)"
  running="$(smartdns_running)"
  pid="$(smartdns_pid)"
  last_apply=""
  [ -f "$LOG_FILE" ] && last_apply="$(tail -1 "$LOG_FILE" 2>/dev/null | json_escape)"

  log_json="[]"
  if [ -f "$LOG_FILE" ]; then
    _tmp="$(mktemp /tmp/ksd-logs.XXXXXX)"
    tail -5 "$LOG_FILE" 2>/dev/null > "$_tmp"
    log_json="["
    first=1
    while IFS= read -r line; do
      esc="$(printf '%s' "$line" | json_escape)"
      [ "$first" -eq 1 ] || log_json="${log_json},"
      first=0
      log_json="${log_json}\"${esc}\""
    done < "$_tmp"
    log_json="${log_json}]"
    rm -f "$_tmp"
  fi

  api_send_json "200" "{\"ok\":true,\"smartdns\":{\"running\":${running},\"pid\":\"${pid}\"},\"domains\":${domains},\"lan_ip\":\"${lan}\",\"web_port\":${port},\"url\":\"http://${lan}:${port}\",\"last_apply\":\"${last_apply}\",\"logs\":${log_json}}"
}

api_get_config_raw() {
  if [ ! -f "$CONFIG" ]; then
    api_send_json "404" '{"ok":false,"error":"config not found"}'
    exit 0
  fi
  printf 'Status: 200\r\n'
  printf 'Content-Type: application/x-yaml; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  cat "$CONFIG"
  exit 0
}

api_save_config() {
  body="$(api_read_body)"
  [ -n "$body" ] || { api_send_json "400" '{"ok":false,"error":"empty body"}'; exit 0; }

  # Accept raw YAML body or {"content":"..."}
  case "$body" in
    \{*)
      content="$(printf '%s' "$body" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')"
      ;;
    *)
      content="$body"
      ;;
  esac

  [ -n "$content" ] || { api_send_json "400" '{"ok":false,"error":"no content"}'; exit 0; }
  cp "$CONFIG" "${CONFIG}.bak" 2>/dev/null || true
  printf '%s\n' "$content" > "$CONFIG"
  api_send_json "200" '{"ok":true,"message":"saved"}'
}

api_reload() {
  APPLY="${KSD_SHARE}/scripts/apply.sh"
  if [ ! -x "$APPLY" ]; then
    api_send_json "500" '{"ok":false,"error":"apply.sh not found"}'
    exit 0
  fi
  if "$APPLY" >>"$LOG_FILE" 2>&1; then
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${ts} reload OK" >>"$LOG_FILE"
    api_send_json "200" '{"ok":true,"message":"applied"}'
  else
    api_send_json "500" '{"ok":false,"error":"apply failed"}'
  fi
}

api_test_dns() {
  domain="${QUERY_STRING#*domain=}"
  domain="${domain%%&*}"
  # URL-decode (percent-encoding)
  domain="$(printf '%s' "$domain" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g' | xargs printf '%b' 2>/dev/null || printf '%s' "$domain")"
  [ -n "$domain" ] || domain="vk.com"
  rtype="A"
  case "$QUERY_STRING" in
    *type=AAAA*) rtype="AAAA" ;;
    *type=HTTPS*) rtype="HTTPS" ;;
  esac

  if command -v dig >/dev/null 2>&1; then
  dns_port="$(grep '^dns_port:' "$CONFIG" 2>/dev/null | awk '{print $2}')"
  [ -n "$dns_port" ] || dns_port="53"
  start_ms="$(date +%s)"
  out="$(dig @"127.0.0.1" -p "$dns_port" "$domain" "$rtype" +time=3 +tries=1 2>&1)" || out="dig failed"
  end_ms="$(date +%s)"
  ms=$(( (end_ms - start_ms) * 1000 ))
  esc="$(printf '%s' "$out" | json_escape)"
  api_send_json "200" "{\"ok\":true,\"domain\":\"${domain}\",\"type\":\"${rtype}\",\"ms\":${ms},\"output\":\"${esc}\"}"
  else
  api_send_json "503" '{"ok":false,"error":"dig not installed"}'
  fi
}

api_domains_list() {
  # Build simple JSON array from domain sets
  echo -n '{"ok":true,"domains":['
  first=1
  if [ -d "${KSD_ETC}/domain-sets" ]; then
    for f in "${KSD_ETC}"/domain-sets/*.txt; do
      [ -f "$f" ] || continue
      group="$(basename "$f" .txt)"
  upstream="$(awk -v g="$group" '
    $0 ~ "^  " g ":$" { in_g=1; next }
    in_g && /^[^ #]/ { exit }
    in_g && $0 ~ /^    upstream:/ { print $2; exit }
  ' "$CONFIG" 2>/dev/null)"
      while IFS= read -r d || [ -n "$d" ]; do
        d="$(echo "$d" | tr -d '\r')"
        [ -z "$d" ] && continue
        case "$d" in \#*) continue ;; esac
        [ "$first" -eq 1 ] || echo -n ','
        first=0
        de="$(printf '%s' "$d" | json_escape)"
        ge="$(printf '%s' "$group" | json_escape)"
        ue="$(printf '%s' "${upstream:-yandex-dot}" | json_escape)"
        printf '{"domain":"%s","group":"%s","upstream":"%s"}' "$de" "$ge" "$ue"
      done < "$f"
    done
  fi
  echo ']}'
}

api_route() {
  path="${PATH_INFO:-/}"
  path="${path#/}"
  method="${REQUEST_METHOD:-GET}"

  api_check_auth

  case "$path" in
    status|"") api_status ;;
    config)
      case "$method" in
        GET) api_get_config_raw ;;
        POST) api_save_config ;;
        *) api_send_json "405" '{"ok":false,"error":"method"}' ;;
      esac
      ;;
    domains)
      body="$(api_domains_list)"
      api_send_json "200" "$body"
      ;;
    reload|apply)
      api_reload
      ;;
    test)
      api_test_dns
      ;;
    *)
      api_send_json "404" '{"ok":false,"error":"not found"}'
      ;;
  esac
}
