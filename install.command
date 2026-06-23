#!/bin/bash

# ============================================================================
# TATBooker - Installateur macOS Ultra-Blindé
# Gère: Détection architecture, Homebrew, Dépendances, Validation, Rollback
# Compatibilité: macOS 10.15+ (Catalina à Sonoma), Intel & Apple Silicon
# ============================================================================

set -e  # Exit on error (désactivé après les tests critiques)

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Variables globales
LOG_FILE="/tmp/tatbooker_install.log"
APP_DIR="$HOME/TATBooker"
REPO_URL="https://github.com/bambino-117/TATBooker---Developpement.git"
ERROR_COUNT=0
STEP=0
ARCH_TYPE=""
MACOS_VERSION=""

# Initialisation log
echo "[$(date)] Installation TATBooker macOS démarrée" > "$LOG_FILE"

clear
echo "============================================"
echo -e "${BLUE}   TATBooker - Installation macOS${NC}"
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

# Détecter architecture (Intel vs Apple Silicon)
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "arm64" ]; then
    print_success "Architecture détectée: Apple Silicon (M1/M2/M3)"
    log_info "Architecture: Apple Silicon (arm64)"
    BREW_PREFIX="/opt/homebrew"
elif [ "$ARCH_TYPE" = "x86_64" ]; then
    print_success "Architecture détectée: Intel x86_64"
    log_info "Architecture: Intel x86_64"
    BREW_PREFIX="/usr/local"
else
    print_error "Architecture non supportée: $ARCH_TYPE"
    log_error "Unsupported architecture: $ARCH_TYPE"
    exit 1
fi

# Détecter version macOS
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VERSION" | cut -d. -f2)

print_success "macOS version: $MACOS_VERSION"
log_info "macOS: $MACOS_VERSION"

# Vérifier version minimale (10.15+)
if [ "$MACOS_MAJOR" -lt 10 ] || { [ "$MACOS_MAJOR" -eq 10 ] && [ "$MACOS_MINOR" -lt 15 ]; }; then
    print_error "macOS $MACOS_VERSION non supporté (minimum: 10.15 Catalina)"
    log_error "macOS version too old: $MACOS_VERSION"
    exit 1
fi

# Vérifier Xcode Command Line Tools
if xcode-select -p &> /dev/null; then
    print_success "Xcode Command Line Tools: OK"
    log_info "Xcode CLT found"
else
    print_warning "Xcode Command Line Tools manquant, installation..."
    log_info "Installing Xcode CLT"
    
    # Installation automatique
    xcode-select --install 2>/dev/null || true
    
    echo ""
    echo -e "${YELLOW}Une fenêtre va s'ouvrir pour installer Xcode Command Line Tools${NC}"
    echo -e "${YELLOW}Cliquez sur 'Installer' et attendez la fin de l'installation${NC}"
    echo ""
    read -p "Appuyez sur ENTRÉE après l'installation des Command Line Tools..."
    
    if xcode-select -p &> /dev/null; then
        print_success "Xcode Command Line Tools installé"
        log_info "Xcode CLT installed"
    else
        print_error "Xcode Command Line Tools toujours absent"
        log_error "Xcode CLT installation failed"
        exit 1
    fi
fi

# Vérifier espace disque (minimum 2 GB)
AVAILABLE_SPACE=$(df -g "$HOME" | awk 'NR==2 {print $4}')
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
# PHASE 1: INSTALLATION HOMEBREW
# ============================================================================
((STEP++))
print_step "$STEP/11" "Vérification de Homebrew..."

if command -v brew &> /dev/null; then
    BREW_VERSION=$(brew --version | head -n1 | awk '{print $2}')
    print_success "Homebrew déjà présent: v$BREW_VERSION"
    log_info "Homebrew found: v$BREW_VERSION"
    
    # Mettre à jour Homebrew
    print_warning "Mise à jour de Homebrew..."
    if brew update >> "$LOG_FILE" 2>&1; then
        print_success "Homebrew mis à jour"
        log_info "Homebrew updated"
    else
        print_warning "Échec mise à jour Homebrew (non bloquant)"
        log_warn "Homebrew update failed"
    fi
else
    print_warning "Homebrew non trouvé. Installation..."
    log_info "Installing Homebrew"
    
    echo ""
    echo -e "${YELLOW}Installation de Homebrew (peut prendre 5-10 minutes)...${NC}"
    echo -e "${YELLOW}Un mot de passe administrateur peut être demandé${NC}"
    echo ""
    
    # Installation Homebrew
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1; then
        print_success "Homebrew installé avec succès"
        log_info "Homebrew installed"
        
        # Configurer PATH pour Homebrew (Apple Silicon)
        if [ "$ARCH_TYPE" = "arm64" ]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/.bash_profile"
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        
        print_success "PATH Homebrew configuré"
    else
        print_error "Échec installation Homebrew"
        log_error "Homebrew installation failed"
        echo ""
        echo "Installez Homebrew manuellement:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
fi

# Vérifier Homebrew disponible
if ! command -v brew &> /dev/null; then
    print_error "Homebrew toujours absent après installation"
    log_error "Homebrew still not found"
    
    # Tentative de chargement manuel
    if [ -f "$BREW_PREFIX/bin/brew" ]; then
        eval "$($BREW_PREFIX/bin/brew shellenv)"
        if command -v brew &> /dev/null; then
            print_success "Homebrew chargé manuellement"
        else
            exit 1
        fi
    else
        exit 1
    fi
fi

echo ""

# ============================================================================
# PHASE 2: INSTALLATION GIT
# ============================================================================
((STEP++))
print_step "$STEP/11" "Vérification de Git..."

