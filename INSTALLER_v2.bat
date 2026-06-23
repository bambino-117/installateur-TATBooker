@echo off
REM UTF-8 Encoding without BOM
setlocal EnableDelayedExpansion
title TATBooker - Installation Automatique
color 0A

set "LOG_FILE=%TEMP%\tatbooker_install.log"
set "BACKUP_LOG=%TEMP%\tatbooker_install_backup.log"
set "APP_DIR=%USERPROFILE%\TATBooker"
set "REPO_URL=https://github.com/bambino-117/TATBooker---Developpement.git"
set "ERROR_COUNT=0"
set "STEP=0"
set "TOTAL_STEPS=12"

echo. > "%LOG_FILE%"
echo [%date% %time%] Installation TATBooker demarree >> "%LOG_FILE%"

cls
echo.
echo ================================================
echo   TATBooker - Installation Windows
echo   Version 2.0 Robuste
echo ================================================
echo.

echo [0/11] Verifications prealables...
echo [%time%] Phase 0 >> "%LOG_FILE%"

:: Check admin rights
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if !errorlevel! equ 0 (
    echo   OK: Droits administrateur detectes
    echo [OK] Admin >> "%LOG_FILE%"
) else (
    echo   ATTENTION: Execution sans droits administrateur
    echo   Certaines etapes pourraient echouer
    echo [WARN] No admin >> "%LOG_FILE%"
)
echo.

for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo   > Version Windows: %VERSION%
echo [INFO] Windows: %VERSION% >> "%LOG_FILE%"

if %VERSION% GEQ 10.0 (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    echo   > Long paths activés
)

for /f "tokens=3" %%a in ('dir /-c %USERPROFILE% ^| find "octets libres"') do set FREE_SPACE=%%a
set FREE_SPACE=%FREE_SPACE:~0,-3%
if %FREE_SPACE% LSS 3000000 (
    echo [ERREUR] Espace disque insuffisant
    pause
    exit /b 1
)
echo   > Espace disque: OK
echo.

for /f "tokens=*" %%a in ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>^&1') do set PS_VERSION=%%a
if !PS_VERSION! LSS 3 (
    echo [ERREUR] PowerShell 3.0+ requis
    pause
    exit /b 1
)
echo   > PowerShell v!PS_VERSION!: OK
echo.

if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set "ARCH=64"
    set "PYTHON_URL=https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    echo   > Architecture: 64-bit
) else (
    set "ARCH=32"
    set "PYTHON_URL=https://www.python.org/ftp/python/3.12.0/python-3.12.0.exe"
    echo   > Architecture: 32-bit
)
echo.

echo [1/11] Verification de Git...
echo [%time%] Phase 1: Git >> "%LOG_FILE%"

where git >nul 2>&1
if !errorlevel! neq 0 (
    echo   > Git non trouve
    echo [INFO] Git absent >> "%LOG_FILE%"
    echo   > Telechargement Git...
    
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.45.0.windows.1/Git-2.45.0-64-bit.exe"
    set "GIT_INSTALLER=%TEMP%\GitInstaller.exe"
    
    powershell -Command "try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%GIT_URL%' -OutFile '%GIT_INSTALLER%' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }" 2>>"%LOG_FILE%"
    if !errorlevel! equ 0 (
        if exist "!GIT_INSTALLER!" (
            start /wait "" "!GIT_INSTALLER!" /VERYSILENT /NORESTART /LOG="%TEMP%\git_install.log" >>"%LOG_FILE%" 2>&1
            del "!GIT_INSTALLER!" >nul 2>&1
            for /f "skip=2 tokens=3*" %%a in ('reg query HKCU\Environment /v PATH 2^>nul') do set "USER_PATH=%%a %%b"
            for /f "skip=2 tokens=3*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%a %%b"
            set "PATH=%SYSTEM_PATH%;%USER_PATH%;C:\Program Files\Git\cmd"
            where git >nul 2>&1
            if !errorlevel! equ 0 (
                echo   > Git installe avec succes
                echo [OK] Git >> "%LOG_FILE%"
            ) else (
                echo   > Echec detection Git
                goto :FALLBACK_GIT
            )
        )
    ) else (
        echo   > Echec telechargement Git
        goto :FALLBACK_GIT
    )
) else (
    for /f "tokens=*" %%a in ('git --version 2^>^&1') do set GIT_VERSION=%%a
    echo   > Git present: !GIT_VERSION!
    echo [OK] Git >> "%LOG_FILE%"
)
echo.
goto :GIT_DONE

