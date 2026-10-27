#!/bin/sh
# Xem audit log ModSecurity (JSON, mỗi dòng một giao dịch).
#   sh scripts/waf-audit.sh               # 5 giao dịch gần nhất, dạng tóm tắt
#   sh scripts/waf-audit.sh <request-id>  # giao dịch có unique_id = X-Request-ID, bản đầy đủ
#   sh scripts/waf-audit.sh --export      # chép toàn bộ log ra logs/waf/audit.log (đã .gitignore)
# Audit log không chứa header/body request (không lộ Authorization, mật khẩu).
set -eu
export MSYS_NO_PATHCONV=1   # Git Bash: không đổi đường dẫn container thành đường dẫn Windows
cd "$(dirname "$0")/.."
LOG=/var/log/modsecurity/audit/audit.log

case "${1:-}" in
    --export)
        mkdir -p logs/waf
        docker compose exec -T nginx-waf cat "$LOG" > logs/waf/audit.log
        echo "Đã chép $(wc -l < logs/waf/audit.log) giao dịch vào logs/waf/audit.log" ;;
    "")
        docker compose exec -T nginx-waf tail -n 5 "$LOG" | while IFS= read -r line; do
            id=$(echo "$line" | grep -o '"unique_id":"[^"]*"' | cut -d'"' -f4)
            uri=$(echo "$line" | grep -o '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)
            code=$(echo "$line" | grep -o '"http_code":[0-9]*' | cut -d: -f2)
            blocked=$(echo "$line" | grep -o '"is_interrupted":[a-z]*' | cut -d: -f2)
            rules=$(echo "$line" | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')
            echo "$id  $code  blocked=$blocked  $uri"
            echo "    rules: $rules"
        done ;;
    *)
        docker compose exec -T nginx-waf grep "\"unique_id\":\"$1\"" "$LOG" ;;
esac
