# Scripts de Sync et Rollback ArgoCD

Scripts et configurations pour la gestion des déploiements ArgoCD et rollback

## Structure du Projet

```
.
├── manifests/
│   └── base/
│       └── myapp-argo-application.yaml  # Définition de l'application
├── rollback/                           # Archives des états précédents
├── scripts/
│   ├── archive_manifests.sh            # Sauvegarde des manifests
│   └── argo-bidirectional-sync.sh      # Synchronisation ArgoCD <--> Git
├── .gitignore
├── application.yaml                    # Configuration principale d'ArgoCD
└── README.md
```

## Prérequis

### Outils obligatoires

1. **Git** - Système de contrôle de version  
   [Documentation d'installation](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

2. **ArgoCD CLI** - Outil de ligne de commande pour ArgoCD  
   [Guide d'installation](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

3. **yq** - Processeur YAML pour ligne de commande  
   [Instructions d'installation](https://github.com/mikefarah/yq#install)

4. **Cluster Kubernetes avec ArgoCD**  
   - [Installer ArgoCD](https://argo-cd.readthedocs.io/en/stable/getting_started/)

### Vérification des installations

```bash
git --version
argocd version
yq --version
kubectl version --short
```

## Utilisation

### Preparation initiale
```bash
# 1. Etablir la connexion ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443 &  # Lancer en arriere-plan
argocd login localhost:8080 --username admin --password <password> --insecure
```
- Pour le mot de passe ArgoCD :
    ```bash
    kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    ```
### Script d'archivage (archive_manifests.sh)
```bash
cd scripts/
./archive_manifests.sh

# Resultat attendu :
# - Cree une archive horodatee dans ../rollback/
# - Format : manifests_YYYYMMDD_HHMMSS.tar.gz
# - Contenu : dossier manifests/ complet
```

### Script de synchronisation (argocd-bidirectional-sync.sh)
```bash
# Syntaxe :
./argocd-bidirectional-sync.sh <APP_NAME> <GIT_REPO_PATH> [BRANCH]

# Exemple complet :
./argocd-bidirectional-sync.sh my-app .. main
```

#### Flux d'execution :
1. Le script demande la direction de synchronisation :
   ```
   1) Cluster -> Git (sauvegarde l'etat actuel)
   2) Git -> Cluster (deploie les changements)
   ```

2. Pour Cluster -> Git :
   - Filtre automatiquement les champs Kubernetes
   - Crée une archive de rollback
   - Met à jour le dépôt Git

3. Pour Git -> Cluster :
   - Propose une synchronisation forcée (--force)
   - Applique la configuration Git sur le cluster

## Notes Techniques

- Les archives contiennent une copie complète du dossier manifests/
- Format : .tar.gz compressé avec horodatage
- Les scripts filtrent automatiquement :
  - Champs managés par Kubernetes
  - Métadonnées temporaires
  - Champs de status