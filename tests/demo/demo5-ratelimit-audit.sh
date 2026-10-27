#!/bin/sh
# Kiểm chứng bổ sung cho Mục tiêu 1 và 3 của đề cương:
#   - Rate Limiting chống brute-force đăng nhập (429)
#   - Accounting: IP client giả trong X-Forwarded-For không lọt vào audit log
#   - Một request ID xuyên suốt log Nginx, audit log WAF và log backend
. "$(dirname "$0")/common.sh"

title "Bổ sung 1: brute-force đăng nhập bị rate limit (5 request/phút mỗi IP)"
sleep 13   # để vùng rate limit đăng nhập hồi lại sau các demo trước
CODES=""
for i in $(seq 1 8); do
    CODES="$CODES $(req POST /api/v1/auth/login "" '{"username":"user_a","password":"sai-mat-khau"}')"
done
note "8 lần đoán mật khẩu liên tiếp ->$CODES"
N429=$(echo $CODES | tr ' ' '\n' | grep -c 429)
check "Có request bị chặn 429" 1 "$([ "$N429" -ge 1 ] && echo 1 || echo 0)"
check "Request đầu tiên vẫn tới backend (401 sai mật khẩu)" 401 "$(echo $CODES | cut -d' ' -f1)"

title "Bổ sung 2: client tự gửi X-Forwarded-For giả"
s=$(curl -s --cacert "$CA" -o /dev/null -D "$TMP/head" -w '%{http_code}' -H 'X-Forwarded-For: 6.6.6.6' -H 'X-Real-IP: 6.6.6.6' "$BASE/api/v1/posts")
RID=$(last_rid); sleep 1
LINE=$(backend_logs | grep "$RID")
note "$LINE"
check "IP giả 6.6.6.6 không xuất hiện trong log backend" 0 "$(echo "$LINE" | grep -c '6\.6\.6\.6')"
check "Log backend có IP client thật (không phải IP Nginx 10.209.10.10)" 0 "$(echo "$LINE" | grep -c 'ip=10\.209\.10\.10')"

title "Bổ sung 3: một request ID xuyên suốt 3 lớp"
TA=$(login "$USER_A" "$PASS_A") || exit 1
s=$(req POST /api/v1/secure/records/search "$TA" '{"keyword":"alpha<script>alert(1)</script>"}'); RID=$(last_rid); sleep 1
NG=$(nginx_log | grep -c "rid=$RID")
WAF=$(waf_audit "$RID" | wc -l | tr -d " ")
note "XSS vào route secure -> HTTP $s, rid $RID: log Nginx $NG dòng, audit WAF $WAF dòng"
check "Nginx và WAF cùng ghi rid" "1 1" "$NG $WAF"
s=$(req POST /api/v1/secure/records/search "$TA" '{"keyword":"alpha"}'); RID=$(last_rid); sleep 1
BE=$(backend_logs | grep -c "$RID")
note "Request hợp lệ -> HTTP $s, rid $RID: log backend $BE dòng"
check "Backend ghi đúng rid do Nginx sinh" 1 "$([ "$BE" -ge 1 ] && echo 1 || echo 0)"

title "Bổ sung 4: chỉ mở đúng những gì cần ra ngoài"
check "Swagger UI không công khai" 404 "$(req GET /swagger-ui/index.html "")"
check "Tài liệu OpenAPI không công khai" 404 "$(req GET /v3/api-docs "")"
check "Actuator khác health không công khai" 404 "$(req GET /actuator/env "")"
P80=$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost/ 2>/dev/null || true)
check "Cổng 80 đóng (chỉ mở 443 theo đề cương)" 000 "$P80"

summary