:FALLBACK_GIT
echo [AVERTISSEMENT] Git installation manuelle requise
echo   Telechargez: https://git-scm.com/download/win
set /p MANUAL="Appuyez sur ENTREE apres installation..."
where git >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERREUR] Git absent
    goto :CLEANUP_ERROR
)

:GIT_DONE

echo [2/11] Recuperation application...
echo [%time%] Phase 2: Repo >> "%LOG_FILE%"

if exist "%APP_DIR%\.git" (
    echo   > Mise a jour repo...
    cd /d "%APP_DIR%"
    git pull >>"%LOG_FILE%" 2>&1
    if !errorlevel! neq 0 (
        echo   > git pull echoue, re-clone...
        cd ..
        rmdir /s /q "%APP_DIR%" >nul 2>&1
        goto :FRESH_CLONE
    )
    echo [OK] Repo >> "%LOG_FILE%"
) else (
    :FRESH_CLONE
    echo   > Clone repo...
    git clone "%REPO_URL%" "%APP_DIR%" >>"%LOG_FILE%" 2>&1
    if !errorlevel! neq 0 (
        echo [ERREUR] Clone echoue
        set /a ERROR_COUNT+=1
        goto :CLEANUP_ERROR
    )
)

cd /d "%APP_DIR%"
if not exist "main_webapp.py" (
    echo [ERREUR] Structure repo invalide
    set /a ERROR_COUNT+=1
    goto :CLEANUP_ERROR
)
echo.

echo [3/11] Verification Python...
echo [%time%] Phase 3: Python >> "%LOG_FILE%"

where python >nul 2>&1
if !errorlevel! neq 0 (
    echo   > Python non trouve
    set "PYTHON_INSTALLER=%TEMP%\Python.exe"
    
    powershell -Command "try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PYTHON_URL%' -OutFile '%PYTHON_INSTALLER%' -UseBasicParsing -TimeoutSec 60 } catch { exit 1 }" 2>>"%LOG_FILE%"
    if !errorlevel! equ 0 (
        if exist "!PYTHON_INSTALLER!" (
            start /wait "" "!PYTHON_INSTALLER!" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0 >>"%LOG_FILE%" 2>&1
            del "!PYTHON_INSTALLER!" >nul 2>&1
            for /f "skip=2 tokens=3*" %%a in ('reg query HKCU\Environment /v PATH 2^>nul') do set "USER_PATH=%%a %%b"
            for /f "skip=2 tokens=3*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%a %%b"
            set "PATH=%SYSTEM_PATH%;%USER_PATH%"
            timeout /t 2 /nobreak >nul
            where python >nul 2>&1
            if !errorlevel! equ 0 (
                echo   > Python installe
                echo [OK] Python >> "%LOG_FILE%"
            ) else (
                echo [ERREUR] Python non detecte
                goto :CLEANUP_ERROR
            )
        )
    ) else (
        echo [ERREUR] Telechargement Python echoue
        goto :CLEANUP_ERROR
    )
) else (
    for /f "tokens=*" %%a in ('python --version 2^>^&1') do set PY_VERSION=%%a
    echo   > Python present: !PY_VERSION!
    echo [OK] Python >> "%LOG_FILE%"
)
echo.

echo [4/11] Environnement virtuel...
echo [%time%] Phase 4: Venv >> "%LOG_FILE%"

if not exist "venv" (
    echo   > Creation venv...
    python -m venv venv >>"%LOG_FILE%" 2>&1
    if !errorlevel! neq 0 (
        echo [ERREUR] Venv creation echouee
        set /a ERROR_COUNT+=1
        goto :CLEANUP_ERROR
    )
    echo   > Venv cree
    echo [OK] Venv >> "%LOG_FILE%"
) else (
    echo   > Venv existant
)

