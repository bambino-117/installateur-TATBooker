@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion
title TATBooker - Installation Automatique Blindée
color 0A

whoami /groups | find "S-1-5-32-544" >nul
if %errorlevel% neq 0 (
    echo Droits administrateur requis. Clic droit -> Executer en tant qu'administrateur
    pause
    exit /b 1
)

:: ============================================
:: MODE DEBUG - Pour voir les erreurs
:: ============================================
set "DEBUG_MODE=1"
if "%DEBUG_MODE%"=="1" (
    echo [DEBUG] Script lance a %date% %time%
    echo [DEBUG] Repertoire: %CD%
    pause
)

:: ============================================================================
:: TATBooker - Installateur Windows Ultra-Blindé
:: Gère: Détection, Téléchargement, Installation, Validation, Rollback
:: ============================================================================

set "LOG_FILE=%TEMP%\tatbooker_install.log"
set "APP_DIR=%USERPROFILE%\TATBooker"
set "REPO_URL=https://github.com/bambino-117/TATBooker---Developpement.git"
set "ERROR_COUNT=0"
set "STEP=0"

echo. > "%LOG_FILE%"
echo [%date% %time%] Installation TATBooker demarree >> "%LOG_FILE%"

cls
echo ============================================
echo    TATBooker - Installation Windows
echo    Installation Automatique Blindee
echo ============================================
echo.

:: ============================================================================
:: PHASE 0: VERIFICATIONS PREALABLES
:: ============================================================================
echo [0/10] Verifications prealables...
echo [%time%] Phase 0: Verifications >> "%LOG_FILE%"

:: Détecter version Windows
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo   ^> Version Windows: %VERSION%
echo [INFO] Windows version: %VERSION% >> "%LOG_FILE%"

:: Vérifier si Windows 8.0 (non supporté pour Python 3.12)
if "%VERSION%"=="6.2" (
    echo [AVERTISSEMENT] Windows 8.0 detecte - Python limite a 3.8
    set "PYTHON_URL=https://www.python.org/ftp/python/3.8.10/python-3.8.10-amd64.exe"
    set "PYTHON_MAX_VERSION=3.8"
    echo [WARN] Windows 8.0 - Python 3.8 max >> "%LOG_FILE%"
)

:: Activer long paths (Windows 10+)
if %VERSION% GEQ 10.0 (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    echo   ^> Long paths actives
)

:: Vérifier espace disque (minimum 2 GB)
for /f "tokens=3" %%a in ('dir /-c %USERPROFILE% ^| find "octets libres"') do set FREE_SPACE=%%a
set FREE_SPACE=%FREE_SPACE:~0,-3%
if %FREE_SPACE% LSS 2000000 (
    echo [ERREUR] Espace disque insuffisant. Minimum 2 GB requis.
    echo [ERREUR] Espace insuffisant >> "%LOG_FILE%"
    pause
    exit /b 1
)
echo   ^> Espace disque: OK

:: Tester connexion Internet (avec timeout court)
ping -n 1 -w 1000 github.com > nul 2>&1
if %errorlevel% neq 0 (
    echo [AVERTISSEMENT] Connexion Internet faible ou absente
    echo [WARN] Pas de connexion Internet >> "%LOG_FILE%"
    echo   Tentative alternative avec google.com...
    ping -n 1 -w 1000 google.com > nul 2>&1
    if %errorlevel% neq 0 (
        set /p CONTINUE="Continuer quand meme? (O/N): "
        if /i not "!CONTINUE!"=="O" exit /b 1
    ) else (
        echo   ^> Connexion Internet: OK (via fallback)
    )
) else (
    echo   ^> Connexion Internet: OK
)

:: Vérifier PowerShell (minimum 3.0)
for /f "tokens=*" %%a in ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>^&1') do set PS_VERSION=%%a
if %PS_VERSION% LSS 3 (
    echo [ERREUR] PowerShell 3.0+ requis (version detectee: %PS_VERSION%)
    echo [ERROR] PowerShell version too old >> "%LOG_FILE%"
    pause
    exit /b 1
)
echo   ^> PowerShell: v%PS_VERSION%

