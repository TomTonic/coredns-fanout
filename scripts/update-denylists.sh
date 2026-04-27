#!/bin/sh
set -eu

SOURCES_FILE="${SOURCES_FILE:-/etc/coredns/denylist.d/sources.txt}"
TARGET_DIR="${TARGET_DIR:-/etc/coredns/denylist.d}"
DOWNLOAD_INTERVAL_SECONDS="${DOWNLOAD_INTERVAL_SECONDS:-21600}"
TMP_DIR="${TARGET_DIR}/.tmp"
LOCK_DIR="${TARGET_DIR}/.update.lock"

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

acquire_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    return 0
  fi

  echo "[filterlist-updater] another updater instance is already running" >&2
  exit 1
}

cleanup() {
  rm -f "${TMP_DIR}"/*.tmp 2>/dev/null || true
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

acquire_lock

sanitize_name() {
  # Keep filenames predictable and safe for bind-mounted host filesystems.
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
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

    fields=$(printf '%s\n' "${line}" | awk '{ print NF }')

    if [ "${fields}" -lt 1 ] || [ "${fields}" -gt 2 ]; then
      echo "[filterlist-updater] skipping invalid source line: ${line}" >&2
      continue
    fi

    if [ "${fields}" -eq 1 ]; then
      url="${line}"
      filename=$(basename "${url%%\?*}")
    else
      filename=$(printf '%s\n' "${line}" | awk '{ print $1 }')
      url=$(printf '%s\n' "${line}" | awk '{ print $2 }')
    fi

    case "${url}" in
      http://*|https://*)
        ;;
      *)
        echo "[filterlist-updater] skipping source with unsupported URL scheme: ${url}" >&2
        continue
        ;;
    esac

    if [ -z "${filename}" ] || [ "${filename}" = "/" ] || [ "${filename}" = "." ]; then
      filename="list-${downloaded}.txt"
    fi

    safe_name=$(sanitize_name "${filename}")

    if [ -z "${safe_name}" ] || [ "${safe_name}" = "." ] || [ "${safe_name}" = ".." ]; then
      filename="list-${downloaded}.txt"
      safe_name="${filename}"
    fi

    tmp_file="${TMP_DIR}/${safe_name}.tmp"
    target_file="${TARGET_DIR}/${safe_name}"

    echo "[filterlist-updater] downloading ${url} -> ${safe_name}"
    if ! curl --fail --show-error --silent --location --retry 3 --connect-timeout 15 \
      --max-time 120 "${url}" -o "${tmp_file}"; then
      echo "[filterlist-updater] download failed for ${url}" >&2
      rm -f "${tmp_file}" 2>/dev/null || true
      continue
    fi

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
