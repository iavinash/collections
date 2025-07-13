#!/bin/bash

set -e

# === INPUTS ===
ENVIRONMENT=$1
APP_NAME=$2
VERSION=$3
ACTION=$4

CONFIG_DIR="./config"
SERVER_LIST="$CONFIG_DIR/servers.txt"
DEPLOY_MAP="$CONFIG_DIR/deploy_map.conf"

# === VALIDATION ===
if [[ -z "$ENVIRONMENT" || -z "$APP_NAME" || -z "$VERSION" || -z "$ACTION" ]]; then
  echo "----------------------------------------------------"
  echo " AM-DEPLOYER USAGE:"
  echo " ./deploy.sh <environment> <app_name> <version> <action>"
  echo " Example: ./deploy.sh prod bookings 22.1.33 start"
  echo "----------------------------------------------------"
  exit 1
fi

if [[ ! -f "$SERVER_LIST" || ! -f "$DEPLOY_MAP" ]]; then
  echo "[ERROR] Missing config files in $CONFIG_DIR"
  exit 1
fi

# === GET ALL VARIANTS OF THE APP ===
mapfile -t VARIANTS < <(grep "^$APP_NAME\." "$DEPLOY_MAP")

if [[ ${#VARIANTS[@]} -eq 0 ]]; then
  echo "[ERROR] No variants found for app $APP_NAME in deploy_map.conf"
  exit 1
fi

# === DEPLOY TO EACH SERVER ===
while IFS= read -r SERVER; do
  echo "======================================================"
  echo ">>> DEPLOYING $APP_NAME TO SERVER: $SERVER"
  echo "======================================================"

  for VARIANT_LINE in "${VARIANTS[@]}"; do
    IFS='|' read -r VARIANT_PATH DEPLOY_DIR INSTANCES <<<"$(echo "$VARIANT_LINE" | sed "s/^$APP_NAME\.//")"

    echo "------------------------------------------------------"
    echo ">>> Processing Variant: $VARIANT_PATH"
    echo "------------------------------------------------------"

    ssh "$SERVER" bash -c "' 
      set -e
      echo "[INFO] Entering directory: $DEPLOY_DIR"
      cd $DEPLOY_DIR

      echo "[INFO] Running release.sh $VERSION"
      ./release.sh $VERSION
      wait

      cd current/build
      echo "[INFO] In build directory: $(pwd)"

      if [[ -z "$INSTANCES" ]]; then
        echo "[INFO] Single-instance deployment for $VARIANT_PATH"
        ./run.sh $ACTION
      elif [[ "$INSTANCES" == *-* ]]; then
        IFS="-" read -r START END <<< "$INSTANCES"
        for i in $(seq $START $END); do
          echo "[INFO] Running instance $i for $VARIANT_PATH"
          ./run.sh $ACTION $i
        done
      else
        echo "[INFO] Running single instance $INSTANCES"
        ./run.sh $ACTION $INSTANCES
      fi
    '"

    echo "[SUCCESS] Finished $VARIANT_PATH on $SERVER"
  done

  echo "[DONE] All variants of $APP_NAME deployed on $SERVER"
  echo
done < "$SERVER_LIST"

echo "======================================================"
echo ">>> AM-DEPLOYER COMPLETED SUCCESSFULLY" 
echo ">>> DEPLOYMENT OF $APP_NAME ($VERSION) TO ALL SERVERS COMPLETE"
echo "======================================================"
