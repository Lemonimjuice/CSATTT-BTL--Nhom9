@echo off
chcp 65001 >nul
rem Máy nạn nhân, Demo 1: bấm đúp để bật lại backend-node-1 và chờ tới khi node khỏe (healthy).
setlocal
cd /d "%~dp0.."
echo Đang bật lại backend-node-1, chờ khoảng 30-60 giây...
docker compose up -d --no-deps --wait backend-node-1
if errorlevel 1 goto failed
echo.
echo backend-node-1 đã chạy lại, Nginx chia tải cho cả 2 node như trước.
goto end

:failed
echo LỖI: backend-node-1 chưa khỏe. Xem log: docker compose logs --tail 50 backend-node-1

:end
echo.
pause
