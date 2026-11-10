#!/bin/sh
# Chạy trên MÁY TẤN CÔNG (Git Bash, không cần Docker): tấn công qua mạng LAN vào máy nạn nhân đang chạy hệ thống.
#   sh tests/lan/attacker.sh <IP_MÁY_NẠN_NHÂN> check   kiểm tra kết nối trước khi demo
#   sh tests/lan/attacker.sh <IP_MÁY_NẠN_NHÂN> demo1   (demo1 ... demo5) chạy một demo
#   sh tests/lan/attacker.sh <IP_MÁY_NẠN_NHÂN> all     check rồi demo1 -> demo5
# Bước phía nạn nhân (tắt node, đổi WAF, xem log) làm trên máy nạn nhân bằng file bấm đúp trong scripts/.
# Script tự đợi máy nạn nhân làm xong (tối đa WAIT_MAX giây, mặc định 120), không cần bấm Enter.
# Hướng dẫn đầy đủ: docs/demo-2-may.md
TARGET=${1:-}; WHAT=${2:-all}
case "$TARGET" in ""|-h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
BASE="https://$TARGET"; INSECURE=1
WAIT_MAX=${WAIT_MAX:-120}
. "$(dirname "$0")/../demo/common.sh"
PAYLOAD="' OR '1'='1"
POST_A_DRAFT=3

victim() { printf '\n  >>> MÁY NẠN NHÂN: %s\n\n' "$*"; }
now()    { date +%H:%M:%S; }

do_check() {
    title "Kiểm tra kết nối tới máy nạn nhân $TARGET"
    s=$(req GET /actuator/health "")
    check "HTTPS cổng 443 tới Nginx của máy nạn nhân" 200 "$s"
    if [ "$s" = 000 ]; then
        note "Không kết nối được. Kiểm tra: 2 máy cùng mạng, IP đúng (máy nạn nhân bấm scripts\\Xem-Log.bat để xem IP),"
        note "máy nạn nhân đang chạy hệ thống, tường lửa Windows của máy nạn nhân cho phép Docker Desktop."
        return 1
    fi
    note "Nginx trả lời, node phục vụ: $(header X-Upstream)"
    P80=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://$TARGET/" 2>/dev/null || true)
    check "Cổng 80 đóng (chỉ mở 443)" 000 "$P80"
    P8080=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://$TARGET:8080/" 2>/dev/null || true)
    check "Backend không mở cổng 8080 ra mạng" 000 "$P8080"
    if login "$USER_A" "$PASS_A" >/dev/null; then L=ok; else L=lỗi; fi
    check "Đăng nhập user_a qua mạng LAN" ok "$L"
}

do_demo1() {
    title "Demo 1 (máy tấn công): HA & Failover"
    TA=$(login "$USER_A" "$PASS_A") || return 1
    note "User A đăng nhập 1 lần; token chỉ giữ trong biến, không in ra."

    title "Bước 1: cả 2 node đang phục vụ (Round-Robin)"
    NODES=""
    for i in 1 2 3 4; do
        s=$(req GET /api/v1/posts/me "$TA"); up=$(header X-Upstream)
        note "request $i -> HTTP $s, node $up"; NODES="$NODES $up"
    done
    check "Số node khác nhau đã phục vụ" 2 "$(echo $NODES | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')"

    title "Bước 2: gửi liên tục bằng token cũ, chờ máy nạn nhân đánh sập node 1"
    victim "bấm đúp scripts\\Demo1-TatNode1.bat"
    note "Mỗi giây 1 request, chờ tối đa ${WAIT_MAX}s. X-Upstream có 2 địa chỉ = Nginx thử node sập rồi chuyển node."
    ERRS=0; SEEN=0; AFTER=0; DOWN=""; t=0
    while [ "$t" -lt "$WAIT_MAX" ]; do
        s=$(req GET /api/v1/posts/me "$TA"); up=$(header X-Upstream); mark=""
        [ "$s" = 200 ] || ERRS=$((ERRS+1))
        case "$up" in *,*) if [ "$SEEN" = 0 ]; then SEEN=1; DOWN=${up%%,*}
            mark="   <- $DOWN không trả lời, Nginx tự chuyển sang node còn lại"; fi ;; esac
        note "$(now)  HTTP $s  upstream $up$mark"
        if [ "$SEEN" = 1 ]; then AFTER=$((AFTER+1)); [ "$AFTER" -ge 6 ] && break; fi
        sleep 1; t=$((t+1))
    done
    check "Thấy node bị đánh sập trong thời gian chờ" 1 "$SEEN"
    check "Không request nào lỗi, vẫn dùng token cũ, không đăng nhập lại" 0 "$ERRS"
    [ "$SEEN" = 1 ] || return 1

    title "Bước 3: chờ máy nạn nhân bật lại node đã sập ($DOWN)"
    victim "bấm đúp scripts\\Demo1-BatNode1.bat (node khởi động mất khoảng 30-60 giây)"
    BACK=0; t=0; last=""
    while [ "$t" -lt $((WAIT_MAX * 2)) ]; do
        s=$(req GET /api/v1/posts/me "$TA"); up=$(header X-Upstream)
        [ "$up" != "$last" ] && note "$(now)  HTTP $s  upstream $up"; last=$up
        if [ "$s" = 200 ] && [ "$up" = "$DOWN" ]; then BACK=1; break; fi
        sleep 2; t=$((t+2))
    done
    check "Node đã sập phục vụ trở lại" 1 "$BACK"
}

