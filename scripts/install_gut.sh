#!/usr/bin/env bash
# Télécharge et installe le plugin GUT (Godot Unit Test) dans addons/gut/.
# À exécuter une seule fois en local avant d'ouvrir le projet dans Godot.
# GUT 9.x est requis pour Godot 4.x.
set -euo pipefail

GUT_VERSION="9.3.0"
GUT_URL="https://github.com/bitwes/Gut/releases/download/v${GUT_VERSION}/Gut_v${GUT_VERSION}.zip"
TMP_ZIP="/tmp/gut_${GUT_VERSION}.zip"
TMP_DIR="/tmp/gut_extract_$$"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Installation de GUT v${GUT_VERSION} dans ${PROJECT_ROOT}/addons/gut/"

if [ -d "${PROJECT_ROOT}/addons/gut" ]; then
    echo "    addons/gut/ existe déjà — suppression pour réinstaller."
    rm -rf "${PROJECT_ROOT}/addons/gut"
fi

echo "==> Téléchargement depuis GitHub..."
curl -fsSL "$GUT_URL" -o "$TMP_ZIP"

echo "==> Extraction..."
mkdir -p "$TMP_DIR"
unzip -q "$TMP_ZIP" -d "$TMP_DIR"

mkdir -p "${PROJECT_ROOT}/addons"
cp -r "${TMP_DIR}/addons/gut" "${PROJECT_ROOT}/addons/gut"

rm -rf "$TMP_ZIP" "$TMP_DIR"

echo ""
echo "✓ GUT installé dans addons/gut/"
echo ""
echo "Étapes suivantes :"
echo "  1. Ouvrez le projet dans Godot"
echo "  2. Project > Project Settings > Plugins > Gut > Enable"
echo "  3. Lancez les tests en ligne de commande :"
echo "     godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit"