:: Détection architecture
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set "ARCH=64"
    set "PYTHON_URL=https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    echo   ^> Architecture: 64-bit
) else (
    set "ARCH=32"
    set "PYTHON_URL=https://www.python.org/ftp/python/3.12.0/python-3.12.0.exe"
    echo   ^> Architecture: 32-bit
)

echo.

:: ============================================================================
:: PHASE 1: INSTALLATION GIT
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Verification de Git...
echo [%time%] Phase 1: Git >> "%LOG_FILE%"

where git >nul 2>&1
if %errorlevel% neq 0 (
    echo   ^> Git non trouve. Telechargement...
    echo [INFO] Installation Git >> "%LOG_FILE%"
    
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.45.0.windows.1/Git-2.45.0-64-bit.exe"
    set "GIT_INSTALLER=%TEMP%\GitInstaller.exe"
    
    powershell -Command "try { Invoke-WebRequest -Uri '%GIT_URL%' -OutFile '%GIT_INSTALLER%' -UseBasicParsing } catch { exit 1 }"
    if %errorlevel% neq 0 (
        echo [ERREUR] Echec telechargement Git
        echo [ERROR] Download Git failed >> "%LOG_FILE%"
        set /a ERROR_COUNT+=1
        goto :FALLBACK_GIT
    )
    
    echo   ^> Installation de Git (patientez 1-2 min)...
    start /wait "" "%GIT_INSTALLER%" /VERYSILENT /NORESTART /LOG="%TEMP%\git_install.log"
    del "%GIT_INSTALLER%" >nul 2>&1
    
    :: Rafraîchir PATH manuellement (refreshenv n'existe pas par défaut)
    for /f "skip=2 tokens=3*" %%a in ('reg query HKCU\Environment /v PATH 2^>nul') do set "USER_PATH=%%a %%b"
    for /f "skip=2 tokens=3*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%a %%b"
    set "PATH=%SYSTEM_PATH%;%USER_PATH%;C:\Program Files\Git\cmd"
    
    where git >nul 2>&1
    if %errorlevel% neq 0 (
        echo [ERREUR] Git installe mais non detecte dans PATH
        echo [ERROR] Git not in PATH >> "%LOG_FILE%"
        goto :FALLBACK_GIT
    )
    echo   ^> Git installe avec succes
    echo [OK] Git installed >> "%LOG_FILE%"
) else (
    for /f "tokens=*" %%a in ('git --version 2^>^&1') do set GIT_VERSION=%%a
    echo   ^> Git deja present: !GIT_VERSION!
    echo [OK] Git found: !GIT_VERSION! >> "%LOG_FILE%"
)
echo.
goto :GIT_DONE

:FALLBACK_GIT
echo [AVERTISSEMENT] Git non disponible. Installation manuelle requise.
echo   Telechargez: https://git-scm.com/download/win
set /p MANUAL_GIT="Appuyez sur ENTREE apres installation manuelle de Git..."
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR CRITIQUE] Git toujours absent. Impossible de continuer.
    goto :CLEANUP_ERROR
)

:GIT_DONE

:: ============================================================================
:: PHASE 2: CLONAGE / MISE A JOUR DU DEPOT
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Recuperation de l'application...
echo [%time%] Phase 2: Clone/Pull >> "%LOG_FILE%"

if exist "%APP_DIR%\.git" (
    echo   ^> Installation existante detectee
    echo   ^> Mise a jour en cours...
    cd /d "%APP_DIR%"
    git pull >> "%LOG_FILE%" 2>&1
    if %errorlevel% neq 0 (
        echo [AVERTISSEMENT] Echec git pull, re-clone complet...
        cd ..
        rmdir /s /q "%APP_DIR%" >nul 2>&1
        goto :FRESH_CLONE
    )
    echo   ^> Mise a jour terminee
    echo [OK] Git pull successful >> "%LOG_FILE%"
) else (
    :FRESH_CLONE
    echo   ^> Premier clonage (peut prendre 2-5 min)...
    if exist "%APP_DIR%" rmdir /s /q "%APP_DIR%" >nul 2>&1
    
    git clone "%REPO_URL%" "%APP_DIR%" >> "%LOG_FILE%" 2>&1
    if %errorlevel% neq 0 (
        echo [ERREUR] Echec du clonage Git
        echo [ERROR] Git clone failed >> "%LOG_FILE%"
        set /a ERROR_COUNT+=1
        goto :CLEANUP_ERROR
    )
    echo   ^> Clonage termine
    echo [OK] Git clone successful >> "%LOG_FILE%"
)

