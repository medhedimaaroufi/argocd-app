#!/bin/bash
set -euo pipefail

# Fonction pour filtrer les champs gérés automatiquement par Kubernetes
filter_managed_fields() {
  local manifest="$1"
  # Supprime les champs inutiles pour la comparaison/sauvegarde dans Git
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

# Fonction pour archiver les manifests actuels avant modification (sauvegarde)
archive_manifests(){
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S") # Génère un timestamp unique
  ARCHIVE_NAME="manifests_$TIMESTAMP.tar.gz" # Nom de l'archive
  ROLLBACK_DIR="./rollback" # Dossier de sauvegarde

  mkdir -p "$ROLLBACK_DIR" # Crée le dossier s'il n'existe pas

  # Archive et compresse le dossier 'manifests/'
  tar -czf "$ROLLBACK_DIR/$ARCHIVE_NAME" -C . manifests/

  echo "Manifests archived as $ROLLBACK_DIR/$ARCHIVE_NAME"
}

# Vérifie que le script reçoit au moins 2 arguments (nom de l'app et chemin du repo Git)
if [ $# -lt 2 ]; then
  echo "Usage : $0 <nom_app> <chemin_repo_git> [nom_branche]"
  exit 1
fi

NOM_APP="$1" # Nom de l'application ArgoCD
CHEMIN_REPO_GIT="$2" # Chemin local du repo Git
NOM_BRANCHE="${3:-master}" # Nom de la branche (par défaut master)

# Vérifie que yq est installé (utilisé pour manipuler les fichiers YAML)
if ! command -v yq &> /dev/null; then
  echo "[ERREUR] yq doit être installé pour exécuter ce script."
  echo "Installez-le avec: sudo apt-get install yq"
  exit 1
fi

# Demande à l'utilisateur la direction de synchronisation souhaitée
echo "[QUESTION] Choisissez la direction de synchronisation :"
echo "1) Synchroniser Argo CD (cluster) → Git (sauvegarder les changements manuels dans Git)"
echo "2) Synchroniser Git → Argo CD (appliquer l'état Git sur le cluster)"
read -p "Votre choix (1 ou 2) : " CHOIX_SYNC

# Vérifie que le choix est valide
if [[ "$CHOIX_SYNC" != "1" && "$CHOIX_SYNC" != "2" ]]; then
  echo "[ERREUR] Choix invalide. Doit être 1 ou 2."
  exit 1
fi

# Cas 1 : Synchronisation du cluster vers Git (sauvegarde des changements manuels)
if [[ "$CHOIX_SYNC" == "1" ]]; then
  echo "[INFO] Synchronisation Argo CD → Git en cours..."

  # Récupère les manifests actuels du cluster et de Git
  MANIFEST_LIVE=$(argocd app manifests "$NOM_APP" --source=live)
  MANIFEST_GIT=$(argocd app manifests "$NOM_APP" --source=git)
  
  # Filtre les champs gérés automatiquement
  FILTERED_LIVE=$(filter_managed_fields "$MANIFEST_LIVE")
  FILTERED_GIT=$(filter_managed_fields "$MANIFEST_GIT")

  # Compare les manifests filtrés, quitte si aucune différence
  if diff -u <(echo "$FILTERED_GIT") <(echo "$FILTERED_LIVE") > /dev/null; then
    echo "[INFO] Aucune différence détectée. Git et le cluster sont synchronisés."
    exit 0
  fi

  FICHIER_TEMP=$(mktemp) # Crée un fichier temporaire pour stocker le manifest filtré
  echo "$FILTERED_LIVE" > "$FICHIER_TEMP"

  cd "$CHEMIN_REPO_GIT" || exit 1 # Va dans le repo Git
  git checkout "$NOM_BRANCHE"
  git pull origin "$NOM_BRANCHE"

  archive_manifests # Archive les manifests actuels avant modification
  rm -r ./manifests/base # Supprime l'ancien dossier de manifests
  mkdir -p ./manifests/base # Recrée le dossier

  CHEMIN_MANIFEST_APP="./manifests/base/${NOM_APP}.yaml" # Chemin du manifest à mettre à jour
  cp "$FICHIER_TEMP" "$CHEMIN_MANIFEST_APP" # Copie le manifest filtré

  git add -A
  git commit -m "[ArgoCD] Mise à jour $NOM_APP pour correspondre à l'état du cluster"
  git push origin "$NOM_BRANCHE"

  argocd app sync "$NOM_APP" # Synchronise l'application ArgoCD
  echo "[SUCCÈS] Git mis à jour avec l'état du cluster (champs managés filtrés)."
  rm "$FICHIER_TEMP"

# Cas 2 : Synchronisation de Git vers le cluster (appliquer l'état Git)
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