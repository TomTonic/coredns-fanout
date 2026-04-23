#!/bin/sh
set -eu

SOURCES_FILE="${SOURCES_FILE:-/etc/coredns/denylist.d/sources.txt}"
TARGET_DIR="${TARGET_DIR:-/etc/coredns/denylist.d}"
DOWNLOAD_INTERVAL_SECONDS="${DOWNLOAD_INTERVAL_SECONDS:-21600}"
TMP_DIR="${TARGET_DIR}/.tmp"

if [ ! -f "${SOURCES_FILE}" ]; then
  echo "[filterlist-updater] sources file not found: ${SOURCES_FILE}" >&2
  exit 1
fi

case "${DOWNLOAD_INTERVAL_SECONDS}" in
  ''|*[!0-9]*)
    echo "[filterlist-updater] DOWNLOAD_INTERVAL_SECONDS must be a non-negative integer" >&2
    exit 1
    ;;
esac

mkdir -p "${TARGET_DIR}" "${TMP_DIR}"

sanitize_name() {
  # Keep filenames predictable and safe for bind-mounted host filesystems.
  printf '%s' "$1" | sed 's#[/[:space:]]#_#g'
}

download_once() {
  downloaded=0

  while IFS= read -r raw || [ -n "${raw}" ]; do
    line=$(printf '%s' "${raw}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    if [ -z "${line}" ]; then
      continue
    fi

    case "${line}" in
      \#*)
        continue
        ;;
    esac

    set -- ${line}

    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
      echo "[filterlist-updater] skipping invalid source line: ${line}" >&2
      continue
    fi

    if [ "$#" -eq 1 ]; then
      url="$1"
      filename=$(basename "${url%%\?*}")
    else
      filename="$1"
      url="$2"
    fi

    if [ -z "${filename}" ] || [ "${filename}" = "/" ] || [ "${filename}" = "." ]; then
      filename="list-${downloaded}.txt"
    fi

    safe_name=$(sanitize_name "${filename}")
    tmp_file="${TMP_DIR}/${safe_name}.tmp"
    target_file="${TARGET_DIR}/${safe_name}"

    echo "[filterlist-updater] downloading ${url} -> ${safe_name}"
    curl --fail --show-error --silent --location --retry 3 --connect-timeout 15 \
      --max-time 120 "${url}" -o "${tmp_file}"
    mv "${tmp_file}" "${target_file}"

    downloaded=$((downloaded + 1))
  done < "${SOURCES_FILE}"

  if [ "${downloaded}" -eq 0 ]; then
    echo "[filterlist-updater] no enabled sources found in ${SOURCES_FILE}" >&2
  else
    echo "[filterlist-updater] updated ${downloaded} list(s)"
  fi
}

download_once

if [ "${DOWNLOAD_INTERVAL_SECONDS}" -eq 0 ]; then
  echo "[filterlist-updater] DOWNLOAD_INTERVAL_SECONDS=0, running once and exiting"
  exit 0
fi

while :; do
  sleep "${DOWNLOAD_INTERVAL_SECONDS}"
  download_once
done
