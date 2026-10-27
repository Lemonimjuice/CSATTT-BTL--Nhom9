#!/bin/sh
# Kiểm tra nhanh trước khi trình bày / chấm bài. Chạy từ thư mục gốc repo (Git Bash):
#   sh scripts/preflight.sh
# In [PASS] / [WARN] / [FAIL] cho từng mục kèm cách sửa. Thoát mã 1 nếu có mục FAIL.
# Chỉ đọc trạng thái, không sửa gì (ngoại lệ: 1 lần đăng nhập thử và 1 request XSS mẫu để kiểm tra WAF).
set -u
cd "$(dirname "$0")/.."
CA=nginx/certs/server.crt
HDR=$(mktemp)
trap 'rm -f "$HDR"' EXIT
# Git Bash: không đổi "/etc/..." thành "C:/Program Files/Git/etc/..." khi truyền vào container.
# Chỉ áp cho lệnh docker exec; curl trên Windows vẫn cần Git Bash đổi đường dẫn file tạm.
dexec() { MSYS_NO_PATHCONV=1 docker compose exec -T "$@"; }
WAF_IMAGE=owasp/modsecurity-crs@sha256:873ce68a658d2e3b61484a8a24d215f7d15456e7ce5aec5e7114bf000d743365
P=0; W=0; F=0
pass() { P=$((P+1)); printf '  [PASS] %s\n' "$1"; }
warn() { W=$((W+1)); printf '  [WARN] %s\n         -> %s\n' "$1" "$2"; }
fail() { F=$((F+1)); printf '  [FAIL] %s\n         -> %s\n' "$1" "$2"; }
envval() { grep "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-; }

echo "== Máy và Docker"
if docker info >/dev/null 2>&1; then pass "Docker đang chạy"; else
    fail "Không kết nối được Docker" "Mở Docker Desktop, chờ biểu tượng chuyển xanh rồi chạy lại"; echo; echo "Kết quả: $P PASS, $W WARN, $F FAIL"; exit 1; fi
for img in "$WAF_IMAGE" postgres:16-alpine nhom9/blog-api:local; do
    if docker image inspect "$img" >/dev/null 2>&1; then pass "Có sẵn image ${img%%@*}"; else
        warn "Chưa có image ${img%%@*} trên máy" "Lần dựng tới cần Internet: chạy 'docker compose up -d --build --wait' trước buổi trình bày"; fi
done

echo "== Cấu hình"
if [ -f .env ]; then
    miss=""; for k in DB_ADMIN_PASSWORD APP_DB_USERNAME APP_DB_PASSWORD JWT_SECRET SQLI_LAB_READER_PASSWORD; do
        [ -n "$(envval $k)" ] || miss="$miss $k"; done
    if [ -z "$miss" ]; then pass ".env có đủ biến"; else fail ".env thiếu:$miss" "Xóa .env rồi chạy 'sh scripts/init-env.sh', sau đó 'docker compose down -v'"; fi
    [ "$(envval APP_DB_PASSWORD | tr -d '\r' | wc -c)" -ge 24 ] && pass "APP_DB_PASSWORD đủ 24 ký tự" \
        || fail "APP_DB_PASSWORD ngắn hơn 24 ký tự" "Sinh lại .env bằng scripts/init-env.sh"
    jb=$(envval JWT_SECRET | tr -d '\r' | openssl base64 -d -A 2>/dev/null | wc -c)
    [ "$jb" -ge 32 ] && pass "JWT_SECRET là Base64 của $jb byte" \
        || fail "JWT_SECRET không phải Base64 >= 32 byte (backend sẽ không khởi động)" "Sinh lại .env bằng scripts/init-env.sh"
    case "$(envval WAF_MODE | tr -d '\r')" in
        ""|On) pass "WAF_MODE trong .env là On" ;;
        DetectionOnly) warn "WAF_MODE trong .env là DetectionOnly (WAF không chặn)" "Sửa .env thành WAF_MODE=On" ;;
        *) fail "WAF_MODE trong .env không hợp lệ" "Chỉ dùng On hoặc DetectionOnly" ;;
    esac
else
    fail "Chưa có file .env" "Chạy: sh scripts/init-env.sh"
fi
if [ -f "$CA" ] && [ -f nginx/certs/server.key ]; then
    if openssl x509 -in "$CA" -noout -checkend 604800 >/dev/null 2>&1; then pass "Chứng chỉ còn hạn trên 7 ngày"; else
        warn "Chứng chỉ hết hạn trong 7 ngày tới" "FORCE=1 sh nginx/certs/generate-cert.sh rồi 'docker compose restart nginx-waf'"; fi
