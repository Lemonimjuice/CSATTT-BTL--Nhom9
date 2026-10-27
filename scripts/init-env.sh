#!/bin/sh
# Chuẩn bị môi trường chạy. Chạy từ thư mục gốc repo (Git Bash), chạy lại nhiều lần cũng an toàn:
#   sh scripts/init-env.sh
# 1. Tạo các thư mục logs/ mà container ghi vào (audit log tập trung).
# 2. Sinh file .env với mọi mật khẩu/khóa ngẫu nhiên, nếu chưa có. Không in giá trị bí mật.
set -eu
cd "$(dirname "$0")/.."

# Tạo sẵn và cho phép ghi: trên Linux, nếu để Docker tự tạo thì thư mục thuộc root và Nginx (uid 101),
# backend (user blogapi) không ghi được log, Nginx sẽ không khởi động. Windows/macOS không bị ảnh hưởng.
mkdir -p logs/nginx logs/waf logs/backend-node-1 logs/backend-node-2
chmod 777 logs/nginx logs/waf logs/backend-node-1 logs/backend-node-2
echo "Thư mục logs/ đã sẵn sàng."

if [ -f .env ]; then
    echo ".env đã có, giữ nguyên. Muốn sinh lại: xóa .env rồi chạy lại script này (nhớ 'docker compose down -v')."
    exit 0
fi

hex() { openssl rand -hex 24; }
b64() { openssl rand -base64 32; }

umask 077
cat > .env <<EOF
DB_ADMIN_PASSWORD=$(hex)
APP_DB_USERNAME=app_user
APP_DB_PASSWORD=$(hex)
JWT_SECRET=$(b64)
WAF_MODE=On
SQLI_LAB_READER_PASSWORD=$(hex)
EOF
echo "Đã tạo .env (6 biến, giá trị ngẫu nhiên)."
