@echo off
chcp 65001 >nul
rem Máy nạn nhân, Demo 1: bấm đúp để đánh sập backend-node-1. Nginx tự chuyển request sang node 2.
rem Xong demo bấm đúp Demo1-BatNode1.bat để bật lại.
setlocal
cd /d "%~dp0.."
echo Đang tắt backend-node-1...
docker compose stop backend-node-1
if errorlevel 1 goto failed
echo.
echo Đã tắt backend-node-1. Máy tấn công vẫn dùng tiếp được, Nginx chuyển sang node 2.
echo Xong Demo 1 nhớ bấm đúp Demo1-BatNode1.bat để bật lại.
goto end

:failed
echo LỖI: không tắt được backend-node-1. Kiểm tra Docker Desktop đang chạy và hệ thống đã được dựng.

:end
echo.
pause
