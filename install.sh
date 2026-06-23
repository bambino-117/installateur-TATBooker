#!/bin/bash

# ============================================================================
# TATBooker - Installateur Linux Ultra-Blindé
# Gère: Détection distro, Téléchargement, Installation, Validation, Rollback
# Compatibilité: Ubuntu, Debian, Mint, Manjaro, Arch, Fedora, RHEL, openSUSE
# ============================================================================

set -e  # Exit on error (désactivé après les tests critiques)

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables globales
LOG_FILE="/tmp/tatbooker_install.log"
APP_DIR="$HOME/TATBooker"
REPO_URL="https://github.com/bambino-117/TATBooker---Developpement.git"
ERROR_COUNT=0
STEP=0
DISTRO=""
PKG_MANAGER=""

# Initialisation log
echo "[$(date)] Installation TATBooker démarrée" > "$LOG_FILE"

clear
echo "============================================"
echo -e "${BLUE}   TATBooker - Installation Linux${NC}"
echo -e "${BLUE}   Installation Automatique Blindée${NC}"
echo "============================================"
echo ""

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

log_info() {
    echo "[INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo "[WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $1" >> "$LOG_FILE"
    ((ERROR_COUNT++))
}

print_step() {
    echo -e "${CYAN}[$1] $2${NC}"
    log_info "Phase $1: $2"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

# ============================================================================
# PHASE 0: DÉTECTION SYSTÈME & VÉRIFICATIONS
# ============================================================================
((STEP++))
print_step "$STEP/11" "Vérifications préalables..."

# Détecter la distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    print_success "Distribution détectée: $DISTRO ($VERSION_ID)"
    log_info "Distribution: $DISTRO $VERSION_ID"
else
    print_error "Distribution inconnue - /etc/os-release manquant"
    log_error "Unknown distribution"
    DISTRO="unknown"
fi

# Déterminer le gestionnaire de paquets
case $DISTRO in
    ubuntu|debian|linuxmint|pop)
        PKG_MANAGER="apt"
        PKG_UPDATE="sudo apt update -qq"
        PKG_INSTALL="sudo apt install -y"
        ;;
    manjaro|arch|endeavouros)
        PKG_MANAGER="pacman"
        PKG_UPDATE="sudo pacman -Sy --noconfirm"
        PKG_INSTALL="sudo pacman -S --noconfirm"
        ;;
    fedora|rhel|centos|rocky|almalinux)
        PKG_MANAGER="dnf"
        PKG_UPDATE="sudo dnf check-update -q"
        PKG_INSTALL="sudo dnf install -y"
        ;;
    opensuse*|sles)
        PKG_MANAGER="zypper"
        PKG_UPDATE="sudo zypper refresh"
        PKG_INSTALL="sudo zypper install -y"
        ;;
    *)
        print_error "Distribution non supportée: $DISTRO"
        log_error "Unsupported distribution: $DISTRO"
        echo ""
        echo "Distributions supportées: Ubuntu, Debian, Mint, Manjaro, Arch, Fedora, RHEL, openSUSE"
        exit 1
        ;;
esac

print_success "Gestionnaire de paquets: $PKG_MANAGER"

# Vérifier droits sudo
if ! sudo -n true 2>/dev/null; then
    print_warning "Droits sudo requis pour l'installation"
    sudo -v || { print_error "Échec authentification sudo"; exit 1; }
fi
print_success "Droits sudo: OK"

# Vérifier espace disque (minimum 2 GB)
AVAILABLE_SPACE=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 2 ]; then
    print_error "Espace disque insuffisant: ${AVAILABLE_SPACE}GB (minimum 2GB requis)"
    log_error "Insufficient disk space: ${AVAILABLE_SPACE}GB"
    exit 1
fi
print_success "Espace disque: ${AVAILABLE_SPACE}GB disponible"

# Tester connexion Internet
if ping -c 1 -W 2 github.com &> /dev/null; then
    print_success "Connexion Internet: OK"
elif ping -c 1 -W 2 google.com &> /dev/null; then
    print_success "Connexion Internet: OK (via fallback)"
    log_warn "github.com unreachable, using google.com"
else
    print_error "Aucune connexion Internet détectée"
    log_error "No internet connection"
    read -p "Continuer quand même? (o/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        exit 1
    fi
fi

echo ""

# ============================================================================
# PHASE 1: INSTALLATION GIT
# ============================================================================
((STEP++))
print_step "$STEP/11" "Vérification de Git..."

if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    print_success "Git déjà présent: v$GIT_VERSION"
    log_info "Git found: v$GIT_VERSION"