do_demo2() {
    title "Demo 2 (máy tấn công): Virtual Patching tại WAF"
    TA=$(login "$USER_A" "$PASS_A") || return 1

    title "Bước 1: request bình thường đi qua WAF"
    s=$(req POST /api/v1/vuln/records/search "$TA" '{"keyword":"alpha"}')
    note "keyword=alpha -> HTTP $s, body: $(body)"
    check "Request hợp lệ tới được backend" 200 "$s"

    title "Bước 2: tiêm SQLi vào cụm LỖI  keyword=$PAYLOAD"
    s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID=$(last_rid)
    note "HTTP $s, X-Blocked-By: $(header X-Blocked-By), rid $RID"
    check "WAF chặn payload SQLi dù code Java chưa vá" 403 "$s"
    check "Do WAF chặn (header X-Blocked-By: waf)" waf "$(header X-Blocked-By)"
    victim "tra bằng chứng: bấm đúp scripts\\Tra-RequestID.bat, dán $RID (thấy luật 100100, backend không có dòng nào)"

    title "Bước 3: OWASP CRS cũng chặn payload này ở cụm secure"
    s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
    note "HTTP $s, rid $(last_rid)"
    check "CRS chặn SQLi ở route secure" 403 "$s"
}

# wait_probe MÃ: gửi payload SQLi vào cụm secure tới khi nhận MÃ (200 = WAF DetectionOnly, 403 = WAF On)
wait_probe() {
    t=0
    while [ "$t" -lt "$WAIT_MAX" ]; do
        s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
        [ "$s" = "$1" ] && break
        note "$(now)  payload -> HTTP $s, đang chờ máy nạn nhân..."
        sleep 3; t=$((t+3))
    done
    echo "$s" > "$TMP/probe"
}

do_demo3() {
    title "Demo 3 (máy tấn công): Defense in Depth"
    TA=$(login "$USER_A" "$PASS_A") || return 1

    title "Bước 1: chờ máy nạn nhân giả lập WAF bị lách (chế độ DetectionOnly)"
    victim "bấm đúp scripts\\WAF-DetectionOnly.bat"
    wait_probe 200; s=$(cat "$TMP/probe")
    check "Payload lọt qua WAF (DetectionOnly)" 200 "$s"
    [ "$s" = 200 ] || return 1

    title "Bước 2: payload vào cụm LỖI /api/v1/vuln/records/search"
    s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}")
    ROWS=$(body | grep -o '"id"' | wc -l | tr -d ' ')
    note "HTTP $s, số dòng trả về: $ROWS"
    note "body: $(body)"
    check "SQLi thành công ở bản lỗi: lộ cả 3 dòng thay vì 0" 3 "$ROWS"

    title "Bước 3: cùng payload vào cụm VÁ /api/v1/secure/records/search"
    s=$(req POST /api/v1/secure/records/search "$TA" "{\"keyword\":\"$PAYLOAD\"}"); RID=$(last_rid)
    note "HTTP $s, body: $(body), rid $RID"
    check "Parameterized Query: payload là chuỗi thường, không lộ gì" "[]" "$(body)"
    victim "tra $RID bằng scripts\\Tra-RequestID.bat: WAF ghi PHÁT HIỆN nhưng không chặn, backend vẫn trả []"

    title "Bước 4: SQLi ở bản lỗi KHÔNG chạm được bảng users của blogdb"
    s=$(req POST /api/v1/vuln/records/search "$TA" "{\"keyword\":\"x' UNION SELECT id, username FROM public.users --\"}")
    note "UNION sang public.users -> HTTP $s, body: $(body)"
    check "Truy vấn chéo database bị chặn (400)" 400 "$s"

    title "Bước 5: chờ máy nạn nhân bật lại WAF chế độ chặn"
    victim "bấm đúp scripts\\WAF-On.bat (QUAN TRỌNG: quên thì WAF chỉ ghi log, không chặn)"
    wait_probe 403
    check "WAF chặn lại như bình thường" 403 "$(cat "$TMP/probe")"
}

