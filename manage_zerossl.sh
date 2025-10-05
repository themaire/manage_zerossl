#!/usr/bin/env bash
set -euo pipefail

# Chargement des secrets (export access_key="...") depuis /root/secret_zerossl.sh si présent
if [ -f /root/secret_zerossl.sh ]; then
  # shellcheck disable=SC1091
  . /root/secret_zerossl.sh
  # echo "Access key trouvée : $access_key."
else
  echo "Aucun fichier de secret trouvé (/root/secret_zerossl.sh). Vous devez définir 'access_key' dans /root/secret_zerossl.sh".
  usage
  exit 1
fi

# Variables

# IMPORTANT: access_key doit venir de /root/secret_zerossl.sh ou de l'env
access_key="${access_key:-}"

# Gestion du domaine via ./domain_name.sh (créé automatiquement si absent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN_FILE="$SCRIPT_DIR/domain_name.sh"

# Si le fichier existe, on le source pour récupérer DOMAIN
if [ -f "$DOMAIN_FILE" ]; then
  # shellcheck disable=SC1090
  . "$DOMAIN_FILE"
else
  read -rp "Entrez votre nom de domaine (ex: example.com): " DOMAIN
  if [ -z "${DOMAIN:-}" ]; then
    echo "Nom de domaine vide. Abandon."
    exit 1
  fi
  cat > "$DOMAIN_FILE" <<EOF
#!/bin/bash
DOMAIN="${DOMAIN}"
EOF
  chmod 644 "$DOMAIN_FILE" || true
  echo "Fichier de configuration domaine créé: $DOMAIN_FILE"
fi

# Répertoires et fichiers liés au domaine
CERT_DIR="/etc/ssl/certs/$DOMAIN" # Répertoire certs
CERT_ID_FILE="$CERT_DIR/cert_id"                          # Stockage de l'ID
CSR_FILE="$CERT_DIR/csr.pem"                              # Chemin du CSR

VALIDATION_METHOD="HTTP_CSR_HASH"   # Méthode de validation (choix possibles HTTP_CSR_HASH, CNAME_CSR_HASH ou EMAIL)
# Sinon methode par CNAME: CNAME_CSR_HASH
# VALIDATION_METHOD="CNAME_CSR_HASH"   # Méthode de validation (autres possibilités CNAME_CSR_HASH ou EMAIL)


# Garde-fous pour verifier si les outils nécessaires sont présents
command -v curl >/dev/null 2>&1 || { echo "curl manquant"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq manquant"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl manquant"; exit 1; }

# Créer le répertoire pour les certificats si nécessaire
mkdir -p "$CERT_DIR"

