#!/bin/sh
# Demo 2 - Vá ảo tại tầng biên (Virtual Patching / Integrity).
# Endpoint /api/v1/vuln/records/search CÓ LỖI SQLi (nối chuỗi), chạy ngay trên backend chính.
# Bật WAF: payload bị chặn 403 tại Nginx, request không tới được code Java, dù code chưa được vá.
# Cần: docker compose up -d, WAF_MODE=On.
. "$(dirname "$0")/common.sh"
PAYLOAD="' OR '1'='1"

title "Demo 2: Virtual Patching tại WAF"
TA=$(login "$USER_A" "$PASS_A") || exit 1
note "User A đăng nhập qua Nginx."

title "Bước 1: request bình thường đi qua WAF"
s=$(req POST /api/v1/vuln/records/search "$TA" '{"keyword":"alpha"}')
note "keyword=alpha -> HTTP $s, body: $(body)"
check "Request hợp lệ tới được backend" 200 "$s"

title "Bước 2: tiêm SQLi  keyword=$PAYLOAD"
s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
RID=$(last_rid)
note "HTTP $s, X-Blocked-By: $(header X-Blocked-By), rid $RID"
note "body: $(body)"
check "WAF chặn payload SQLi" 403 "$s"
check "Header đánh dấu do WAF chặn (không phải backend)" waf "$(header X-Blocked-By)"

title "Bước 3: bằng chứng trong audit log ModSecurity (unique_id = rid)"
sleep 1
ENTRY=$(waf_audit "$RID")
RULES=$(echo "$ENTRY" | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')
note "Luật đã khớp: $RULES"
echo "$ENTRY" | grep -o '"message":"[^"]*"' | sort -u | sed 's/^/  /'
case " $RULES " in *" 100100 "*) R=có ;; *) R=không ;; esac
check "Custom rule vá ảo 100100 có trong audit log" có "$R"

title "Bước 4: backend không hề nhận request bị chặn"
N=$(backend_logs | grep -c "$RID")
check "Số dòng log backend có rid của request bị chặn" 0 "$N"

title "Bước 5: OWASP CRS cũng chặn payload này ở route secure (luật chung, không cần biết lỗ hổng)"
s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID2=$(last_rid)
sleep 1
RULES2=$(waf_audit "$RID2" \
    | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')
note "HTTP $s, luật CRS đã khớp: $RULES2"
check "CRS chặn SQLi ở route secure" 403 "$s"

summary
