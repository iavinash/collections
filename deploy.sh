#!/bin/bash

set -e

# === INPUTS ===
ENVIRONMENT=$1
APP_NAME=$2
VERSION=$3

# === VALIDATION ===
if [[ -z "$ENVIRONMENT" || -z "$APP_NAME" || -z "$VERSION" ]]; then
  echo "Usage: $0 <environment> <app_name> <version>"
  echo "Example: $0 prod booking 22.1.33"
  exit 1
fi

CONFIG_DIR="./config"
SERVER_LIST="$CONFIG_DIR/servers.txt"
APP_PATHS_FILE="$CONFIG_DIR/app_paths.conf"

if [[ ! -f "$SERVER_LIST" || ! -f "$APP_PATHS_FILE" ]]; then
  echo "Missing config files in $CONFIG_DIR"
  exit 1
fi

# === RESOLVE APPLICATION DIRECTORY ===
APP_PATH=$(grep "^$APP_NAME=" "$APP_PATHS_FILE" | cut -d'=' -f2)

if [[ -z "$APP_PATH" ]]; then
  echo "Invalid app_name: $APP_NAME. Must be one of booking, rate, idsystem."
  exit 1
fi

# === DEPLOY LOOP ===
while IFS= read -r SERVER; do
  echo "========== Deploying to $SERVER =========="
  
  ssh "$SERVER" bash -c "'
    set -e
    echo \"[INFO] Switching to app directory: $APP_PATH\"
    cd $APP_PATH

    echo \"[INFO] Running release.sh with version: $VERSION\"
    ./release.sh $VERSION

    echo \"[INFO] Waiting for artefact to be ready...\"
    wait

    cd current/build

    for i in 1 2; do
      echo \"[INFO] Starting instance \$i for $APP_NAME on $SERVER\"
      ./run.sh start \$i
    done
  '"
  
  echo "✅ Deployment completed for $SERVER"
  echo
done < "$SERVER_LIST"

echo "🎉 All deployments finished successfully!"
