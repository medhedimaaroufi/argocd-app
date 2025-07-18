#!/bin/bash

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="manifests_$TIMESTAMP.tar.gz"
ROLLBACK_DIR="../rollback"

mkdir -p "$ROLLBACK_DIR"

tar -czf "$ROLLBACK_DIR/$ARCHIVE_NAME" -C .. manifests/

echo "Manifests archived as $ROLLBACK_DIR/$ARCHIVE_NAME"