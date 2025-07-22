#!/bin/bash
set -euo pipefail

# Function to filter out Kubernetes-managed fields
filter_managed_fields() {
  local manifest="$1"
  echo "$manifest" | yq eval 'del(.metadata.managedFields)' - | \
    yq eval 'del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' - | \
    yq eval 'del(.metadata.creationTimestamp)' - | \
    yq eval 'del(.metadata.generation)' - | \
    yq eval 'del(.metadata.resourceVersion)' - | \
    yq eval 'del(.metadata.selfLink)' - | \
    yq eval 'del(.metadata.uid)' - | \
    yq eval 'del(.status)' - | \
    yq eval 'del(.metadata.annotations."deployment.kubernetes.io/revision")' - | \
    yq eval 'del(.spec.template.metadata.annotations."kubectl.kubernetes.io/restartedAt")' -
}

archive_manifests(){
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  ARCHIVE_NAME="manifests_$TIMESTAMP.tar.gz"
  ROLLBACK_DIR="../rollback"

  mkdir -p "$ROLLBACK_DIR"

  tar -czf "$ROLLBACK_DIR/$ARCHIVE_NAME" -C .. manifests/

  echo "Manifests archived as $ROLLBACK_DIR/$ARCHIVE_NAME"
}

if [ $# -lt 2 ]; then
  echo "Usage : $0 <nom_app> <chemin_repo_git> [nom_branche]"
  exit 1
fi

NOM_APP="$1"
CHEMIN_REPO_GIT="$2"
NOM_BRANCHE="${3:-master}"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "[ERREUR] yq doit être installé pour exécuter ce script."
  echo "Installez-le avec: brew install yq ou sudo apt-get install yq"
  exit 1
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

  MANIFEST_LIVE=$(argocd app manifests "$NOM_APP" --source=live)
  MANIFEST_GIT=$(argocd app manifests "$NOM_APP" --source=git)
  
  # Filter managed fields from live manifest for comparison
  FILTERED_LIVE=$(filter_managed_fields "$MANIFEST_LIVE")
  FILTERED_GIT=$(filter_managed_fields "$MANIFEST_GIT")

  if diff -u <(echo "$FILTERED_GIT") <(echo "$FILTERED_LIVE") > /dev/null; then
    echo "[INFO] Aucune différence détectée. Git et le cluster sont synchronisés."
    exit 0
  fi

  FICHIER_TEMP=$(mktemp)
  # Store filtered manifest in temp file
  echo "$FILTERED_LIVE" > "$FICHIER_TEMP"

  cd "$CHEMIN_REPO_GIT" || exit 1
  git checkout "$NOM_BRANCHE"
  git pull origin "$NOM_BRANCHE"

  archive_manifests
  rm -r ./manifests/base
  mkdir -p ./manifests/base

  CHEMIN_MANIFEST_APP="./manifests/base/${NOM_APP}.yaml"
  cp "$FICHIER_TEMP" "$CHEMIN_MANIFEST_APP"

  git add "$CHEMIN_MANIFEST_APP"
  git commit -m "[ArgoCD] Mise à jour $NOM_APP pour correspondre à l'état du cluster"
  git push origin "$NOM_BRANCHE"

  echo "[SUCCÈS] Git mis à jour avec l'état du cluster (champs managés filtrés)."
  rm "$FICHIER_TEMP"

elif [[ "$CHOIX_SYNC" == "2" ]]; then
  echo "[INFO] Synchronisation Git → Argo CD en cours..."
  read -p "Forcer la synchronisation (écraser les changements manuels) ? (o/n) : " FORCER_SYNC

  if [[ "$FORCER_SYNC" == "o" ]]; then
    echo "[ATTENTION] Synchronisation forcée (--force). Les changements manuels seront écrasés !"
    argocd app sync "$NOM_APP" --force
  else
    echo "[INFO] Synchronisation normale (sans --force)."
    argocd app sync "$NOM_APP"
  fi

  echo "[SUCCÈS] Argo CD synchronisé avec l'état Git."
fi