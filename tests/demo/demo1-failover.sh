#!/bin/sh
# Demo 1 - Tính sẵn sàng cao (HA & Failover).
# Đăng nhập 1 lần, tắt backend-node-1, dùng tiếp token cũ: Nginx tự chuyển sang node 2,
# không phải đăng nhập lại vì JWT stateless và 2 node dùng chung JWT secret + CSDL.
. "$(dirname "$0")/common.sh"

title "Demo 1: HA & Failover"
TA=$(login /api/v1/auth/login "$USER_A" "$PASS_A") || exit 1
note "User A đã đăng nhập qua Nginx (token chỉ giữ trong biến, không in ra)."

title "Bước 1: cả 2 node đang chạy, Round-Robin"
NODES=""
for i in 1 2 3 4; do
    s=$(req GET /api/v1/posts/me "$TA"); up=$(header X-Upstream)
    note "request $i -> HTTP $s, node $up, rid $(last_rid)"
    NODES="$NODES $up"
done
DISTINCT=$(echo $NODES | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')
check "Số node khác nhau đã phục vụ" 2 "$DISTINCT"

title "Bước 2: đánh sập backend-node-1"
docker compose stop backend-node-1 >/dev/null 2>&1
note "docker compose stop backend-node-1 -> $(docker compose ps -a backend-node-1 --format '{{.State}}')"

title "Bước 3: dùng tiếp token cũ, không đăng nhập lại"
OK=0
for i in 1 2 3 4 5 6; do
    s=$(req GET /api/v1/posts/me "$TA")
    note "request $i -> HTTP $s, node(s) $(header X-Upstream)"
    [ "$s" = 200 ] && OK=$((OK+1))
done
check "Request thành công sau khi node 1 sập (6 lần)" 6 "$OK"

title "Log Nginx (5 dòng cuối): upstream có 2 địa chỉ = đã thử node 1 rồi chuyển sang node 2"
docker compose logs --no-log-prefix --tail 40 nginx-waf 2>/dev/null | grep 'posts/me' | tail -5 | sed 's/^/  /'

title "Bước 4: bật lại backend-node-1"
docker compose start backend-node-1 >/dev/null 2>&1
for i in $(seq 1 40); do
    [ "$(docker compose ps backend-node-1 --format '{{.Health}}')" = healthy ] && break; sleep 3
done
check "backend-node-1 hoạt động trở lại" healthy "$(docker compose ps backend-node-1 --format '{{.Health}}')"

summary
