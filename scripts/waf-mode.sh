#!/bin/sh
# Đổi chế độ WAF mà không phải sửa .env. Chạy từ thư mục gốc repo (Git Bash):
#   sh scripts/waf-mode.sh               # xem chế độ đang chạy
#   sh scripts/waf-mode.sh DetectionOnly # chỉ ghi log, không chặn (Demo 3: giả lập WAF bị lách luật)
#   sh scripts/waf-mode.sh On            # chặn (mặc định, Demo 2)
# Chỉ khởi động lại container nginx-waf (vài giây); backend và database không bị ảnh hưởng.
set -eu
cd "$(dirname "$0")/.."

current() {
    if MSYS_NO_PATHCONV=1 docker compose exec -T nginx-waf grep -q 'SecRuleEngine DetectionOnly' /etc/nginx/modsecurity-mode.conf 2>/dev/null; then
        echo DetectionOnly
    else
        echo On
    fi
}

case "${1:-}" in
    "")
        echo "WAF đang ở chế độ: $(current)" ;;
    On|DetectionOnly)
        WAF_MODE=$1 docker compose up -d --no-deps --force-recreate --wait nginx-waf >/dev/null
        mode=$(current)
        echo "WAF đang ở chế độ: $mode"
        [ "$mode" = "$1" ] || { echo "LỖI: chưa đổi được sang $1"; exit 1; }
        if [ "$mode" = DetectionOnly ]; then
            echo "CẢNH BÁO: WAF chỉ ghi log, KHÔNG chặn. Xong Demo 3 nhớ chạy: sh scripts/waf-mode.sh On"
        fi ;;
    *)
        echo "Giá trị không hợp lệ: $1 (chỉ nhận On hoặc DetectionOnly, phân biệt hoa thường)"
        exit 2 ;;
esac