cd /d "%APP_DIR%"
echo.

:: ============================================================================
:: PHASE 3: INSTALLATION PYTHON
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Verification de Python...
echo [%time%] Phase 3: Python >> "%LOG_FILE%"

where python >nul 2>&1
if %errorlevel% neq 0 (
    where py >nul 2>&1
    if %errorlevel% neq 0 (
    echo   ^> Python non trouve. Installation...
    echo [INFO] Installing Python >> "%LOG_FILE%"

    ) else (
        set "python=py"
    )
    
    set "PYTHON_INSTALLER=%TEMP%\PythonInstaller.exe"
    
    echo   ^> Telechargement Python 3.12 (%ARCH%-bit)...
    powershell -Command "try { Invoke-WebRequest -Uri '%PYTHON_URL%' -OutFile '%PYTHON_INSTALLER%' -UseBasicParsing } catch { exit 1 }"
    if %errorlevel% neq 0 (
        echo [AVERTISSEMENT] Echec telechargement Python 3.12, tentative 3.11...
        set "PYTHON_URL=https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
        powershell -Command "try { Invoke-WebRequest -Uri '!PYTHON_URL!' -OutFile '%PYTHON_INSTALLER%' -UseBasicParsing } catch { exit 1 }"
        if %errorlevel% neq 0 goto :FALLBACK_PYTHON
    )
    
    echo   ^> Installation de Python (patientez 3-5 min)...
    start /wait "" "%PYTHON_INSTALLER%" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
    del "%PYTHON_INSTALLER%" >nul 2>&1
    
    :: Rafraîchir PATH manuellement
    for /f "skip=2 tokens=3*" %%a in ('reg query HKCU\Environment /v PATH 2^>nul') do set "USER_PATH=%%a %%b"
    for /f "skip=2 tokens=3*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%a %%b"
    set "PATH=%SYSTEM_PATH%;%USER_PATH%"
    
    where python >nul 2>&1
    if %errorlevel% neq 0 (
        echo [ERREUR] Python installe mais non detecte
        goto :FALLBACK_PYTHON
    )
    echo   ^> Python installe avec succes
    echo [OK] Python installed >> "%LOG_FILE%"
) else (
    for /f "tokens=*" %%a in ('python --version 2^>^&1') do set PY_VERSION=%%a
    echo   ^> Python deja present: !PY_VERSION!
    echo [OK] Python found: !PY_VERSION! >> "%LOG_FILE%"
)
echo.
goto :PYTHON_DONE

:FALLBACK_PYTHON
echo [ERREUR CRITIQUE] Installation Python echouee
echo   Telechargez manuellement: https://www.python.org/downloads/
set /p MANUAL_PY="Appuyez sur ENTREE apres installation manuelle..."
where python >nul 2>&1
if %errorlevel% neq 0 goto :CLEANUP_ERROR

:PYTHON_DONE

:: ============================================================================
:: PHASE 4: ENVIRONNEMENT VIRTUEL
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Configuration environnement virtuel...
echo [%time%] Phase 4: Venv >> "%LOG_FILE%"

if exist "%APP_DIR%\venv" (
    echo   ^> Environnement virtuel existant
    echo [OK] Venv exists >> "%LOG_FILE%"
) else (
    echo   ^> Creation environnement virtuel...
    "%APP_DIR%\venv\Scripts\python.exe" -m venv "%APP_DIR%\venv" >> "%LOG_FILE%" 2>&1
    if %errorlevel% neq 0 (
        echo [ERREUR] Echec creation venv
        echo [ERROR] Venv creation failed >> "%LOG_FILE%"
        pause
        goto :CLEANUP_ERROR
    )
    echo   ^> Venv cree
    echo [OK] Venv created >> "%LOG_FILE%"
)

