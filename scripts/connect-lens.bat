@echo off
chcp 65001 >nul
REM Lens 连接 Minikube 自动化脚本（双击运行）

echo ========================================
echo    Lens 连接 Minikube 自动化工具
echo ========================================
echo.

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

REM 检查 PowerShell 脚本是否存在
if not exist "connect-lens.ps1" (
    echo [错误] 找不到 connect-lens.ps1 脚本
    pause
    exit /b 1
)

REM 运行 PowerShell 脚本（绕过执行策略）
echo 正在启动 PowerShell 脚本...
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%connect-lens.ps1"

echo.
echo ========================================
echo.
echo 按任意键关闭窗口...
pause >nul
