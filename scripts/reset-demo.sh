#!/bin/sh
# Đưa hệ thống về trạng thái sạch trước buổi trình bày. Chạy từ thư mục gốc repo (Git Bash):
#   sh scripts/reset-demo.sh --yes
# XÓA toàn bộ dữ liệu trong DB (volume postgres_data) và các file log trong logs/,
# rồi dựng lại từ đầu với dữ liệu mẫu và chạy preflight. Giữ nguyên .env và chứng chỉ.
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" != "--yes" ]; then
    echo "Lệnh này XÓA dữ liệu DB và log để dựng lại hệ thống sạch."
    echo "Chạy lại kèm xác nhận: sh scripts/reset-demo.sh --yes"
    exit 2
fi

echo "== Dừng hệ thống và xóa volume DB"
docker compose down -v
echo "== Xóa log cũ"
rm -rf logs/nginx logs/waf logs/backend-node-1 logs/backend-node-2
sh scripts/init-env.sh
sh nginx/certs/generate-cert.sh
echo "== Dựng lại (lần đầu có thể mất vài phút)"
docker compose up -d --build --wait --wait-timeout 400
echo "== Kiểm tra"
sh scripts/preflight.sh
