#!/bin/bash

set -e

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


cat <<'EOF'
 ============================================================================================================== 
    ,---.   ,--.   ,--.         ,------.   ,------. ,------.  ,--.     ,-----.  ,--.   ,--. ,------. ,------.  
   /  O  \  |   '.'   | ,-----. |  .-.  \  |  .---' |  .--. ' |  |    '  .-.  '  \  '.'  /  |  .---' |  .--. ' 
  |  .-.  | |  |'.'|  | '-----' |  |  \  : |  `--,  |  '--' | |  |    |  | |  |   '.    /   |  `--,  |  '--'.' 
  |  | |  | |  |   |  |         |  '--'  / |  `---. |  | --'  |  '--. '  '-'  '     |  |    |  `---. |  |\  \  
  `--' `--' `--'   `--'         `-------'  `------' `--'      `-----'  `-----'      `--'    `------' `--' '--' 

                            SCRIPTED BY: Avinash Mishra (AM - Deployer)                                      
 ===============================================================================================================
EOF


# === INPUTS ===
ENVIRONMENT=$1
APP_NAME=$2
VERSION=$3
ACTION=$4

if [[ "$VERSION" =~ ^(start|stop|bounce)$ ]]; then
  ACTION="$VERSION"
  VERSION=""
fi

CONFIG_DIR="./config"
SERVER_LIST="$CONFIG_DIR/servers.txt"
DEPLOY_MAP="$CONFIG_DIR/deploy_map.conf"

# === BASIC VALIDATION ===
if [[ -z "$ENVIRONMENT" || -z "$APP_NAME" || -z "$ACTION" ]]; then
  echo -e "${RED}----------------------------------------------------"
  echo " AM-DEPLOYER USAGE:"
  echo " ./deploy.sh <environment> <app_name> [version] <action>"
  echo " Example: ./deploy.sh uat bookings 22.1.33 start"
  echo " Example: ./deploy.sh uat bookings bounce"
  echo -e "----------------------------------------------------${NC}"
  exit 1
fi

if [[ ! -f "$SERVER_LIST" || ! -f "$DEPLOY_MAP" ]]; then
  echo -e "${RED}[ERROR] Missing config files in $CONFIG_DIR${NC}"
  exit 1
fi

# === Ask for variant when stopping bookings or rate ===
SELECTED_STACKS=()
if [[ "$ACTION" == "stop" || ( "$ACTION" == "bounce" && -z "$VERSION" ) ]]; then
  if [[ "$APP_NAME" == "bookings" || "$APP_NAME" == "rate" ]]; then
    echo -e "\n${YELLOW}Choose the stack(s) you want to $ACTION (comma separated):${NC}"
    echo " 1) inst"
    echo " 2) retail"
    echo " 3) house"
    read -p "Enter choice (e.g., inst,retail): " STACK_INPUT
    IFS=',' read -r -a STACKS <<< "$STACK_INPUT"

    for s in "${STACKS[@]}"; do
      if [[ "$s" =~ ^(inst|retail|house)$ ]]; then
        SELECTED_STACKS+=("$s")
      else
        echo -e "${RED}[WARNING] Ignoring invalid stack: $s${NC}"
      fi
    done

    if [[ ${#SELECTED_STACKS[@]} -eq 0 ]]; then
      echo -e "${RED}[ERROR] No valid stack selected. Exiting.${NC}"
      exit 1
    fi
  fi
fi

# === GET VARIANTS ===
VARIANTS=()
while IFS= read -r line; do
  VARIANTS+=("$line")
done <<< "$(grep "^$APP_NAME\." "$DEPLOY_MAP")"

if [[ ${#VARIANTS[@]} -eq 0 ]]; then
  echo -e "${RED}[ERROR] No variants found for app $APP_NAME in deploy_map.conf${NC}"
  exit 1
fi

# === DEPLOY TO EACH SERVER ===
while IFS= read -r SERVER; do
  echo -e "${YELLOW}======================================================"
  echo ">>> DEPLOYING $APP_NAME TO SERVER: $SERVER"
  echo -e "======================================================${NC}"

  VARIANTS_PROCESSED=0

  for VARIANT_LINE in "${VARIANTS[@]}"; do
    IFS='|' read -r VARIANT_PATH DEPLOY_DIR INSTANCES <<< "$(echo "$VARIANT_LINE" | sed "s/^$APP_NAME\.//")"

    # If user selected specific stacks (only for stop or bounce without version)
    if [[ ${#SELECTED_STACKS[@]} -gt 0 ]]; then
      MATCHED=false
      for stack in "${SELECTED_STACKS[@]}"; do
        if [[ "$VARIANT_PATH" == "$stack" ]]; then
          MATCHED=true
          break
        fi
      done
      [[ "$MATCHED" == false ]] && continue
    fi

    VARIANTS_PROCESSED=$((VARIANTS_PROCESSED + 1))

    echo -e "${GREEN}------------------------------------------------------"
    echo ">>> Processing Variant: $VARIANT_PATH"
    echo -e "------------------------------------------------------${NC}"

    ssh "$SERVER" bash -c "'
      set -e
      echo \"[INFO] Entering directory: $DEPLOY_DIR\"
      cd $DEPLOY_DIR

      if [[ \"$ACTION\" == \"start\" || ( \"$ACTION\" == \"bounce\" && -n \"$VERSION\" ) ]]; then
        echo \"[INFO] Running release.sh $VERSION\"
        ./release.sh $VERSION
        wait
      fi

      cd current/build
      echo \"[INFO] In build directory: \\$(pwd)\"

      if [[ -z \"$INSTANCES\" ]]; then
        echo \"[INFO] Single-instance deployment for $VARIANT_PATH\"
        ./run.sh $ACTION
      elif [[ \"$INSTANCES\" == *-* ]]; then
        IFS=\"-\" read -r START END <<< \"$INSTANCES\"
        for i in \\$(seq $START $END); do
          echo \"[INFO] Running instance \\$i for $VARIANT_PATH\"
          ./run.sh $ACTION \\$i
        done
      else
        echo \"[INFO] Running single instance $INSTANCES\"
        ./run.sh $ACTION $INSTANCES
      fi
    '"

    echo -e "${GREEN}[SUCCESS] Finished $VARIANT_PATH on $SERVER${NC}"
  done

  if [[ $VARIANTS_PROCESSED -eq 0 ]]; then
    echo -e "${YELLOW}[SKIPPED] No matching variants processed for $APP_NAME on $SERVER${NC}"
  else
    echo -e "${GREEN}[DONE] All applicable variants of $APP_NAME deployed on $SERVER${NC}"
  fi

  echo

done < "$SERVER_LIST"

echo -e "${GREEN}======================================================"
echo ">>> AM-DEPLOYER COMPLETED SUCCESSFULLY"
echo ">>> DEPLOYMENT OF $APP_NAME (${VERSION:-<no-version>}) TO ALL SERVERS COMPLETE"
echo -e "======================================================${NC}"
