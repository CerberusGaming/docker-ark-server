#!/usr/bin/env bash

set -e

[[ "${DEBUG,,}" = "false" ]] || [[ "${DEBUG,,}" = "0" ]] || [[ -z "${DEBUG}" ]] || set -x

function ensure_rights() {
  TARGET="${ARK_SERVER_VOLUME} ${STEAM_HOME}"
  if [[ -n "${1}" ]]; then
    TARGET="${1}"
  fi

  echo "...ensuring rights on ${TARGET}"
  sudo chown -R "${STEAM_USER}":"${STEAM_GROUP}" ${TARGET}
}

function may_update() {
  if [[ "${UPDATE_ON_START}" != "true" ]]; then
    return
  fi

  echo "\$UPDATE_ON_START is 'true'..."

  # auto checks if a update is needed, if yes, then update the server or mods
  # (otherwise it just does nothing)
  ${ARKMANAGER} update --verbose --update-mods --backup --no-autostart
}

function create_missing_dir() {
  for DIRECTORY in ${@}; do
    [[ -n "${DIRECTORY}" ]] || return
    if [[ ! -d "${DIRECTORY}" ]]; then
      mkdir -p "${DIRECTORY}"
      echo "...successfully created ${DIRECTORY}"
      ensure_rights "${DIRECTORY}"
    fi
  done
}

function copy_missing_file() {
  SOURCE="${1}"
  DESTINATION="${2}"

  if [[ ! -f "${DESTINATION}" ]]; then
    cp -a "${SOURCE}" "${DESTINATION}"
    echo "...successfully copied ${SOURCE} to ${DESTINATION}"
  fi

  ensure_rights ${DESTINATION}
}

########################################################################################################################
sudo chown "${STEAM_USER}":"${STEAM_GROUP}" ${ARK_SERVER_VOLUME}


if [[ ! "$(id -u "${STEAM_USER}")" -eq "${STEAM_UID}" ]] || [[ ! "$(id -g "${STEAM_GROUP}")" -eq "${STEAM_GID}" ]]; then
  sudo usermod -o -u "${STEAM_UID}" "${STEAM_USER}"
  sudo groupmod -o -g "${STEAM_GID}" "${STEAM_GROUP}"
fi

echo "_______________________________________"
echo ""
echo "# Ark Server - $(date)"
echo "# UID ${STEAM_UID} - GID ${STEAM_GID}"
echo "# ARGS ${args[*]}"
echo "_______________________________________"

ARKMANAGER="$(command -v arkmanager)"
[[ -x "${ARKMANAGER}" ]] || (
  echo "Arkamanger is missing"
  exit 1
)

cd "${ARK_SERVER_VOLUME}"

echo "Setting up folder and file structure..."
create_missing_dir "${ARK_SERVER_VOLUME}/log" "${ARK_SERVER_VOLUME}/backup" "${ARK_SERVER_VOLUME}/staging"

echo "Setting up Arkmanager..."
# setup arkmanager directories
if [[ ! -d ${ARK_TOOLS_DIR} ]]; then
  sudo mv "/etc/arkmanager" "${ARK_TOOLS_DIR}"
  ensure_rights "${ARK_TOOLS_DIR}"
  rm -f "${ARK_TOOLS_DIR}/arkmanager.cfg" "${ARK_TOOLS_DIR}/instances/main.cfg"
fi

# symlink arkmanager directories
sudo rm -rf "/etc/arkmanager"
sudo ln -s "${ARK_TOOLS_DIR}" "/etc/arkmanager"

# copy from template to server volume
copy_missing_file "${TEMPLATE_DIRECTORY}/arkmanager.cfg" "${ARK_TOOLS_DIR}/arkmanager.cfg"
copy_missing_file "${TEMPLATE_DIRECTORY}/arkmanager-user.cfg" "${ARK_TOOLS_DIR}/instances/main.cfg"

# Install ark
if [[ ! -d ${ARK_SERVER_VOLUME}/server ]] || [[ ! -f ${ARK_SERVER_VOLUME}/server/version.txt ]]; then
  echo "No game files found. Installing..."

  create_missing_dir \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Saved/SavedArks" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Content/Mods" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux"

  touch "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer"
  chmod +x "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer"

  ${ARKMANAGER} install --verbose
else
  may_update
fi

if [[ -n "${GAME_MOD_IDS}" ]]; then
  echo "Installing mods: '${GAME_MOD_IDS}' ..."

  for MOD_ID in ${GAME_MOD_IDS//,/ }; do
    echo "...installing '${MOD_ID}'"

    if [[ -d "${ARK_SERVER_VOLUME}/server/ShooterGame/Content/Mods/${MOD_ID}" ]]; then
      echo "...already installed"
      if [[ "${FORCE_MOD_UPDATE,,}" = "true" ]] || [[ "${FORCE_MOD_UPDATE,,}" = "1" ]]; then
        echo "Forcing install."
      else
        continue
      fi
    fi

    ${ARKMANAGER} installmod "${MOD_ID}" --verbose
    echo "...done"
  done

  ${ARKMANAGER} checkmodupdate
fi

args=("$*")
args=("--arkopt,RCONPort=${RCON_PORT}" "${args[@]}")
args=("--arkopt,Port=${GAME_CLIENT_PORT}" "${args[@]}")
args=("--arkopt,QueryPort=${SERVER_LIST_PORT}" "${args[@]}")
args=('--arkopt,-servergamelog' "${args[@]}")

if [[ "${ENABLE_CROSSPLAY}" == "true" ]]; then
  args=('--arkopt,-crossplay' "${args[@]}")
fi
if [[ "${DISABLE_BATTLEYE}" == "true" ]]; then
  args=('--arkopt,-NoBattlEye' "${args[@]}")
fi
if [[ -n "${CLUSTER_ID}" ]]; then
  args=("--arkopt,-clusterid=${CLUSTER_ID}" '--arkopt,-NoTransferFromFiltering' "${args[@]}")
fi

sudo chown "${STEAM_USER}":"${STEAM_GROUP}" ${ARK_SERVER_VOLUME}/server/ShooterGame/Saved/SavedArks

exec ${ARKMANAGER} run --verbose ${args[@]}