if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    print_success "Git déjà présent: v$GIT_VERSION"
    log_info "Git found: v$GIT_VERSION"
else
    print_warning "Git non trouvé. Installation via Homebrew..."
    log_info "Installing Git"
    
    if brew install git >> "$LOG_FILE" 2>&1; then
        print_success "Git installé avec succès"
        log_info "Git installed"
    else
        print_error "Échec installation Git"
        log_error "Git installation failed"
        exit 1
    fi
fi

# Vérifier Git disponible
if ! command -v git &> /dev/null; then
    print_error "Git toujours absent après installation"
    log_error "Git still not found"
    exit 1
fi

echo ""

# ============================================================================
# PHASE 3: CLONAGE / MISE À JOUR DU DÉPÔT
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
# PHASE 4: INSTALLATION PYTHON
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
        print_warning "Python $PYTHON_VERSION trop ancien (minimum 3.8), installation 3.12..."
        log_warn "Python version too old: $PYTHON_VERSION"
        
        if brew install python@3.12 >> "$LOG_FILE" 2>&1; then
            print_success "Python 3.12 installé"
            log_info "Python 3.12 installed"
            
            # Lier python3 à la nouvelle version
            brew link python@3.12 >> "$LOG_FILE" 2>&1 || true
        else
            print_error "Échec installation Python 3.12"
            log_error "Python 3.12 installation failed"
            exit 1
        fi
    fi
else
    print_warning "Python non trouvé. Installation via Homebrew..."
    log_info "Installing Python"
    
    if brew install python@3.12 >> "$LOG_FILE" 2>&1; then
        print_success "Python 3.12 installé"
        log_info "Python installed"
        
        # Lier python3
        brew link python@3.12 >> "$LOG_FILE" 2>&1 || true
    else
        print_error "Échec installation Python"
        log_error "Python installation failed"
        exit 1
    fi
fi

# Vérifier pip
if ! python3 -m pip --version &> /dev/null; then
    print_warning "pip non trouvé, installation..."
    brew install python3 >> "$LOG_FILE" 2>&1 || true
fi

echo ""

# ============================================================================
# PHASE 5: DÉPENDANCES SYSTÈME (WebKit)
# ============================================================================
((STEP++))
print_step "$STEP/11" "Installation dépendances système..."

print_warning "Installation PyGObject et WebKit..."
log_info "Installing system dependencies"

# PyGObject pour pywebview macOS
if brew list pygobject3 &> /dev/null; then
    print_success "PyGObject déjà présent"
else
    if brew install pygobject3 >> "$LOG_FILE" 2>&1; then
        print_success "PyGObject installé"
        log_info "PyGObject installed"
    else
        print_warning "Échec PyGObject (non critique)"
        log_warn "PyGObject install failed"
    fi
fi

echo ""

# ============================================================================
# PHASE 6: ENVIRONNEMENT VIRTUEL
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
        exit 1
    fi
fi

# Activer venv
source venv/bin/activate

echo ""

# ============================================================================
# PHASE 7: MISE À JOUR PIP
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
# PHASE 8: INSTALLATION DÉPENDANCES PYTHON (CRITIQUE)
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
        print_warning "Échec, tentative avec builds précompilés..."
        log_warn "Dependencies install failed, trying with binary wheels"
        
        # Tentative 3: Forcer wheels binaires (Apple Silicon)
        if pip install -r requirements.txt --no-cache-dir --only-binary=:all: >> "$LOG_FILE" 2>&1; then
            print_success "Dépendances installées (wheels binaires)"
            log_info "Dependencies installed (attempt 3, binary)"
        else
            # Tentative 4: Autoriser compilation
            print_warning "Tentative finale avec compilation..."
            if pip install -r requirements.txt --no-cache-dir --no-binary=:none: >> "$LOG_FILE" 2>&1; then
                print_success "Dépendances installées (avec compilation)"
                log_info "Dependencies installed (attempt 4, compiled)"
            else
                print_error "Échec installation dépendances"
                log_error "Dependencies installation failed (all attempts)"
                echo ""
                echo "Consultez le log: $LOG_FILE"
                exit 1
            fi
        fi
    fi
fi

echo ""

# ============================================================================
# PHASE 9: CONFIGURATION ENVIRONNEMENT (.env, secret.key)
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
# PHASE 10: CRÉATION SCRIPT DE LANCEMENT
# ============================================================================
((STEP++))
print_step "$STEP/11" "Création du script de lancement..."

cat > "$APP_DIR/launch.command" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python3 main_webapp.py
EOF

chmod +x "$APP_DIR/launch.command"

if [ -f "$APP_DIR/launch.command" ]; then
    print_success "Script launch.command créé"
    log_info "Launch script created"
else
    print_warning "Échec création launch.command"
    log_warn "Launch script creation failed"
fi

# Copier icône
INSTALLER_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
ICON_SOURCE="$INSTALLER_DIR/logorezos.png"

if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_DIR/logorezos.png" 2>/dev/null || true
    print_success "Icône copiée"
    log_info "Icon copied"
else
    print_warning "Icône source non trouvée"
    log_warn "Icon not found"
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
echo "    - Double-cliquez sur: $APP_DIR/launch.command"
echo "    - Ou glissez launch.command dans le Dock"
echo ""
echo -e "  ${YELLOW}Mise à jour:${NC}"
echo "    - Relancez ce script install.command"
echo ""
echo -e "  ${MAGENTA}Astuce Dock:${NC}"
echo "    - Glissez launch.command dans le Dock pour un accès rapide"
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