call venv\Scripts\activate.bat
echo.

echo [5/11] Pip upgrade...
echo [%time%] Phase 5: Pip >> "%LOG_FILE%"

python -m pip install --upgrade pip setuptools wheel --quiet >>"%LOG_FILE%" 2>&1
if !errorlevel! equ 0 (
    echo   > pip OK
    echo [OK] Pip >> "%LOG_FILE%"
) else (
    echo [AVERTISSEMENT] pip upgrade echoue
    echo [WARN] Pip >> "%LOG_FILE%"
)
echo.

echo [6/11] Installation dependances...
echo [%time%] Phase 6: Deps >> "%LOG_FILE%"

if not exist "requirements.txt" (
    echo [ERREUR] requirements.txt absent
    set /a ERROR_COUNT+=1
    goto :CLEANUP_ERROR
)

pip install -r requirements.txt >>"%LOG_FILE%" 2>&1
if !errorlevel! neq 0 (
    echo   > Nouvelle tentative...
    pip install -r requirements.txt --no-cache-dir --retries 3 >>"%LOG_FILE%" 2>&1
    if !errorlevel! neq 0 (
        echo [ERREUR] Installation dependances echouee
        set /a ERROR_COUNT+=1
        goto :CLEANUP_ERROR
    )
)
echo   > Dependances OK
echo [OK] Deps >> "%LOG_FILE%"
echo.

echo [7/11] Configuration environnement...
echo [%time%] Phase 7: Config >> "%LOG_FILE%"

if not exist ".env" (
    echo   > Creation .env...
    (
        echo SECRET_KEY=tatbooker_default_secret_key_change_in_production
        echo DEBUG=False
        echo DATABASE_URL=sqlite:///tatbooker.db
    ) > .env
    echo [INFO] .env created >> "%LOG_FILE%"
)

if not exist "secret.key" (
    echo   > Generation secret.key...
    python -c "from cryptography.fernet import Fernet; open('secret.key', 'wb').write(Fernet.generate_key())" 2>>"%LOG_FILE%"
)
echo.

echo [7b/11] Initialisation base de donnees...
echo [%time%] Phase 7b: DB Init >> "%LOG_FILE%"

python -c "from datas.database_manager import initialize_db; initialize_db()" >>%LOG_FILE% 2>&1
if !errorlevel! equ 0 (
    echo   > Base de donnees initialisee
    echo [OK] DB Init >> "%LOG_FILE%"
) else (
    echo [ERREUR] Initialisation DB echouee
    set /a ERROR_COUNT+=1
    goto :CLEANUP_ERROR
)
echo.

echo [8/11] WebView2...
echo [%time%] Phase 8: WebView2 >> "%LOG_FILE%"

set "WEBVIEW2_FOUND=0"
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" >nul 2>&1
if !errorlevel! equ 0 set "WEBVIEW2_FOUND=1"

if %WEBVIEW2_FOUND% equ 0 (
    if %VERSION% GEQ 10.0 (
        echo   > Installation WebView2...
        set "WEBVIEW2_URL=https://go.microsoft.com/fwlink/p/?LinkId=2124703"
        set "WEBVIEW2_INSTALLER=%TEMP%\WebView2.exe"
        powershell -Command "try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%WEBVIEW2_URL%' -OutFile '%WEBVIEW2_INSTALLER%' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }" 2>>"%LOG_FILE%"
        if !errorlevel! equ 0 (
            if exist "!WEBVIEW2_INSTALLER!" (
                start /wait "" "!WEBVIEW2_INSTALLER!" /silent /install >>"%LOG_FILE%" 2>&1
                del "!WEBVIEW2_INSTALLER!" >nul 2>&1
            )
        )
    )
) else (
    echo   > WebView2 present
)
echo.

echo [9/11] VC++ Redistributable...
echo [%time%] Phase 9: VC++ >> "%LOG_FILE%"

set "VCREDIST_FOUND=0"
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" >nul 2>&1
if !errorlevel! equ 0 set "VCREDIST_FOUND=1"