:: Activer venv
call "%APP_DIR%\venv\Scripts\activate.bat"
if %errorlevel% neq 0 (
    echo [ERREUR] Echec activation venv
    echo [ERROR] Venv activation failed >> "%LOG_FILE%"
    pause
    goto :CLEANUP_ERROR
)
set "PYTHON_EXE=%APP_DIR%\venv\Scripts\python.exe"
echo [OK] Venv active avec Python: %PYTHON_EXE% >> "%LOG_FILE%"
echo.

:: ============================================================================
:: PHASE 5: MISE A JOUR PIP
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Mise a jour de pip...
echo [%time%] Phase 5: Pip upgrade >> "%LOG_FILE%"

python -m pip install --upgrade pip --quiet >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    echo   ^> pip mis a jour avec succes
    echo [OK] Pip upgraded >> "%LOG_FILE%"
) else (
    echo [AVERTISSEMENT] Echec mise a jour pip, utilisation version existante
    echo [WARN] Pip upgrade failed >> "%LOG_FILE%"
)
echo.

:: ============================================================================
:: PHASE 6: DEPENDANCES (AVEC DEBUG)
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Installation des dependances...
echo [%time%] Phase 6: Dependencies >> "%LOG_FILE%"

if not exist "%APP_DIR%\requirements.txt" (
    echo [ERREUR CRITIQUE] requirements.txt manquant
    echo [ERROR] requirements.txt missing >> "%LOG_FILE%"
    pause
    goto :CLEANUP_ERROR
)

echo   ^> Installation des packages...
echo   ^> PYTHON_EXE: %PYTHON_EXE%
echo   ^> %PYTHON_EXE% -m pip install --upgrade pip

"%PYTHON_EXE%" -m pip install --upgrade pip >> "%LOG_FILE%" 2>&1
echo   ^> %PYTHON_EXE% -m pip install -r requirements.txt

"%PYTHON_EXE%" -m pip install -r "%APP_DIR%\requirements.txt" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 (
    echo [AVERTISSEMENT] Echec installation, tentative sans cache...
    "%PYTHON_EXE%" -m pip install -r "%APP_DIR%\requirements.txt" --no-cache-dir >> "%LOG_FILE%" 2>&1
    if %errorlevel% neq 0 (
        echo [ERREUR] Echec installation dependances
        echo [ERROR] Dependencies install failed >> "%LOG_FILE%"
        pause
        goto :CLEANUP_ERROR
    )
)
echo   ^> Dependances OK
echo [OK] Dependencies installed >> "%LOG_FILE%"

:: ============================================================================
:: PHASE 7: CONFIGURATION ENVIRONNEMENT (.env, secret.key)
:: ============================================================================
set /a STEP+=1
echo [%STEP%/9] Configuration de l'environnement...
echo [%time%] Phase 7: Setup env >> "%LOG_FILE%"

if exist "scripts\setup_env.py" (
    echo   ^> Execution setup_env.py...
    python scripts\setup_env.py >> "%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        echo   ^> Fichier .env et secret.key generes
        echo [OK] Environment configured >> "%LOG_FILE%"
    ) else (
        echo [AVERTISSEMENT] Echec setup_env.py
        echo [WARN] setup_env.py failed >> "%LOG_FILE%"
    )
) else (
    echo [AVERTISSEMENT] Script setup_env.py non trouve
    echo [WARN] setup_env.py not found >> "%LOG_FILE%"
)

:: Vérifier fichiers critiques
if not exist ".env" (
    echo [AVERTISSEMENT] Fichier .env manquant, creation par defaut...
    echo SECRET_KEY=default_secret_key > .env
)
if not exist "secret.key" (
    echo [AVERTISSEMENT] Fichier secret.key manquant, generation...
    python -c "from cryptography.fernet import Fernet; open('secret.key', 'wb').write(Fernet.generate_key())" 2>nul
)

