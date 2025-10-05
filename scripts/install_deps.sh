#!/usr/bin/env bash
set -euo pipefail

# Installe les dépendances requises et vérifie Docker

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

# Détection simple de gestionnaire de paquets
if command -v apt-get >/dev/null 2>&1; then
  PKG="apt-get"
  UPDATE="apt-get update -y"
  INSTALL="apt-get install -y"
elif command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
  UPDATE="dnf -y makecache"
  INSTALL="dnf install -y"
elif command -v yum >/dev/null 2>&1; then
  PKG="yum"
  UPDATE="yum makecache -y"
  INSTALL="yum install -y"
elif command -v zypper >/dev/null 2>&1; then
  PKG="zypper"
  UPDATE="zypper refresh"
  INSTALL="zypper install -y"
else
  echo "Gestionnaire de paquets non supporté. Installez manuellement: curl jq openssl unzip docker." >&2
  exit 1
fi

echo "> Mise à jour des index... ($PKG)"
bash -lc "$UPDATE"

echo "> Installation: curl jq openssl unzip"
bash -lc "$INSTALL curl jq openssl unzip"

if ! command -v docker >/dev/null 2>&1; then
  echo "⚠️ Docker non trouvé. Installez Docker pour la validation HTTP automatique." >&2
else
  echo "✅ Docker détecté: $(docker --version | sed 's/, build.*//')"
fi

echo "Dépendances installées. Pensez à ouvrir les ports 80 et 443 si nécessaire."