else
    fail "Chưa có chứng chỉ" "Chạy: sh nginx/certs/generate-cert.sh"
fi
if [ -d logs/nginx ] && [ -d logs/waf ] && [ -d logs/backend-node-1 ] && [ -d logs/backend-node-2 ]; then pass "Có đủ thư mục logs/"; else
    warn "Thiếu thư mục logs/" "Chạy: sh scripts/init-env.sh (bắt buộc trên Linux)"; fi

echo "== Hệ thống đang chạy"
st=$(docker compose ps --format '{{.Service}}={{.Health}}' 2>/dev/null)
bad=""; for s in nginx-waf backend-node-1 backend-node-2 database; do
    echo "$st" | grep -qx "$s=healthy" || bad="$bad $s"; done
if [ -n "$bad" ]; then
    fail "Container chưa healthy:$bad" "Chạy 'docker compose up -d --build --wait'; backend báo 'SQLi lab isolation check failed' thì cần 'docker compose down -v'"
    echo; echo "Kết quả: $P PASS, $W WARN, $F FAIL"; exit 1
fi
pass "4 container healthy"
if dexec nginx-waf grep -q 'SecRuleEngine DetectionOnly' /etc/nginx/modsecurity-mode.conf 2>/dev/null; then
    warn "WAF đang chạy DetectionOnly (không chặn)" "Chạy: sh scripts/waf-mode.sh On"; else pass "WAF đang chạy chế độ On"; fi
db() { dexec database psql -U postgres_admin -d blogdb -tAc "$1" 2>/dev/null | tr -d '\r'; }
[ "$(db "select 1 from pg_database where datname='sqli_lab'")" = 1 ] && pass "Có database sqli_lab cho cụm /vuln" \
    || fail "Thiếu database sqli_lab (volume DB từ bản cũ)" "Chạy: sh scripts/reset-demo.sh --yes"
case "$(db "select status || '|' || title from posts where id = 3")" in
    "DRAFT|Bản nháp bí mật của User A") pass "Dữ liệu mẫu còn nguyên (bài 3 là nháp gốc của User A)" ;;
    "") warn "Không còn bài 3 (đã bị xóa)" "Demo 4 cần bài 3: chạy sh scripts/reset-demo.sh --yes" ;;
    *) warn "Bài 3 đã bị sửa (thường do chạy demo IDOR)" "Muốn dữ liệu sạch cho buổi trình bày: sh scripts/reset-demo.sh --yes" ;;
esac

echo "== Qua Nginx (https://localhost)"
nodes=""; ok=0
for i in 1 2 3 4; do
    s=$(curl -s --cacert "$CA" -o /dev/null -D "$HDR" -w '%{http_code}' https://localhost/actuator/health)
    [ "$s" = 200 ] && ok=$((ok+1)); nodes="$nodes $(grep -i '^x-upstream' "$HDR" | tr -d '\r' | cut -d' ' -f2)"
done
[ "$ok" = 4 ] && pass "HTTPS qua Nginx trả 200 (chứng chỉ hợp lệ)" || fail "HTTPS qua Nginx lỗi ($ok/4 lần 200)" "Xem logs/nginx/error.log"
[ "$(echo $nodes | tr ' ' '\n' | sort -u | grep -c .)" -ge 2 ] && pass "Cả 2 node backend đang nhận request" \
    || warn "Chỉ 1 node nhận request" "Có thể một node đang tắt (sau Demo 1): docker compose start backend-node-1"
s=$(curl -s --cacert "$CA" -o /dev/null -D "$HDR" -w '%{http_code}' "https://localhost/api/v1/posts/search?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E")
[ "$s" = 403 ] && grep -qi '^x-blocked-by: waf' "$HDR" && pass "WAF chặn request XSS mẫu (403, X-Blocked-By: waf)" \
    || fail "WAF không chặn request XSS mẫu (HTTP $s)" "Kiểm tra chế độ WAF: sh scripts/waf-mode.sh"
s=$(curl -s --cacert "$CA" -o /dev/null -w '%{http_code}' -X POST https://localhost/api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"user_a","password":"UserA@Nhom9-2026"}')
case "$s" in
    200) pass "Đăng nhập user_a thành công" ;;
    429) warn "Đăng nhập đang bị rate limit (429)" "Chờ khoảng 1 phút rồi thử lại" ;;
    *) fail "Đăng nhập user_a lỗi (HTTP $s)" "Dữ liệu mẫu có thể chưa nạp: sh scripts/reset-demo.sh --yes" ;;
esac

echo; echo "Kết quả: $P PASS, $W WARN, $F FAIL"
[ "$F" -eq 0 ]