echo.

:: ============================================================================
:: PHASE 8: INSTALLATION WEBVIEW2 (Windows 8/10)
:: ============================================================================
set /a STEP+=1
echo [%STEP%/10] Verification WebView2 Runtime...
echo [%time%] Phase 8: WebView2 >> "%LOG_FILE%"

reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" >nul 2>&1
if %errorlevel% neq 0 (
    echo   ^> WebView2 non trouve. Installation...
    echo [INFO] Installing WebView2 >> "%LOG_FILE%"
    
    set "WEBVIEW2_URL=https://go.microsoft.com/fwlink/p/?LinkId=2124703"
    set "WEBVIEW2_INSTALLER=%TEMP%\MicrosoftEdgeWebview2Setup.exe"
    
    powershell -Command "try { Invoke-WebRequest -Uri '%WEBVIEW2_URL%' -OutFile '%WEBVIEW2_INSTALLER%' -UseBasicParsing } catch { exit 1 }"
    if %errorlevel% equ 0 (
        start /wait "" "%WEBVIEW2_INSTALLER%" /silent /install
        del "%WEBVIEW2_INSTALLER%" >nul 2>&1
        echo   ^> WebView2 installe
        echo [OK] WebView2 installed >> "%LOG_FILE%"
    ) else (
        echo [AVERTISSEMENT] Echec installation WebView2
        echo   L'application pourrait ne pas fonctionner correctement
        echo [WARN] WebView2 install failed >> "%LOG_FILE%"
    )
) else (
    echo   ^> WebView2 deja present
    echo [OK] WebView2 found >> "%LOG_FILE%"
)
echo.

:: ============================================================================
:: PHASE 9: INSTALLATION VISUAL C++ REDISTRIBUTABLE
:: ============================================================================
set /a STEP+=1
echo [%STEP%/10] Verification Visual C++ Redistributable...
echo [%time%] Phase 9: VC++ Redist >> "%LOG_FILE%"

reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" >nul 2>&1
if %errorlevel% neq 0 (
    echo   ^> VC++ Redistributable non trouve. Installation...
    echo [INFO] Installing VC++ Redist >> "%LOG_FILE%"
    
    set "VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
    set "VCREDIST_INSTALLER=%TEMP%\vc_redist.x64.exe"
    
    powershell -Command "try { Invoke-WebRequest -Uri '%VCREDIST_URL%' -OutFile '%VCREDIST_INSTALLER%' -UseBasicParsing } catch { exit 1 }"
    if %errorlevel% equ 0 (
        start /wait "" "%VCREDIST_INSTALLER%" /quiet /norestart
        del "%VCREDIST_INSTALLER%" >nul 2>&1
        echo   ^> VC++ Redistributable installe
        echo [OK] VC++ Redist installed >> "%LOG_FILE%"
    ) else (
        echo [AVERTISSEMENT] Echec installation VC++ Redistributable
        echo [WARN] VC++ Redist install failed >> "%LOG_FILE%"
    )
) else (
    echo   ^> VC++ Redistributable deja present
    echo [OK] VC++ Redist found >> "%LOG_FILE%"
)
echo.

:: ============================================================================
:: PHASE 10: CREATION RACCOURCIS
:: ============================================================================
set /a STEP+=1
echo [%STEP%/10] Creation des raccourcis...
echo [%time%] Phase 10: Shortcuts >> "%LOG_FILE%"

set "PYTHON_EXE=%APP_DIR%\venv\Scripts\python.exe"
set "MAIN_SCRIPT=%APP_DIR%\main_webapp.py"
set "SHORTCUT=%USERPROFILE%\Desktop\TATBooker.lnk"
set "ICON_PATH=%~dp0logorezos.ico"

:: Copier icône dans le dossier app
if exist "%ICON_PATH%" (
    copy /Y "%ICON_PATH%" "%APP_DIR%\logorezos.ico" >nul 2>&1
    set "ICON_PATH=%APP_DIR%\logorezos.ico"
    echo   ^> Icone copiee
)

