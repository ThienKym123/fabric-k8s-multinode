#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function logging_init() {
  # Reset the output and debug log files
  printf '' > "${LOG_FILE}" > "${DEBUG_FILE}"

  # Write all output to the control flow log to STDOUT
  tail -f "${LOG_FILE}" &

  # Call the exit handler when we exit
  trap exit_fn EXIT

  # Send stdout and stderr from child programs to the debug log file
  exec 1>>"${DEBUG_FILE}" 2>>"${DEBUG_FILE}"

  # Avoid race between tail and logging
  sleep 0.5
}

function exit_fn() {
  local rc=$?
  set +x

  # Write an error icon to the current logging statement if non-zero exit code
  if [ "$rc" -ne 0 ]; then
    pop_fn "$rc"
  fi

  # Remove the log trailer when the process exits
  pkill -P $$ || true
}

function push_fn() {
  echo -ne "   - $@ ..." >> "${LOG_FILE}"
}

function log() {
  echo -e "$@" >> "${LOG_FILE}"
}

function pop_fn() {
  local res="${1:-0}"  # Default to 0 if no argument provided

  # Ensure res is an integer; if not, treat as error
  if ! [[ "$res" =~ ^[0-9]+$ ]]; then
    echo -ne "\r⚠️\n" >> "${LOG_FILE}"
    echo "ERROR: Invalid return code '$res'" >> "${LOG_FILE}"
    tail -n "${LOG_ERROR_LINES}" "${DEBUG_FILE}" >> "${LOG_FILE}"
    return
  fi

  case "$res" in
    0)
      echo -ne "\r✅\n" >> "${LOG_FILE}"
      ;;
    1)
      echo -ne "\r⚠️\n" >> "${LOG_FILE}"
      tail -n "${LOG_ERROR_LINES}" "${DEBUG_FILE}" >> "${LOG_FILE}"
      ;;
    2|127)
      echo -ne "\r☠️\n" >> "${LOG_FILE}"
      tail -n "${LOG_ERROR_LINES}" "${DEBUG_FILE}" >> "${LOG_FILE}"
      ;;
    *)
      echo -ne "\r\n" >> "${LOG_FILE}"
      tail -n "${LOG_ERROR_LINES}" "${DEBUG_FILE}" >> "${LOG_FILE}"
      ;;
  esac
}

function apply_template() {
  echo "Applying template $1:"
  envsubst < "$1" || { log "ERROR: Failed to substitute variables in $1"; exit 1; }
  envsubst < "$1" | kubectl -n "$2" apply -f - || { log "ERROR: Failed to apply $1"; exit 1; }
}

function export_peer_context() {
  local org="$1"
  local peer="$2"

  export FABRIC_CFG_PATH="${PWD}/config/${org}"
  export CORE_PEER_ADDRESS="${org}-${peer}.${DOMAIN}:${NGINX_HTTPS_PORT}"
  export CORE_PEER_MSPCONFIGPATH="${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp"
  export CORE_PEER_TLS_ROOTCERT_FILE="${TEMP_DIR}/channel-msp/peerOrganizations/${org}/msp/tlscacerts/tlsca-signcert.pem"
}

function absolute_path() {
  local relative_path="$1"
  cd "${relative_path}" && pwd || { log "ERROR: Invalid path $relative_path"; exit 1; }
}