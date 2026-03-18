@echo off
title DocFX Build and Deploy
cd /d "%~dp0"

echo.
echo ========================================
echo Starting DocFX Build with PDF...
echo ========================================
echo.

powershell -ExecutionPolicy Bypass -File ".\build-with-pdf.ps1"

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo Build completed successfully!
    echo Starting GitHub Pages Deployment...
    echo ========================================
    echo.
    
    powershell -ExecutionPolicy Bypass -File ".\deploy-gh-pages.ps1"
    
    if %errorlevel% equ 0 (
        echo.
        echo ========================================
        echo Deployment completed successfully!
        echo ========================================
    ) else (
        echo.
        echo ========================================
        echo Deployment failed with error level %errorlevel%
        echo ========================================
    )
) else (
    echo.
    echo ========================================
    echo Build failed with error level %errorlevel%
    echo ========================================
)

echo.
echo Press any key to exit...
pause >nul
