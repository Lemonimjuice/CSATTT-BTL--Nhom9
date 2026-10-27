#!/bin/sh
# Demo 4 - Phòng thủ logic phân quyền (chống IDOR / Broken Access Control, mô hình AAA).
# User B dùng ID bài NHÁP của User A (post 3). Request không có ký tự độc hại nên WAF cho qua;
# tầng Service của Spring Boot đối chiếu JWT với chủ sở hữu và trả 403.
# Cặp đối chứng: bản vá /api/v1/secure/posts vs bản lỗi /api/v1/vuln/posts (cùng backend chính).
. "$(dirname "$0")/common.sh"
POST_A_DRAFT=3

title "Demo 4: chống IDOR"
TA=$(login "$USER_A" "$PASS_A") || exit 1
TB=$(login "$USER_B" "$PASS_B") || exit 1

title "Bước 1: chủ sở hữu (User A) đọc bản nháp của mình trên bản vá"
s=$(req GET /api/v1/secure/posts/$POST_A_DRAFT "$TA")
check "User A đọc nháp của mình" 200 "$s"

title "Bước 2: User B tấn công bài nháp của A trên bản VÁ /api/v1/secure/posts/$POST_A_DRAFT"
s=$(req GET /api/v1/secure/posts/$POST_A_DRAFT "$TB"); note "GET    -> $s  $(body)"
check "B đọc nháp của A" 403 "$s"
check "403 này do backend, không phải WAF (không có X-Blocked-By)" "" "$(header X-Blocked-By)"
s=$(req PUT /api/v1/secure/posts/$POST_A_DRAFT "$TB" '{"title":"B da sua bai cua A"}'); RID=$(last_rid); note "PUT    -> $s"
check "B sửa bài của A" 403 "$s"
s=$(req DELETE /api/v1/secure/posts/$POST_A_DRAFT "$TB"); note "DELETE -> $s"
check "B xóa bài của A" 403 "$s"

title "Bước 3: chưa đăng nhập -> 401 (phân biệt với 403 khi đã đăng nhập nhưng không có quyền)"
s=$(req PUT /api/v1/secure/posts/$POST_A_DRAFT "" '{"title":"x"}')
check "PUT không có token" 401 "$s"
s=$(req GET /api/v1/secure/posts/$POST_A_DRAFT "")
check "Đọc nháp không có token (bản vá)" 401 "$s"
s=$(req GET /api/v1/posts/$POST_A_DRAFT "")
check "Đọc nháp không có token qua route công khai" 401 "$s"

title "Bước 4: audit log backend ghi lại lần bị từ chối (username, IP thật, rid)"
sleep 1
backend_logs | grep "$RID" | sed 's/^/  /'
N=$(backend_logs | grep "$RID" | grep -c 'user=user_b')
check "Log backend có rid + user_b cho request bị từ chối" 1 "$([ "$N" -ge 1 ] && echo 1 || echo 0)"

title "Đối chứng: bản LỖI /api/v1/vuln/posts (cùng backend, cùng token)"
s=$(req GET /api/v1/vuln/posts/$POST_A_DRAFT "")
note "GET không token -> $s  $(body)"
check "Bản lỗi: ai cũng đọc được nháp, không cần đăng nhập (lỗi gốc)" 200 "$s"
s=$(req GET /api/v1/vuln/posts/$POST_A_DRAFT "$TB")
note "GET -> $s  $(body)"
check "Bản lỗi: B đọc được nháp của A" 200 "$s"
check "Bản lỗi: lộ email tác giả" 1 "$(body | grep -c 'user_a@nhom9.test')"
s=$(req PUT /api/v1/vuln/posts/$POST_A_DRAFT "$TB" '{"title":"B da sua bai cua A"}')
check "Bản lỗi: B sửa được bài của A (IDOR)" 200 "$s"

summary
