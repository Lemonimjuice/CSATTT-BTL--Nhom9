#!/bin/sh
# Xem audit log ModSecurity (JSON, mỗi dòng một giao dịch). Chạy từ thư mục gốc repo (Git Bash):
#   sh scripts/waf-audit.sh               # 5 giao dịch gần nhất, dạng tóm tắt
#   sh scripts/waf-audit.sh <request-id>  # giao dịch có unique_id = X-Request-ID, bản đầy đủ
# Đọc thẳng file trên máy (logs/waf/modsec_audit.log, mount từ container nginx-waf),
# nên vẫn xem được kể cả khi container đã dừng.
# Audit log không chứa header/body request (không lộ Authorization, mật khẩu).
set -eu
cd "$(dirname "$0")/.."
LOG=logs/waf/modsec_audit.log   # trùng SecAuditLog trong nginx/modsecurity/modsecurity.conf

if [ ! -s "$LOG" ]; then
    echo "Chưa có $LOG (hệ thống chưa chạy, hoặc WAF chưa ghi giao dịch nào)."
    exit 1
fi

case "${1:-}" in
    "")
        tail -n 5 "$LOG" | while IFS= read -r line; do
            id=$(echo "$line" | grep -o '"unique_id":"[^"]*"' | cut -d'"' -f4)
            uri=$(echo "$line" | grep -o '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)
            code=$(echo "$line" | grep -o '"http_code":[0-9]*' | cut -d: -f2)
            blocked=$(echo "$line" | grep -o '"is_interrupted":[a-z]*' | cut -d: -f2)
            rules=$(echo "$line" | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')
            echo "$id  $code  blocked=$blocked  $uri"
            echo "    rules: $rules"
        done ;;
    *)
        grep "\"unique_id\":\"$1\"" "$LOG" || { echo "Không có giao dịch nào với request ID $1 (WAF chỉ ghi request có luật khớp)."; exit 1; } ;;
esac
