@echo off
chcp 65001 >nul
rem Máy nạn nhân: bấm đúp để mở cửa sổ xem log 3 lớp (Nginx, WAF, backend) theo thời gian thực.
rem Đầu cửa sổ in địa chỉ IP để máy tấn công gọi tới. Đóng cửa sổ hoặc Ctrl+C để dừng.
title Nhom 9 - Log phong thu (may nan nhan)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0xem-log.ps1" %*
echo.
pause
