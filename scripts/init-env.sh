#!/bin/sh
# Sinh file .env với mọi mật khẩu/khóa ngẫu nhiên. Chạy từ thư mục gốc repo (Git Bash):
#   sh scripts/init-env.sh
# Không ghi đè .env đã có; không in giá trị bí mật ra màn hình.
set -eu
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    echo ".env đã tồn tại, không ghi đè. Xóa file đó nếu muốn sinh lại (nhớ chạy 'docker compose down -v')."
    exit 1
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
SQLI_LAB_AUTH_ADMIN_PASSWORD=$(hex)
SQLI_LAB_AUTH_APP_PASSWORD=$(hex)
SQLI_LAB_ADMIN_PASSWORD=$(hex)
SQLI_LAB_READER_PASSWORD=$(hex)
SQLI_LAB_JWT_SECRET=$(b64)
EOF
echo "Đã tạo .env (10 biến, giá trị ngẫu nhiên)."