do_demo4() {
    title "Demo 4 (máy tấn công): chống IDOR"
    TA=$(login "$USER_A" "$PASS_A") || return 1
    TB=$(login "$USER_B" "$PASS_B") || return 1

    title "Bước 1: chủ sở hữu (User A) đọc bản nháp $POST_A_DRAFT của mình"
    check "User A đọc nháp của mình" 200 "$(req GET /api/v1/secure/posts/$POST_A_DRAFT "$TA")"

    title "Bước 2: User B tấn công bài nháp của A trên bản VÁ /api/v1/secure/posts/$POST_A_DRAFT"
    s=$(req GET /api/v1/secure/posts/$POST_A_DRAFT "$TB"); note "GET    -> $s  $(body)"
    check "B đọc nháp của A" 403 "$s"
    check "403 này do backend, không phải WAF (không có X-Blocked-By)" "" "$(header X-Blocked-By)"
    s=$(req PUT /api/v1/secure/posts/$POST_A_DRAFT "$TB" '{"title":"B da sua bai cua A"}'); RID=$(last_rid)
    note "PUT    -> $s  rid $RID"
    check "B sửa bài của A" 403 "$s"
    s=$(req DELETE /api/v1/secure/posts/$POST_A_DRAFT "$TB"); note "DELETE -> $s"
    check "B xóa bài của A" 403 "$s"
    victim "tra $RID bằng scripts\\Tra-RequestID.bat: log backend ghi user=user_b bị 403"

    title "Bước 3: chưa đăng nhập -> 401 (khác 403 khi đã đăng nhập nhưng không có quyền)"
    check "PUT không có token" 401 "$(req PUT /api/v1/secure/posts/$POST_A_DRAFT "" '{"title":"x"}')"
    check "Đọc nháp không có token (bản vá)" 401 "$(req GET /api/v1/secure/posts/$POST_A_DRAFT "")"

    title "Đối chứng: bản LỖI /api/v1/vuln/posts (cùng backend, cùng token)"
    s=$(req GET /api/v1/vuln/posts/$POST_A_DRAFT ""); note "GET không token -> $s  $(body)"
    check "Bản lỗi: ai cũng đọc được nháp, không cần đăng nhập" 200 "$s"
    s=$(req GET /api/v1/vuln/posts/$POST_A_DRAFT "$TB")
    check "Bản lỗi: lộ email tác giả" 1 "$(body | grep -c 'user_a@nhom9.test')"
    s=$(req PUT /api/v1/vuln/posts/$POST_A_DRAFT "$TB" '{"title":"B da sua bai cua A"}')
    check "Bản lỗi: B sửa được bài của A (IDOR)" 200 "$s"
}

do_demo5() {
    title "Bổ sung (máy tấn công): giả IP, cổng mở, brute-force"

    title "Bổ sung 1: tự gửi X-Forwarded-For giả để che IP"
    s=$(curl -s -k -o /dev/null -D "$TMP/head" -w '%{http_code}' -H 'X-Forwarded-For: 6.6.6.6' -H 'X-Real-IP: 6.6.6.6' "$BASE/api/v1/posts")
    RID=$(last_rid); note "HTTP $s, rid $RID"
    victim "tra $RID bằng scripts\\Tra-RequestID.bat: log backend KHÔNG có 6.6.6.6"

    title "Bổ sung 2: dò những gì mở ra mạng"
    check "Swagger UI không công khai" 404 "$(req GET /swagger-ui/index.html "")"
    check "Tài liệu OpenAPI không công khai" 404 "$(req GET /v3/api-docs "")"
    check "Actuator khác health không công khai" 404 "$(req GET /actuator/env "")"
    check "Cổng 80 đóng" 000 "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://$TARGET/" 2>/dev/null || true)"
    check "Cổng 8080 của backend đóng" 000 "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://$TARGET:8080/" 2>/dev/null || true)"

    title "Bổ sung 3 (để cuối): brute-force đăng nhập bị rate limit (5 lần/phút)"
    sleep 13   # để hạn mức đăng nhập hồi lại sau các lần đăng nhập ở demo trước
    CODES=""
    for i in $(seq 1 8); do
        CODES="$CODES $(req POST /api/v1/auth/login "" '{"username":"user_a","password":"sai-mat-khau"}')"
    done
    note "8 lần đoán mật khẩu liên tiếp ->$CODES"
    N429=$(echo $CODES | tr ' ' '\n' | grep -c 429)
    check "Có request bị chặn 429" 1 "$([ "$N429" -ge 1 ] && echo 1 || echo 0)"
    note "Đăng nhập bị chặn khoảng 1 phút. Docker Desktop gộp mọi máy thành 1 IP nên máy nạn nhân cũng bị tính chung."
}

case "$WHAT" in
    check|demo1|demo2|demo3|demo4|demo5) "do_$WHAT" ;;
    all)
        FAILED=""
        do_check || { summary; exit 1; }
        for d in demo1 demo2 demo3 demo4 demo5; do
            before=$FAIL_COUNT
            "do_$d" || true
            [ "$FAIL_COUNT" -gt "$before" ] && FAILED="$FAILED $d"
        done
        [ -n "$FAILED" ] && printf '\nPhần có lỗi:%s\n' "$FAILED" ;;
    *) echo "Không biết '$WHAT'. Dùng: check, demo1 ... demo5, all"; exit 2 ;;
esac
summary