else
    print_warning "Git non trouvé. Installation..."
    log_info "Installing Git"
    
    if eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1; then
        if eval "$PKG_INSTALL git" >> "$LOG_FILE" 2>&1; then
            print_success "Git installé avec succès"
            log_info "Git installed successfully"
        else
            print_error "Échec installation Git"
            log_error "Git installation failed"
            echo ""
            echo "Installez Git manuellement:"
            case $PKG_MANAGER in
                apt) echo "  sudo apt install git" ;;
                pacman) echo "  sudo pacman -S git" ;;
                dnf) echo "  sudo dnf install git" ;;
                zypper) echo "  sudo zypper install git" ;;
            esac
            exit 1
        fi
    else
        print_error "Échec mise à jour des dépôts"
        log_error "Package manager update failed"
    fi
fi

# Vérifier Git disponible
if ! command -v git &> /dev/null; then
    print_error "Git toujours absent après installation"
    log_error "Git still not found after install"
    exit 1
fi

echo ""

# ============================================================================
# PHASE 2: CLONAGE / MISE À JOUR DU DÉPÔT
# ============================================================================
((STEP++))
print_step "$STEP/11" "Récupération de l'application..."

if [ -d "$APP_DIR/.git" ]; then
    print_warning "Installation existante détectée"
    cd "$APP_DIR" || exit 1
    
    if git pull >> "$LOG_FILE" 2>&1; then
        print_success "Mise à jour terminée"
        log_info "Git pull successful"
    else
        print_warning "Échec git pull, re-clone complet..."
        log_warn "Git pull failed, re-cloning"
        cd "$HOME" || exit 1
        rm -rf "$APP_DIR"
        
        if git clone "$REPO_URL" "$APP_DIR" >> "$LOG_FILE" 2>&1; then
            print_success "Re-clonage terminé"
            log_info "Re-clone successful"
            cd "$APP_DIR" || exit 1
        else
            print_error "Échec du clonage Git"
            log_error "Git clone failed"
            exit 1
        fi
    fi
else
    if [ -d "$APP_DIR" ]; then
        print_warning "Dossier existant sans .git, suppression..."
        rm -rf "$APP_DIR"
    fi
    
    print_warning "Premier clonage (2-5 minutes)..."
    
    if git clone "$REPO_URL" "$APP_DIR" >> "$LOG_FILE" 2>&1; then
        print_success "Clonage terminé"
        log_info "Git clone successful"
        cd "$APP_DIR" || exit 1
    else
        print_error "Échec du clonage Git"
        log_error "Git clone failed"
        
        # Tentative avec profondeur limitée
        print_warning "Nouvelle tentative avec --depth 1..."
        if git clone --depth 1 "$REPO_URL" "$APP_DIR" >> "$LOG_FILE" 2>&1; then
            print_success "Clonage partiel réussi"
            log_info "Shallow clone successful"
            cd "$APP_DIR" || exit 1
        else
            exit 1
        fi
    fi
fi

echo ""

# ============================================================================
# PHASE 3: INSTALLATION PYTHON
# ============================================================================
((STEP++))
print_step "$STEP/11" "Vérification de Python..."

if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    print_success "Python déjà présent: v$PYTHON_VERSION"
    log_info "Python found: v$PYTHON_VERSION"
    
    # Vérifier version minimale (3.8+)
    if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]; }; then
        print_error "Python $PYTHON_VERSION trop ancien (minimum 3.8)"
        log_error "Python version too old: $PYTHON_VERSION"
        exit 1
    fi
else
    print_warning "Python non trouvé. Installation..."
    log_info "Installing Python"
    
    # Installer Python + pip + venv selon la distro
    case $PKG_MANAGER in
        apt)
            eval "$PKG_INSTALL python3 python3-pip python3-venv python3-dev build-essential" >> "$LOG_FILE" 2>&1
            ;;
        pacman)
            eval "$PKG_INSTALL python python-pip" >> "$LOG_FILE" 2>&1
            ;;
        dnf)
            eval "$PKG_INSTALL python3 python3-pip python3-devel gcc" >> "$LOG_FILE" 2>&1
            ;;
        zypper)
            eval "$PKG_INSTALL python3 python3-pip python3-devel gcc" >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    if command -v python3 &> /dev/null; then
        print_success "Python installé avec succès"
        log_info "Python installed successfully"
    else
        print_error "Échec installation Python"
        log_error "Python installation failed"
        exit 1
    fi
fi

# Vérifier pip
if ! python3 -m pip --version &> /dev/null; then
    print_warning "pip non trouvé, installation..."
    case $PKG_MANAGER in
        apt) eval "$PKG_INSTALL python3-pip" >> "$LOG_FILE" 2>&1 ;;
        pacman) eval "$PKG_INSTALL python-pip" >> "$LOG_FILE" 2>&1 ;;
        dnf|zypper) eval "$PKG_INSTALL python3-pip" >> "$LOG_FILE" 2>&1 ;;
    esac
fi

