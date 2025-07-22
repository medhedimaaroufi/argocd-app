#!/bin/bash

set -euo pipefail

# Fonction pour afficher l'utilisation
usage() {
  echo "Usage : $0 <nom_app> <chemin_repo_git> [nom_branche]"
  exit 1
}

# Fonction pour nettoyer les fichiers temporaires
cleanup() {
  if [[ -n "${FICHIER_TEMP:-}" && -f "$FICHIER_TEMP" ]]; then
    rm -f "$FICHIER_TEMP"
    echo "[INFO] Fichier temporaire $FICHIER_TEMP supprimé."
  fi
  if [[ -n "${FICHIER_TEMP_FILTERED:-}" && -f "$FICHIER_TEMP_FILTERED" ]]; then
    rm -f "$FICHIER_TEMP_FILTERED"
    echo "[INFO] Fichier temporaire $FICHIER_TEMP_FILTERED supprimé."
  fi
}

# Trap pour garantir le nettoyage à la sortie
trap cleanup EXIT

# Fonction pour installer yq sur Ubuntu
install_yq() {
  echo "[INFO] yq non trouvé. Tentative d'installation de yq..."

  # Version de yq (dernière version stable au 22 juillet 2025)
  YQ_VERSION="v4.44.3"
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) YQ_BINARY="yq_linux_amd64" ;;
    aarch64) YQ_BINARY="yq_linux_arm64" ;;
    *) echo "[ERREUR] Architecture non supportée : $ARCH" ; exit 1 ;;
  esac

  # Essayer d'installer via snap
  if command -v snap >/dev/null 2>&1; then
    echo "[INFO] Installation de yq via snap..."
    if ! sudo snap install yq; then
      echo "[ERREUR] Échec de l'installation de yq via snap."
    else
      echo "[SUCCÈS] yq installé via snap."
      return 0
    fi
  else
    echo "[INFO] Snap non disponible. Téléchargement du binaire yq..."
  fi

  # Télécharger le binaire yq depuis GitHub
  if ! curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /usr/local/bin/yq; then
    echo "[ERREUR] Échec du téléchargement du binaire yq."
    exit 1
  fi
  chmod +x /usr/local/bin/yq

  # Vérifier l'installation
  if ! command -v yq >/dev/null 2>&1; then
    echo "[ERREUR] Échec de l'installation de yq."
    exit 1
  fi
  echo "[SUCCÈS] yq installé avec succès."
}

