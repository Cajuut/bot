@echo off
echo Check for Node.js...
node -v >nul 2>&1
if %errorlevel% neq 0 (
    echo Node.js is not installed or not in PATH. Please install Node.js.
    pause
    exit /b
)

echo Setting up Node Bot...
cd node_bot
if not exist node_modules (
    echo Installing dependencies...
    call npm install
)
cd ..

echo Starting Flutter UI...
cd flutter_ui
call flutter run -d windows
pause