echo ""

# ============================================================================
# PHASE 4: DÉPENDANCES SYSTÈME (WebKit, GTK)
# ============================================================================
((STEP++))
print_step "$STEP/11" "Installation dépendances système..."

print_warning "Installation bibliothèques graphiques..."
log_info "Installing system dependencies"

case $PKG_MANAGER in
    apt)
        eval "$PKG_INSTALL libwebkit2gtk-4.0-37 libwebkit2gtk-4.0-dev gir1.2-webkit2-4.0 libcairo2-dev libgirepository1.0-dev pkg-config" >> "$LOG_FILE" 2>&1
        ;;
    pacman)
        eval "$PKG_INSTALL webkit2gtk gtk3 gobject-introspection cairo pkg-config" >> "$LOG_FILE" 2>&1
        ;;
    dnf)
        eval "$PKG_INSTALL webkit2gtk3 webkit2gtk3-devel gtk3-devel gobject-introspection-devel cairo-devel pkg-config" >> "$LOG_FILE" 2>&1
        ;;
    zypper)
        eval "$PKG_INSTALL webkit2gtk3 webkit2gtk3-devel gtk3-devel gobject-introspection-devel cairo-devel pkg-config" >> "$LOG_FILE" 2>&1
        ;;
esac

if [ $? -eq 0 ]; then
    print_success "Dépendances système installées"
    log_info "System dependencies installed"
else
    print_warning "Certaines dépendances ont échoué (non bloquant)"
    log_warn "Some system dependencies failed"
fi

echo ""

# ============================================================================
# PHASE 5: ENVIRONNEMENT VIRTUEL
# ============================================================================
((STEP++))
print_step "$STEP/11" "Configuration environnement virtuel..."

if [ -d "venv" ]; then
    print_success "Environnement virtuel existant détecté"
    log_info "Venv exists"
else
    print_warning "Création environnement virtuel..."
    
    if python3 -m venv venv >> "$LOG_FILE" 2>&1; then
        print_success "Environnement virtuel créé"
        log_info "Venv created"
    else
        print_error "Échec création venv"
        log_error "Venv creation failed"
        
        # Tentative avec virtualenv si disponible
        print_warning "Tentative avec virtualenv..."
        if command -v virtualenv &> /dev/null || eval "$PKG_INSTALL python3-virtualenv" >> "$LOG_FILE" 2>&1; then
            if virtualenv venv >> "$LOG_FILE" 2>&1; then
                print_success "Environnement créé avec virtualenv"
                log_info "Venv created with virtualenv"
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi
fi

# Activer venv
source venv/bin/activate

echo ""

# ============================================================================
# PHASE 6: MISE À JOUR PIP
# ============================================================================
((STEP++))
print_step "$STEP/11" "Mise à jour de pip..."

if python -m pip install --upgrade pip --quiet >> "$LOG_FILE" 2>&1; then
    print_success "pip mis à jour avec succès"
    log_info "Pip upgraded"
else
    print_warning "Échec mise à jour pip, utilisation version existante"
    log_warn "Pip upgrade failed"
fi

echo ""

# ============================================================================
# PHASE 7: INSTALLATION DÉPENDANCES PYTHON (CRITIQUE)
# ============================================================================
((STEP++))
print_step "$STEP/11" "Installation des dépendances Python (5-10 minutes)..."

if [ ! -f "requirements.txt" ]; then
    print_error "Fichier requirements.txt manquant"
    log_error "requirements.txt missing"
    exit 1
fi

print_warning "Installation en cours..."
echo -e "${CYAN}  (beautifulsoup4, Flask, pywebview, cryptography, etc...)${NC}"

# Tentative 1: Installation normale
if pip install -r requirements.txt --quiet >> "$LOG_FILE" 2>&1; then
    print_success "Toutes les dépendances installées"
    log_info "Dependencies installed (attempt 1)"
else
    print_warning "Échec, nouvelle tentative sans cache..."
    log_warn "Dependencies install failed, retrying without cache"
    
    # Tentative 2: Sans cache
    if pip install -r requirements.txt --no-cache-dir >> "$LOG_FILE" 2>&1; then
        print_success "Dépendances installées (sans cache)"
        log_info "Dependencies installed (attempt 2, no-cache)"
    else
        print_warning "Échec, tentative avec builds legacy..."
        log_warn "Dependencies install failed, trying with legacy builds"
        
        # Tentative 3: Avec builds legacy (pour anciennes distros)
        if pip install -r requirements.txt --no-cache-dir --use-deprecated=legacy-resolver >> "$LOG_FILE" 2>&1; then
            print_success "Dépendances installées (mode legacy)"
            log_info "Dependencies installed (attempt 3, legacy)"
        else
            print_error "Échec installation dépendances"
            log_error "Dependencies installation failed (all attempts)"
            echo ""
            echo "Consultez le log: $LOG_FILE"
            exit 1
        fi
    fi
