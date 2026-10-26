#!/bin/sh
# Demo 2 - Vá ảo tại tầng biên (Virtual Patching / Integrity).
# Endpoint /api/v1/vuln/records/search CÓ LỖI SQLi (nối chuỗi). Bật WAF: payload bị chặn 403
# ngay tại Nginx, request không tới được code Java, dù code chưa được vá.
# Cần: docker compose --profile lab up -d, WAF_MODE=On.
. "$(dirname "$0")/common.sh"
PAYLOAD="' OR '1'='1"

title "Demo 2: Virtual Patching tại WAF"
LA=$(login /lab/api/v1/auth/login "$USER_A" "$PASS_A") || exit 1
note "User A đăng nhập vào lab cô lập (JWT riêng của lab)."

title "Bước 1: request bình thường đi qua WAF"
s=$(req POST /api/v1/vuln/records/search "$LA" '{"keyword":"alpha"}')
note "keyword=alpha -> HTTP $s, body: $(body)"
check "Request hợp lệ tới được backend lab" 200 "$s"

title "Bước 2: tiêm SQLi  keyword=$PAYLOAD"
s=$(req POST /api/v1/vuln/records/search "$LA" "{\"keyword\":\"$PAYLOAD\"}")
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

title "Bước 4: backend lab không hề nhận request bị chặn"
N=$(docker compose logs --no-log-prefix sqli-lab-api 2>/dev/null | grep -c "$RID")
check "Số dòng log backend có rid của request bị chặn" 0 "$N"

title "Bước 5: OWASP CRS cũng chặn payload này ở route secure (luật chung, không cần biết lỗ hổng)"
TA=$(login /api/v1/auth/login "$USER_A" "$PASS_A") || exit 1
s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID2=$(last_rid)
sleep 1
RULES2=$(waf_audit "$RID2" \
    | grep -o '"ruleId":"[0-9]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')
note "HTTP $s, luật CRS đã khớp: $RULES2"
check "CRS chặn SQLi ở route secure" 403 "$s"

summary
