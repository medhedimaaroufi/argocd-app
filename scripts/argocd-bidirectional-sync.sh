

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage : $0 <nom_app> <chemin_repo_git> [nom_branche]"
  exit 1
fi

NOM_APP="$1"
CHEMIN_REPO_GIT="$2"
NOM_BRANCHE="${3:-master}"

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

  if diff -u <(echo "$MANIFEST_GIT") <(echo "$MANIFEST_LIVE") > /dev/null; then
    echo "[INFO] Aucune différence détectée. Git et le cluster sont synchronisés."
    exit 0
  fi

  FICHIER_TEMP=$(mktemp)
  echo "$MANIFEST_LIVE" > "$FICHIER_TEMP"

  cd "$CHEMIN_REPO_GIT" || exit 1
  git checkout "$NOM_BRANCHE"
  git pull origin "$NOM_BRANCHE"

  CHEMIN_MANIFEST_APP="./manifests/base/${NOM_APP}.yaml"
  cp "$FICHIER_TEMP" "$CHEMIN_MANIFEST_APP"

  git add "$CHEMIN_MANIFEST_APP"
  git commit -m "[ArgoCD] Mise à jour $NOM_APP pour correspondre à l'état du cluster"
  git push origin "$NOM_BRANCHE"

  echo "[SUCCÈS] Git mis à jour avec l'état du cluster."
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