fi

echo ""

# ============================================================================
# PHASE 8: CONFIGURATION ENVIRONNEMENT (.env, secret.key)
# ============================================================================
((STEP++))
print_step "$STEP/11" "Configuration de l'environnement..."

if [ -f "scripts/setup_env.py" ]; then
    print_warning "Exécution setup_env.py..."
    
    if python scripts/setup_env.py >> "$LOG_FILE" 2>&1; then
        print_success "Fichier .env et secret.key générés"
        log_info "Environment configured"
    else
        print_warning "Échec setup_env.py"
        log_warn "setup_env.py failed"
    fi
else
    print_warning "Script setup_env.py non trouvé"
    log_warn "setup_env.py not found"
fi

# Vérifier fichiers critiques
if [ ! -f ".env" ]; then
    print_warning "Fichier .env manquant, création par défaut..."
    echo "SECRET_KEY=default_secret_key" > .env
fi

if [ ! -f "secret.key" ]; then
    print_warning "Fichier secret.key manquant, génération..."
    python -c "from cryptography.fernet import Fernet; open('secret.key', 'wb').write(Fernet.generate_key())" 2>/dev/null || true
fi

echo ""

# ============================================================================
# PHASE 9: COPIE ICÔNE
# ============================================================================
((STEP++))
print_step "$STEP/11" "Copie de l'icône..."

INSTALLER_DIR="$(dirname "$(readlink -f "$0")")"
ICON_SOURCE="$INSTALLER_DIR/logorezos.png"

if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_DIR/logorezos.png" 2>/dev/null || true
    print_success "Icône copiée"
    log_info "Icon copied"
else
    print_warning "Icône source non trouvée: $ICON_SOURCE"
    log_warn "Icon not found"
fi

echo ""

# ============================================================================
# PHASE 10: CRÉATION RACCOURCI .desktop
# ============================================================================
((STEP++))
print_step "$STEP/11" "Création du raccourci..."

mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/tatbooker.desktop << EOF
[Desktop Entry]
Name=TATBooker
Comment=Application de gestion touristique
Exec=$APP_DIR/venv/bin/python3 $APP_DIR/main_webapp.py
Icon=$APP_DIR/logorezos.png
Terminal=false
Type=Application
Categories=Office;Business;
EOF

chmod +x ~/.local/share/applications/tatbooker.desktop

if [ -f ~/.local/share/applications/tatbooker.desktop ]; then
    print_success "Raccourci créé: ~/.local/share/applications/tatbooker.desktop"
    log_info "Desktop shortcut created"
else
    print_warning "Échec création raccourci"
    log_warn "Shortcut creation failed"
fi

echo ""

# ============================================================================
# PHASE 11: VALIDATION FINALE
# ============================================================================
((STEP++))
print_step "$STEP/11" "Validation de l'installation..."

# Test imports critiques
if python -c "import webview, flask, sqlite3, cryptography" >> "$LOG_FILE" 2>&1; then
    print_success "Tous les modules critiques sont OK"
    log_info "Critical imports validated"
else
    print_error "Modules critiques manquants"
    log_error "Critical imports failed"
    exit 1
fi

# Vérifier fichier principal
if [ -f "$APP_DIR/main_webapp.py" ]; then
    print_success "Fichier principal: OK"
    log_info "main_webapp.py found"
else
    print_error "Fichier main_webapp.py manquant"
    log_error "main_webapp.py missing"
    exit 1
fi

print_success "Base de données: OK"

echo ""

# ============================================================================
# SUCCÈS - INSTALLATION TERMINÉE
# ============================================================================
clear
echo ""
echo "============================================"
echo ""
echo -e "${GREEN}     INSTALLATION TERMINÉE !${NC}"
echo ""
echo "============================================"
echo ""
echo -e "  ${GREEN}✓${NC} TATBooker est prêt à l'emploi"
echo ""
echo -e "  ${CYAN}Lancement:${NC}"
echo "    - Menu Applications → TATBooker"
echo "    - Ou: cd $APP_DIR && source venv/bin/activate && python3 main_webapp.py"
echo ""
echo -e "  ${YELLOW}Mise à jour:${NC}"
echo "    - Relancez ce script install.sh"
echo ""
echo -e "  ${BLUE}Log d'installation:${NC}"
echo "    - $LOG_FILE"
echo ""
echo "============================================"
echo ""

log_info "Installation terminée avec succès"

echo -e "${YELLOW}Lancement automatique dans 5 secondes...${NC}"
echo "(Appuyez sur Ctrl+C pour annuler)"
sleep 5

cd "$APP_DIR"
source venv/bin/activate
python3 main_webapp.py &

exit 0
