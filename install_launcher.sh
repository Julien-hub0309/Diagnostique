#!/bin/bash

# --- Configuration ---
APP_NAME="fo_diagramme"
# Dossier où se trouve ce script (la racine du projet)
PROJECT_DIR=$(pwd)
# Chemin vers l'exécutable compilé
EXECUTABLE="$PROJECT_DIR/build/linux/x64/release/bundle/$APP_NAME"
# Nom du fichier .desktop de sortie
DESKTOP_FILE="fo_printer.desktop"
# Dossier système pour les lanceurs utilisateur
INSTALL_DIR="$HOME/.local/share/applications"

# 1. Vérifier si le build existe
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Erreur : L'exécutable n'a pas été trouvé à :"
    echo "   $EXECUTABLE"
    echo "   Veuillez d'abord compiler l'application avec : flutter build linux --release"
    exit 1
fi

# 2. Créer le fichier .desktop dynamiquement
echo "⚙️ Génération du fichier $DESKTOP_FILE..."

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Fo Printer
Comment=Mon application Flutter de gestion d'impression
Exec=$EXECUTABLE
Path=$PROJECT_DIR/build/linux/x64/release/bundle/
Icon=$PROJECT_DIR/assets/background.png
Terminal=false
Categories=Utility;Application;
EOF

# 3. Installer le lanceur
echo "📦 Installation du lanceur dans $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$DESKTOP_FILE" "$INSTALL_DIR/"

# 4. Finalisation
echo "✅ Installation terminée !"
echo "Vous pouvez maintenant trouver 'Fo Printer' dans votre menu d'applications."