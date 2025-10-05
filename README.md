# ⚡ manage_zerossl — Automatisez vos certificats ZeroSSL en 6 étapes

![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=fff)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![CI](https://img.shields.io/badge/status-weekend_project-ff69b4)

Un petit script bash, made with love le temps d’un week‑end, pour demander, valider et installer des certificats ZeroSSL en gardant votre clé privée 100% chez vous. Simple, lisible, et prêt pour la prod. 🔐🚀


## ✨ Points forts
- 🔏 Sécurité first: génération locale de la clé privée + CSR
- 🤖 Workflow guidé de bout en bout (création → validation → téléchargement)
- 🌐 Validation HTTP automatisée via un conteneur Apache éphémère
- 🧩 Zéro JSON manual: le script s’occupe des appels API
- 🧰 Idempotent: relances et reprises faciles


## 🚧 Prérequis
- Un compte sur le site https://app.zerossl.com
- Linux (bash)
- Accès root (sudo ou root direct)
- Outils: `curl`, `jq`, `openssl`, `unzip` (recommandé)
- Docker (pour la validation HTTP automatique)
- Ports ouverts: 80 (HTTP) et 443 (HTTPS)


## 🔐 Configuration
1) Access key ZeroSSL (obligatoire)
Créez le fichier `/root/secret_zerossl.sh`:

```bash
#!/bin/bash
export access_key="votre_access_key"
```

2) Nom de domaine
- À la première exécution, si `./domain_name.sh` n’existe pas, le script vous demandera votre domaine et créera le fichier automatiquement.
- Format du fichier généré:

```bash
#!/bin/bash
DOMAIN="votre-domaine.tld"
```

Les certificats seront stockés dans `/etc/ssl/certs/$DOMAIN`.


## ⚙️ Installation rapide
Installez les dépendances système et vérifiez Docker:

```zsh
sudo ./scripts/install_deps.sh
```


## 🧭 Workflow express
1) Générer le CSR + clé privée (localement)
2) Créer la demande de certificat chez ZeroSSL
3) Démarrer un Apache jetable pour la validation HTTP
4) Lancer la vérification côté ZeroSSL
5) Arrêter le conteneur Apache
6) Télécharger le certificat signé et générer `fullchain.pem`




## 🧪 Commandes
- Génération locale sécurisée
```zsh
sudo ./manage_zerossl.sh create_csr
```

- Création du certificat + lancement de la vérification
```zsh
sudo ./manage_zerossl.sh create
```

- Démarrer le serveur temporaire pour la validation HTTP
```zsh
sudo ./manage_zerossl.sh ctstart
```

- Lancer/relancer la vérification (utile après démarrage du serveur)
```zsh
sudo ./manage_zerossl.sh verify
```

- Arrêter le conteneur Apache
```zsh
sudo ./manage_zerossl.sh ctstop
```

- Télécharger les fichiers signés (ZIP), extraire et créer `fullchain.pem`
```zsh
sudo ./manage_zerossl.sh download
```

- Récupérer l’état et les métadonnées du certificat
```zsh
sudo ./manage_zerossl.sh get
```

- Vérifier localement le certificat et la clé privée
```zsh
sudo ./manage_zerossl.sh check_cert
```

- Renouveler (si expiration < 30 jours)
```zsh
sudo ./manage_zerossl.sh renew
```

- Aide intégrée
```zsh
./manage_zerossl.sh help
```


## 🔎 Détails techniques et sécurité
- CSR et clé privée sont générés localement puis stockés dans `/etc/ssl/certs/$DOMAIN/`.
- `fullchain.pem` est automatiquement construit en concaténant `certificate.crt` + `ca_bundle.crt`.
- Permissions durcies pour la clé privée (`chmod 600`).
- Le script stocke l’ID du certificat ZeroSSL dans `cert_id` pour suivre l’état et retenter.


## 🧯 Dépannage rapide
- Validation HTTP: assurez‑vous que le port 80 est ouvert et routé vers la machine exécutant le conteneur Apache.
- Fichier de validation: la commande `get` prépare automatiquement le fichier attendu par ZeroSSL.
- Erreurs API: les réponses JSON sont imprimées avec `jq` pour inspection.
- Pas d’unzip? Conservez le ZIP téléchargé dans le dossier du domaine et extrayez‑le manuellement.


## 💡 Astuce
Vous pouvez forcer la méthode de validation en ajustant la variable `VALIDATION_METHOD` dans le script (`HTTP_CSR_HASH`, `CNAME_CSR_HASH`, `EMAIL`).


## 🏁 Résultat attendu
- Un certificat valide + votre clé privée gardée en local
- Des fichiers prêts pour Nginx/Apache: `privkey.pem` et `fullchain.pem`


---
Fait avec ❤️, café ☕ et quelques emojis bien sentis ✨

## 📄 Licence

Ce projet est distribué sous licence MIT. Voir le fichier `LICENSE`.