# Valider les arguments
if [ $# -lt 2 ]; then
  usage
fi

NOM_APP="$1"
CHEMIN_REPO_GIT="$2"
NOM_BRANCHE="${3:-main}"

# Valider le chemin du dépôt Git
if [[ ! -d "$CHEMIN_REPO_GIT/.git" ]]; then
  echo "[ERREUR] $CHEMIN_REPO_GIT n'est pas un dépôt Git valide."
  exit 1
fi

# Valider l'installation d'Argo CD
if ! command -v argocd >/dev/null 2>&1; then
  echo "[ERREUR] CLI Argo CD non trouvée. Veuillez installer argocd."
  exit 1
fi

# Vérifier et installer yq si nécessaire
if ! command -v yq >/dev/null 2>&1; then
  install_yq
fi

echo "[QUESTION] Choisissez la direction de synchronisation :"
echo "1) Synchroniser Argo CD (cluster) → Git (sauvegarder les changements manuels dans Git)"
echo "2) Synchroniser Git → Argo CD (appliquer l'état Git sur le cluster)"
read -p "Votre choix (1 ou 2) : " CHOIX_SYNC

if [[ "$CHOIX_SYNC" != "1" && "$CHOIX_SYNC" != "2" ]]; then
  echo "[ERREUR] Choix invalide. Doit être 1 ou 2."
  exit 1
fi

if [[ "$CHOIX_SYNC" == "1" ]]; then
  echo "[INFO] Synchronisation Argo CD → Git en cours..."

  # Récupérer les manifestes
  if ! MANIFEST_LIVE=$(argocd app manifests "$NOM_APP" --source=live 2>&1); then
    echo "[ERREUR] Échec de la récupération des manifestes live pour $NOM_APP : $MANIFEST_LIVE"
    exit 1
  fi
  if ! MANIFEST_GIT=$(argocd app manifests "$NOM_APP" --source=git 2>&1); then
    echo "[ERREUR] Échec de la récupération des manifestes Git pour $NOM_APP : $MANIFEST_GIT"
    exit 1
  fi

  # Sauvegarder le manifeste live dans un fichier temporaire
  FICHIER_TEMP=$(mktemp)
  echo "$MANIFEST_LIVE" > "$FICHIER_TEMP"

  # Filtrer les champs gérés par Kubernetes
  FICHIER_TEMP_FILTERED=$(mktemp)
  yq eval 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.managedFields, .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' \
    "$FICHIER_TEMP" > "$FICHIER_TEMP_FILTERED"

  # Comparer le manifeste live filtré avec le manifeste Git
  if diff -u <(echo "$MANIFEST_GIT") <(cat "$FICHIER_TEMP_FILTERED") > /dev/null; then
    echo "[INFO] Aucune différence détectée. Git et le cluster sont synchronisés."
    exit 0
  fi

  # Opérations Git
  cd "$CHEMIN_REPO_GIT" || {
    echo "[ERREUR] Échec du changement de répertoire vers $CHEMIN_REPO_GIT"
    exit 1
  }

  # Vérifier que la branche existe
  if ! git rev-parse --verify "$NOM_BRANCHE" >/dev/null 2>&1; then
    echo "[ERREUR] La branche $NOM_BRANCHE n'existe pas."
    exit 1
  fi

  git checkout "$NOM_BRANCHE" || {
    echo "[ERREUR] Échec du checkout de la branche $NOM_BRANCHE"
    exit 1
  }
  git pull origin "$NOM_BRANCHE" || {
    echo "[ERREUR] Échec du pull de la branche $NOM_BRANCHE"
    exit 1
  }

  # Mettre à jour le manifeste
  CHEMIN_MANIFEST_APP="./manifests/base/${NOM_APP}.yaml"
  mkdir -p "$(dirname "$CHEMIN_MANIFEST_APP")"
  cp "$FICHIER_TEMP_FILTERED" "$CHEMIN_MANIFEST_APP" || {
    echo "[ERREUR] Échec de la copie du manifeste vers $CHEMIN_MANIFEST_APP"
    exit 1
  }

  # Commit et push Git
  git add "$CHEMIN_MANIFEST_APP"
  if ! git commit -m "[ArgoCD] Mise à jour $NOM_APP pour correspondre à l'état du cluster"; then
    echo "[ERREUR] Échec du commit des changements"
    exit 1
  fi
  if ! git push origin "$NOM_BRANCHE"; then
    echo "[ERREUR] Échec du push vers $NOM_BRANCHE"
    exit 1
  }

  echo "[SUCCÈS] Git mises à jour avec l'état du cluster."

elif [[ "$CHOIX_SYNC" == "2" ]]; then
  echo "[INFO] Synchronisation Git → Argo CD en cours..."
  read -p "Forcer la synchronisation (écraser les changements manuels) ? (o/n) : " FORCER_SYNC

  if [[ "$FORCER_SYNC" == "o" ]]; then
    echo "[ATTENTION] Synchronisation forcée (--force). Les changements manuels seront écrasés !"
    if ! argocd app sync "$NOM_APP" --force; then
      echo "[ERREUR] Échec de la synchronisation de $NOM_APP avec --force"
      exit 1
    fi
  else
    echo "[INFO] Synchronisation normale (sans --force)."
    if ! argocd app sync "$NOM_APP"; then
      echo "[ERREUR] Échec de la synchronisation de $NOM_APP"
      exit 1
    fi
  fi

  echo "[SUCCÈS] Argo CD synchronisé avec l'état Git."
fi