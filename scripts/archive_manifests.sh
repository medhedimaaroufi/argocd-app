# Génère un timestamp au format YYYYMMDD_HHMMSS pour nommer l'archive de façon unique
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Définit le nom de l'archive 
ARCHIVE_NAME="manifests_$TIMESTAMP.tar.gz"

# Définit le dossier de destination pour l'archive 
ROLLBACK_DIR="../rollback"

# Crée le dossier rollback s'il n'existe pas déjà
mkdir -p "$ROLLBACK_DIR"

# Archive et compresse le dossier 'manifests/' 
tar -czf "$ROLLBACK_DIR/$ARCHIVE_NAME" -C .. manifests/

echo "Manifests archived as $ROLLBACK_DIR/$ARCHIVE_NAME"