usage() {
  cat <<'EOF'
Usage: manage_zerossl.sh <commande>

Pré-requis:
Script à utiliser avec les droits administrateur (root).

ZeroSSL vous offre gratuitement des certificats SSL/TLS valides pour vos domaines. Il s'agit d'une autorité de certification (CA) reconnue, similaire à Let's Encrypt.
Vous avez le droit à 3 certificats gratuits de 90 jours par domaine (renouvelables).

!!
!IMPORTANT! NECESSITE DOCKER POUR LANCER UN CONTENEUR APACHE TEMPORAIREMENT POUR LA VALIDATION HTTP !!!
!IMPORTANT! Ne pas oublier d'ouvrir le port 80 sur le firewall (et éventuellement sur votre machine avec "ufw allow 80") et le port 443 pour profiter du HTTPS.
!!

Le nom de votre domaine à certifier est lu depuis ./domain_name.sh (créé automatiquement si absent à la première exécution).
Il faut aussi définir 'access_key' via /root/secret_zerossl.sh.
Définissez 'access_key' via /root/secret_zerossl.sh (fichier d'environnement sécurisé dans le dossier /root).
Contenu du fichier /root/secret_zerossl.sh (exemple, ne mettez pas la serie de tirets):
-------------------------------------
#!/bin/bash
export access_key="votre_access_key"
-------------------------------------

Contenu du fichier ./domain_name.sh (auto-généré) :
-------------------------------------
#!/bin/bash
DOMAIN="votre-domaine.tld"
-------------------------------------

# Workflow complet
./manage_zerossl.sh create_csr # Génération locale sécurisée
./manage_zerossl.sh create # Demande à ZeroSSL
./manage_zerossl.sh ctstart # Serveur temp pour validation HTTP
./manage_zerossl.sh verify # Validation du domaine
./manage_zerossl.sh ctstop # Quand vous aurez reçu l'email de validation
./manage_zerossl.sh download # Récupération du certificat signé

Principe :
ETAPE 1
Créer un CSR et une clé privée localement (vous gardez la clé privée) via la commande "create_csr".
Il sera créé dans $CERT_DIR (ex: /etc/ssl/certs/votre_domaine/csr.pem).

🏛️ Information sur le rôle de ZeroSSL (CA) :
ZeroSSL prend votre CSR (certificat prêt à être signé, il contient la clé publique et les 
informations nécessaires à la validation).

ETAPE 2
Faites votre demande de certificat via la commande "create".

ETAPE 3
Allumer votre serveur web temporairement (ex: conteneur Apache) pour servir le fichier de validation HTTP.
Pour ce faire le script a une commande "ctstart" qui démarre un conteneur Apache avec le fichier de validation.
Cela est complement automatisé car le script extrait le nom et le contenu du fichier de validation via la commande "get".
Vous n'avez rien à faire de plus.

ETAPE 4
ZeroSSL vérifie que vous contrôlez le domaine (validation HTTP/DNS) via la commande "verify" + un petit délai
à attendre le temps que la validation soit effective.
Une fois la vérification effectuée, ZeroSSL signe votre certificat avec leur clé privée de CA. Vous recevez un
email de confirmation. Le certificat à un statut "issued".

ETAPE 5
Arrêter le conteneur Apache avec la commande "ctstop".

ETAPE 6
Il est temps de télécharger le certificat signé (certificate.crt) via la commande "download".
Cela télécharge un ZIP et extrait les fichiers dans $CERT_DIR. C'est a dire dans le dossier
/etc/ssl/certs/votre_domaine.
Le fichier fullchain.pem est créé en concaténant certificate.crt et ca_bundle.crt par la meme occasion.
!! C'est ce fichier fullchain.pem qu'il vous sera utile pour l'utiliser dans Apache/Nginx accompagné de la clé privée (privkey.pem).

🔄 Récapitulatif du processus sécurisé
Vous : Générez CSR + clé privée localement
ZeroSSL : Reçoit uniquement le CSR (clé publique)
ZeroSSL : Valide le domaine et signe le certificat
Vous : Récupérez le certificat signé
Résultat : Certificat valide + clé privée 100% sous votre contrôle

Commandes:
  create_csr    Génère le CSR et la clé privée localement (étape préalable)
  create        Crée un nouveau certificat et lance la vérification de domaine
  verify        Lance uniquement la vérification de domaine (utilise cert_id sauvegardé)
  get           Récupère les métadonnées du certificat (status, dates...) via "Get certificate"
  download      Télécharge le certificat (ZIP) et extrait les fichiers
  renew         Renouvelle si le certificat expire bientôt (< 30 jours)
  help          Affiche cette aide

Notes:
- L'ID du certificat est mémorisé dans: cert_id
EOF
}

load_cert_id() {
  if [ -z "${CERT_ID:-}" ] && [ -f "$CERT_ID_FILE" ]; then
    CERT_ID="$(cat "$CERT_ID_FILE")"
  fi
  if [ -z "${CERT_ID:-}" ]; then
    echo "CERT_ID introuvable. Créez d'abord un certificat (commande: create)."
    exit 1
  fi
}

# Fonction pour créer le CSR et la clé privée
create_csr() {
  echo "Création du CSR et de la clé privée pour le domaine: $DOMAIN"
  
  # Créer le répertoire si nécessaire
  mkdir -p "$CERT_DIR"
  
  # Vérifier si les fichiers existent déjà
  if [ -f "$CSR_FILE" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "CSR et clé privée existent déjà:"
    echo "  CSR: $CSR_FILE"
    echo "  Clé privée: $CERT_DIR/privkey.pem"
    read -p "Voulez-vous les recréer ? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Conservation des fichiers existants."
      return 0
    fi
  fi
  
  # Générer le CSR et la clé privée
  echo "Génération du CSR et de la clé privée..."
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$CERT_DIR/privkey.pem" \
    -out "$CSR_FILE" \
    -subj "/CN=$DOMAIN"
  
  # Vérifier que les fichiers ont été créés
  if [ -f "$CSR_FILE" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "✅ CSR créé: $CSR_FILE"
    echo "✅ Clé privée créée: $CERT_DIR/privkey.pem"
    
    # Sécuriser la clé privée
    chmod 600 "$CERT_DIR/privkey.pem"
    echo "🔒 Permissions de la clé privée sécurisées (600)"
    
    echo ""
    echo "Vous pouvez maintenant créer le certificat avec: ./manage_zerossl.sh create"
  else
    echo "❌ Erreur lors de la création du CSR ou de la clé privée"
    exit 1
  fi
}

# Fonction pour créer le certificat
create_certificate() {
  # Lire le CSR local (recommandé: vous gardez la clé privée)
  if [ ! -f "$CSR_FILE" ]; then
    echo "CSR introuvable: $CSR_FILE"
    echo "Générez-le par exemple:"
    echo "openssl req -new -newkey rsa:2048 -nodes -keyout \"$CERT_DIR/privkey.pem\" -out \"$CSR_FILE\" -subj \"/CN=$DOMAIN\""
    exit 1
  fi

  # Appel ZeroSSL en form-encoded (pas JSON)
  response="$(curl -s -X POST "https://api.zerossl.com/certificates?access_key=$access_key" \
    --data-urlencode "certificate_domains=$DOMAIN" \
    --data-urlencode "certificate_validity_days=90" \
    --data-urlencode "certificate_csr@${CSR_FILE}")"

  # Succès si pas d'objet error et présence d'un id
  if echo "$response" | jq -e '(.error | not) and (.id != null)' >/dev/null 2>&1; then
    echo "Certificat créé avec succès."
    CERT_ID="$(echo "$response" | jq -r '.id')"
    echo "$CERT_ID" > "$CERT_ID_FILE"
    echo "CERT_ID: $CERT_ID"

    # Tip: affiche un résumé de validation pour savoir quoi déployer (HTTP/DNS)
    echo "Résumé validation:"
    echo "$response" | jq '.validation // empty'

    # Certains champs ne sont présents qu’après émission; on ne les force pas ici
  else
    echo "Erreur lors de la création du certificat:"
    echo "$response" | jq .
    exit 1
  fi
}

# Fonction pour vérifier le domaine
verify_domain() {
  load_cert_id
  
  verification_response="$(curl -s -X POST "https://api.zerossl.com/certificates/$CERT_ID/challenges?access_key=$access_key" \
  --data-urlencode "validation_method=$VALIDATION_METHOD")"
  sleep 1
  echo "$verification_response" | jq .

  if echo "$verification_response" | jq -e '(.error | not)' >/dev/null 2>&1; then
    echo "Vérification envoyée (méthode: $VALIDATION_METHOD)."
    # Affiche l’état pour suivre la progression
    echo "$verification_response" | jq '{id, status, validation}'
  else
    echo "Erreur lors de la vérification du domaine:"
    echo "$verification_response" | jq .
    exit 1
  fi

}

action_apache_container() {
    local action=$1
    case $action in
        start)
            echo "Démarrage du conteneur Apache..."
            docker run -d --name apache-container -p 80:80 -v "/root/make_cert/$validation_file_name:/usr/local/apache2/htdocs/.well-known/pki-validation/$validation_file_name" httpd
            ;;
        stop)
            echo "Arrêt du conteneur Apache..."
            docker stop apache-container
            sleep 1
            docker rm apache-container
            docker image rm apache-container
            ;;
        *)
            echo "Usage: $0 {start|stop}"
            ;;
    esac
}

