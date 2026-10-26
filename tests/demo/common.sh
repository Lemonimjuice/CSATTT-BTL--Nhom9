#!/bin/sh
# Hàm dùng chung cho các script demo. Được `. tests/demo/common.sh` nạp, không chạy trực tiếp.
# Không in mật khẩu, JWT hay refresh token ra màn hình.

ROOT=${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT"
BASE=${BASE:-https://localhost}
CA="$ROOT/nginx/certs/server.crt"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Tài khoản thử nghiệm trong database/init/03-seed-data.sql
USER_A=user_a; PASS_A='UserA@Nhom9-2026'
USER_B=user_b; PASS_B='UserB@Nhom9-2026'

PASS_COUNT=0; FAIL_COUNT=0

title() { printf '\n==== %s ====\n' "$*"; }
note()  { printf '  %s\n' "$*"; }

# req METHOD PATH [TOKEN] [JSON_BODY]  -> in mã trạng thái, lưu body/header vào $TMP/body, $TMP/head
req() {
    _m=$1; _p=$2; _t=${3:-}; _d=${4:-}
    set -- -s --cacert "$CA" -X "$_m" -o "$TMP/body" -D "$TMP/head" -w '%{http_code}'
    [ -n "$_t" ] && set -- "$@" -H "Authorization: Bearer $_t"
    [ -n "$_d" ] && set -- "$@" -H 'Content-Type: application/json' --data-binary "$_d"
    curl "$@" "$BASE$_p"
}
header() { grep -i "^$1:" "$TMP/head" | head -1 | cut -d' ' -f2- | tr -d '\r'; }
body()   { cat "$TMP/body"; }

# check MÔ_TẢ KỲ_VỌNG THỰC_TẾ
check() {
    if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); printf '  [PASS] %s: %s\n' "$1" "$3"
    else FAIL_COUNT=$((FAIL_COUNT+1)); printf '  [FAIL] %s: mong đợi %s, nhận %s\n' "$1" "$2" "$3"; fi
}

# login PATH USER PASS -> in access token (thử lại khi gặp rate limit 429 của Nginx)
login() {
    for _i in 1 2 3 4 5 6; do
        _s=$(req POST "$1" "" "{\"username\":\"$2\",\"password\":\"$3\"}")
        if [ "$_s" = 200 ]; then sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p' "$TMP/body"; return 0; fi
        if [ "$_s" = 429 ]; then sleep 13; continue; fi
        echo "login $2 thất bại: HTTP $_s" >&2; return 1
    done
    echo "login $2: vẫn bị rate limit" >&2; return 1
}

# Mã request ID cuối cùng mà Nginx trả về
last_rid() { header X-Request-ID; }

# Chạy lệnh trong container nginx-waf. MSYS_NO_PATHCONV: Git Bash trên Windows không đổi
# "/var/log/..." thành "C:/Program Files/Git/var/log/...".
waf_exec() { MSYS_NO_PATHCONV=1 docker compose exec -T nginx-waf "$@"; }
# waf_audit RID -> dòng audit log ModSecurity có unique_id = RID
waf_audit() { waf_exec grep "\"unique_id\":\"$1\"" /var/log/modsecurity/audit/audit.log; }

# Log backend chính (2 node) đã bỏ mã màu ANSI
backend_logs() { docker compose logs --no-log-prefix backend-node-1 backend-node-2 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }

summary() {
    printf '\nKết quả: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [ "$FAIL_COUNT" -eq 0 ]
}