if %VCREDIST_FOUND% equ 0 (
    echo   > Installation VC++ Redist...
    set "VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
    set "VCREDIST_INSTALLER=%TEMP%\vc_redist.x64.exe"
    powershell -Command "try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%VCREDIST_URL%' -OutFile '%VCREDIST_INSTALLER%' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }" 2>>"%LOG_FILE%"
    if !errorlevel! equ 0 (
        if exist "!VCREDIST_INSTALLER!" (
            start /wait "" "!VCREDIST_INSTALLER!" /quiet /norestart >>"%LOG_FILE%" 2>&1
            del "!VCREDIST_INSTALLER!" >nul 2>&1
        )
    )
) else (
    echo   > VC++ Redistributable present
)
echo.

echo [10/11] Raccourcis...
echo [%time%] Phase 10: Shortcuts >> "%LOG_FILE%"

set "PYTHON_EXE=%APP_DIR%\venv\Scripts\python.exe"
set "MAIN_SCRIPT=%APP_DIR%\main_webapp.py"
set "SHORTCUT=%USERPROFILE%\Desktop\TATBooker.lnk"

powershell -Command "try { $WS = New-Object -ComObject WScript.Shell; $SC = $WS.CreateShortcut('%SHORTCUT%'); $SC.TargetPath = '%PYTHON_EXE%'; $SC.Arguments = '%MAIN_SCRIPT%'; $SC.WorkingDirectory = '%APP_DIR%'; $SC.Save(); exit 0 } catch { exit 1 }" >>"%LOG_FILE%" 2>&1
if !errorlevel! equ 0 (
    echo   > Raccourci Bureau cree
    echo [OK] Shortcut >> "%LOG_FILE%"
) else (
    echo [AVERTISSEMENT] Raccourci echoue
)
echo.

echo [11/11] Validation...
echo [%time%] Phase 11: Validation >> "%LOG_FILE%"

python -c "import webview, flask, sqlite3" >>"%LOG_FILE%" 2>&1
if !errorlevel! neq 0 (
    echo [ERREUR] Modules manquants
    set /a ERROR_COUNT+=1
    goto :VALIDATION_FAILED
)

if not exist "%MAIN_SCRIPT%" (
    echo [ERREUR] main_webapp.py absent
    set /a ERROR_COUNT+=1
    goto :VALIDATION_FAILED
)

if not exist ".env" (
    echo [ERREUR] Configuration absente
    set /a ERROR_COUNT+=1
    goto :VALIDATION_FAILED
)

echo.
echo   > Validation OK
echo   > Installation reussie
echo [OK] Validation >> "%LOG_FILE%"
echo.
goto :SUCCESS

:VALIDATION_FAILED
echo.
echo ================================================
echo   VALIDATION ECHOUEE
echo ================================================
echo Erreurs: %ERROR_COUNT%
echo Log: %LOG_FILE%
echo.
pause
exit /b 1

:SUCCESS
cls
echo.
echo ================================================
echo   INSTALLATION TERMINEE AVEC SUCCES
echo ================================================
echo.
echo TATBooker est pret a l'emploi.
echo.
echo Lancement dans 5 secondes...
timeout /t 5 /nobreak >nul

if exist "%PYTHON_EXE%" (
    if exist "%MAIN_SCRIPT%" (
        echo [%time%] Lancement >> "%LOG_FILE%"
        start "" "%PYTHON_EXE%" "%MAIN_SCRIPT%"
        exit /b 0
    )
)

echo [ERREUR] Lancement impossible
pause
exit /b 1

:CLEANUP_ERROR
echo.
echo ================================================
echo   ERREUR CRITIQUE
echo ================================================
echo.
echo Installation echouee. Erreurs: %ERROR_COUNT%
echo Log: %LOG_FILE%
echo.
echo Actions:
echo   1. Verifiez connexion Internet
echo   2. Lancez en admin
echo   3. Supprimez %APP_DIR%
echo   4. Relancez le script
echo.
echo [%time%] Echec - %ERROR_COUNT% erreurs >> "%LOG_FILE%"
pause
exit /b 1
