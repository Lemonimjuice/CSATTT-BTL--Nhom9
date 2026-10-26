#!/bin/sh
# Chạy lần lượt mọi demo. Yêu cầu stack đang chạy kèm lab:
#   docker compose --profile lab up -d --build --wait
# Dùng: sh tests/demo/run-all.sh
cd "$(dirname "$0")"
FAILED=""
for d in demo1-failover demo2-waf-virtual-patch demo3-defense-in-depth demo4-idor demo5-ratelimit-audit; do
    sh "./$d.sh" || FAILED="$FAILED $d"
done
echo
if [ -z "$FAILED" ]; then echo "TẤT CẢ DEMO ĐẠT"; else echo "DEMO CÓ LỖI:$FAILED"; exit 1; fi
