#!/bin/sh
# Demo 3 - Phòng thủ chiều sâu tại CSDL (Defense in Depth).
# Giả sử WAF bị lách luật: chuyển WAF sang DetectionOnly (chỉ ghi log, không chặn) để payload
# lọt vào backend. So sánh:
#   - cụm lỗi /api/v1/vuln (nối chuỗi)             -> payload đổi câu SQL, lộ toàn bộ dữ liệu giả
#   - cụm vá  /api/v1/secure (Parameterized Query) -> payload chỉ là chuỗi thường, không lộ gì
# Script tự trả WAF về chế độ On khi kết thúc.
. "$(dirname "$0")/common.sh"
PAYLOAD="' OR '1'='1"

restore_waf() {
    WAF_MODE=On docker compose up -d --no-deps --force-recreate nginx-waf >/dev/null 2>&1
    sleep 3
}

title "Demo 3: Defense in Depth"
title "Bước 1: giả lập WAF bị lách -> WAF_MODE=DetectionOnly"
WAF_MODE=DetectionOnly docker compose up -d --no-deps --force-recreate nginx-waf >/dev/null 2>&1
sleep 3
trap 'restore_waf; rm -rf "$TMP"' EXIT
note "nginx-waf đã khởi động lại với SecRuleEngine DetectionOnly"

TA=$(login "$USER_A" "$PASS_A") || exit 1

title "Bước 2: payload lọt vào cụm LỖI /api/v1/vuln/records/search"
s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
ROWS=$(body | grep -o '"id"' | wc -l | tr -d ' ')
note "HTTP $s, X-Blocked-By: '$(header X-Blocked-By)', số dòng trả về: $ROWS"
note "body: $(body)"
check "WAF không chặn (đang DetectionOnly)" 200 "$s"
check "SQLi thành công ở bản lỗi: lộ cả 3 dòng thay vì 0" 3 "$ROWS"

title "Bước 3: cùng payload vào cụm VÁ /api/v1/secure/records/search"
s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID=$(last_rid)
note "HTTP $s, body: $(body)"
check "Backend nhận request (WAF không chặn)" 200 "$s"
check "Parameterized Query: payload là chuỗi literal, không khớp Record nào" "[]" "$(body)"

title "Bước 4: SQLi ở bản lỗi KHÔNG chạm được bảng users của blogdb (database riêng)"
s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"x' UNION SELECT id, username FROM public.users --\"}")
note "UNION sang public.users -> HTTP $s, body: $(body)"
check "Truy vấn chéo database bị chặn, không lộ users (400)" 400 "$s"

title "Bước 5: WAF vẫn ghi nhận tấn công dù không chặn (bằng chứng cho đội vận hành)"
sleep 1
s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID=$(last_rid); sleep 1
ENTRY=$(waf_audit "$RID")
note "is_interrupted: $(echo "$ENTRY" | grep -o '"is_interrupted":[a-z]*' | cut -d: -f2)"
note "luật đã khớp: $(echo "$ENTRY" | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')"
check "Audit log có bản ghi phát hiện" 1 "$(echo "$ENTRY" | grep -c unique_id)"

title "Bước 6: trả WAF về chế độ On"
restore_waf
trap 'rm -rf "$TMP"' EXIT
s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
check "WAF chặn lại như bình thường" 403 "$s"

summary
