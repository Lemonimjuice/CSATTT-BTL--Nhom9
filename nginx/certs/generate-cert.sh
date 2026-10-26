#!/bin/sh
# Sinh chứng chỉ tự ký cho Nginx (SSL Termination). Chạy từ thư mục gốc repo:
#   sh nginx/certs/generate-cert.sh          # không ghi đè nếu đã có
#   FORCE=1 sh nginx/certs/generate-cert.sh  # sinh lại
# server.key và server.crt bị .gitignore chặn, mỗi máy tự sinh, không commit.
set -eu

cd "$(dirname "$0")"
# Git Bash trên Windows tự đổi "/C=VN/..." thành đường dẫn Windows nếu không tắt.
export MSYS_NO_PATHCONV=1

if [ -f server.key ] && [ -f server.crt ] && [ "${FORCE:-0}" != "1" ]; then
    echo "Đã có server.key và server.crt; đặt FORCE=1 để sinh lại."
    exit 0
fi

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
    -keyout server.key -out server.crt \
    -subj "/C=VN/ST=Hanoi/L=Hanoi/O=PTIT/OU=CSATTT Nhom 9/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth"

chmod 600 server.key
chmod 644 server.crt
openssl x509 -in server.crt -noout -subject -enddate -ext subjectAltName