# Fonction "Get certificate" (métadonnées/status)
get_certificate() {
  load_cert_id
  get_resp="$(curl -s -G "https://api.zerossl.com/certificates/$CERT_ID" \
    --data-urlencode "access_key=$access_key")"

  echo $get_resp | jq .

  # Extraire le nom de fichier de la réponse
  validation_file_name=$(echo "$get_resp" | jq -r --arg domain "$DOMAIN" '.validation.other_methods[$domain].file_validation_url_http | split("/") | last')
  # Afficher le nom de fichier
  # echo "Nom de fichier de validation: $validation_file_name"

  # Extraire le contenu de file_validation_content
  validation_content=$(echo "$get_resp" | jq -r --arg domain "$DOMAIN" '.validation.other_methods[$domain].file_validation_content')

  # Vider le contenu du fichier
  verification_file_path="/root/make_cert/$validation_file_name"
  rm $verification_file_path && touch $verification_file_path

  # Écrire chaque élément dans le fichier sans les fioritures
  echo "$validation_content" | jq -r '.[]' >> "$verification_file_path"

  # Affiche le status et quelques champs utiles
  echo "Informations du certificat:"
  # echo "$get_resp" | jq '{id, status, common_name: .certificate.common_name, created: .created, expires: .expires, validation: .validation}'
}

