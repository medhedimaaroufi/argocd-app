# REPO-CONFIG_INITIAL-SCRIPT_V1_16-07-2025

## Introduction
Ce dépôt contient des scripts et des manifests de configuration pour la gestion des applications avec Argo CD. Il a été conçu pour faciliter la synchronisation bidirectionnelle entre Git et le cluster, ainsi que l'archivage des manifests pour des opérations de rollback.

## Fonctionnalités
- **Synchronisation bidirectionnelle** : Permet de synchroniser Argo CD (cluster) vers Git ou inversement via le script `argocd-bidirectional-sync.sh`.
- **Archivage des manifests** : Crée des archives temporelles des manifests avec `archive_manifests.sh` pour des sauvegardes ou restaurations.
- **Structure organisée** : Inclut des dossiers pour les manifests, les rollbacks et les scripts.

## Utilisation
1. Assurez-vous que l'interface CLI d'Argo CD est installée et configurée.
2. Exécutez `argocd-bidirectional-sync.sh <nom_app> <chemin_repo_git> [nom_branche]` pour synchroniser les configurations.
3. Utilisez `archive_manifests.sh` pour archiver les manifests dans le dossier `rollback`.

## Remarques
- Les scripts supposent une structure de répertoire et une configuration Git spécifiques.
- Testez les scripts dans un environnement non productif avant utilisation.