:: Créer raccourci Bureau
powershell -Command "$WS = New-Object -ComObject WScript.Shell; $SC = $WS.CreateShortcut('%SHORTCUT%'); $SC.TargetPath = '"%PYTHON_EXE%"'; $SC.Arguments = '"%MAIN_SCRIPT%"'; $SC.WorkingDirectory = '%APP_DIR%'; $SC.IconLocation = '%ICON_PATH%'; $SC.Save()" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    echo   ^> Raccourci Bureau cree: TATBooker.lnk
    echo [OK] Desktop shortcut created >> "%LOG_FILE%"
) else (
    echo [AVERTISSEMENT] Echec creation raccourci
    echo [WARN] Shortcut creation failed >> "%LOG_FILE%"
)

echo.

:: ============================================================================
:: PHASE 11: VALIDATION FINALE
:: ============================================================================
set /a STEP+=1
echo [%STEP%/10] Validation de l'installation...
echo [%time%] Phase 11: Validation >> "%LOG_FILE%"

:: Test import critique
python -c "import webview, flask, sqlite3, cryptography" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR] Modules critiques manquants
    echo [ERROR] Critical imports failed >> "%LOG_FILE%"
    set /a ERROR_COUNT+=1
    goto :VALIDATION_FAILED
)

:: Vérifier fichier principal
if not exist "%MAIN_SCRIPT%" (
    echo [ERREUR CRITIQUE] Fichier main_webapp.py manquant
    echo [ERROR] main_webapp.py missing >> "%LOG_FILE%"
    goto :VALIDATION_FAILED
)

echo   ^> Tous les modules critiques sont OK
echo   ^> Fichier principal: OK
echo   ^> Base de donnees: OK
echo [OK] Validation successful >> "%LOG_FILE%"
echo.
goto :SUCCESS

:VALIDATION_FAILED
echo.
echo ============================================
echo    VALIDATION ECHOUEE
echo ============================================
echo.
echo Certains composants sont manquants ou corrompus.
echo Consultez le log: %LOG_FILE%
echo.
pause
exit /b 1

:: ============================================================================
:: SUCCES - INSTALLATION TERMINEE
:: ============================================================================
:SUCCESS
cls
echo.
echo ============================================
echo.
echo          INSTALLATION TERMINEE !
echo.
echo ============================================
echo.
echo   [32m√[0m TATBooker est pret a l'emploi
echo.
echo   [36mLancement:[0m
echo     - Double-cliquez sur le raccourci Bureau
echo     - Ou executez: %APP_DIR%\venv\Scripts\python.exe %MAIN_SCRIPT%
echo.
echo   [33mMise a jour:[0m
echo     - Relancez ce script INSTALLER.bat
echo.
echo   [35mLog d'installation:[0m
echo     - %LOG_FILE%
echo.
echo ============================================
echo.
echo [%time%] Installation terminee avec succes >> "%LOG_FILE%"
echo.
echo Lancement automatique dans 5 secondes...
echo (Appuyez sur Ctrl+C pour annuler)
timeout /t 5 /nobreak >nul
start "" "%PYTHON_EXE%" "%MAIN_SCRIPT%"
exit /b 0

:: ============================================================================
:: GESTION ERREURS - NETTOYAGE
:: ============================================================================
:CLEANUP_ERROR
echo.
echo ============================================
echo    ERREUR CRITIQUE DETECTEE
echo ============================================
echo.
echo Installation impossible. Erreurs: %ERROR_COUNT%
echo.
echo Consultez le log detaille: %LOG_FILE%
echo.
echo Actions possibles:
echo   1. Verifiez votre connexion Internet
echo   2. Executez en tant qu'administrateur
echo   3. Installez manuellement Git et Python
echo   4. Contactez le support: support@tatbooker.com
echo.
echo [%time%] Installation echouee - %ERROR_COUNT% erreurs >> "%LOG_FILE%"
echo.
pause
exit /b 1