# Fonction pour télécharger le certificat (ZIP) et extraire
download_certificate() {
  load_cert_id

  url="https://api.zerossl.com/certificates/$CERT_ID/download?access_key=$access_key"
  echo "URL du zip $url."

  zip_path="$CERT_DIR/${DOMAIN}_${CERT_ID}.zip"
  echo "Téléchargement du certificat (ZIP) vers: $zip_path"
  
  curl -f -sS -G $url -o "$zip_path"

  # Si le fichier ressemble à du texte, c'est probablement une erreur JSON
  if file -b --mime-type "$zip_path" 2>/dev/null | grep -qi 'text'; then
    echo "Réponse texte (erreur probable):"
    cat "$zip_path"
    exit 1
  fi

  if command -v unzip >/dev/null 2>&1; then
    echo "Extraction du ZIP dans $CERT_DIR"
    unzip -o -q "$zip_path" -d "$CERT_DIR"
    echo "Contenu extrait. Pensez à pointer Apache vers les bons fichiers (ex: certificate.crt, ca_bundle.crt)."
    # À la fin de download_certificate()
    cat "$CERT_DIR/certificate.crt" "$CERT_DIR/ca_bundle.crt" > "$CERT_DIR/fullchain.pem" || true
    chmod 600 "$CERT_DIR/privkey.pem"
    chmod 644 "$CERT_DIR"/{certificate.crt,ca_bundle.crt,fullchain.crt}
  else
    echo "unzip non disponible. Conservez le ZIP à cet emplacement et extrayez-le manuellement."
  fi
}

# Fonction pour renouveler le certificat
renew_certificate() {
  # Si aucun cert actuel, on force la création
  if [ ! -f "$CERT_DIR/cert.pem" ]; then
    echo "Aucun certificat existant trouvé. Création d'un nouveau certificat..."
    create_certificate
    verify_domain
    return
  fi

  expiration_raw="$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  if [ -z "$expiration_raw" ]; then
    echo "Impossible de lire la date d'expiration. Recréation du certificat..."
    create_certificate
    verify_domain
    return
  fi

  expiration_ts="$(date -d "$expiration_raw" +%s)"
  now_ts="$(date +%s)"

  if (( (expiration_ts - now_ts) < 2592000 )); then
    echo "Le certificat expire bientôt. Renouvellement en cours..."
    create_certificate
    verify_domain
  else
    echo "Le certificat est toujours valide (expiration: $expiration_raw)."
  fi
}

# Fonction pour vérifier le certificat et la clé privée
check_certificates() {
  echo "\n🔎 Vérification du certificat (fullchain.pem) :"
  if openssl x509 -in "$CERT_DIR/fullchain.pem" -text -noout; then
    echo "\n✅ Le certificat est valide et lisible."
  else
    echo "\n❌ Erreur lors de la lecture du certificat fullchain.pem."
    return 1
  fi

  echo "\n🔎 Vérification de la clé privée (privkey.pem) :"
  if openssl rsa -in "$CERT_DIR/privkey.pem" -check >/dev/null 2>&1; then
    echo "✅ La clé privée existe et est valide (permissions et format corrects)."
  else
    echo "❌ Erreur lors de la vérification de la clé privée. Détail :"
    openssl rsa -in "$CERT_DIR/privkey.pem" -check
    return 1
  fi
}

# ---------- Dispatch CLI ----------
if [ $# -lt 1 ]; then
  usage
  exit 1
fi

case "$1" in
  create_csr)
    create_csr
    ;;
  create)
    create_certificate
    verify_domain
    ;;
  renew)
    renew_certificate
    ;;
  verify)
    get_certificate
    verify_domain
    ;;
  get)
    get_certificate
    ;;
  download)
    download_certificate
    check_certificates
    ;;
  ctstart)
    get_certificate
    action_apache_container start
    ;;
  ctstop)
    action_apache_container stop 
    ;;
  check_cert)
    check_certificates
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Commande inconnue: $1"
    usage
    exit 1
    ;;
esac