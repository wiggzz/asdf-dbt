#!/usr/bin/env bash

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN_DEFAULT="python3"
FUSION_MANIFEST_DEFAULT_URL="https://dl.fusion.getdbt.com/cli/manifest.json"

log() {
  echo "asdf-dbt: $*" >&2
}

fail() {
  log "$*"
  exit 1
}

get_python_bin() {
  if [[ -n "${ASDF_DBT_PYTHON_BIN:-}" ]]; then
    echo "$ASDF_DBT_PYTHON_BIN"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    echo python3
    return
  fi
  if command -v python >/dev/null 2>&1; then
    echo python
    return
  fi
  fail "python3 is required to install dbt-core"
}

# Determine host triplet key used in manifests (platform-arch)
resolve_fusion_platform_key() {
  local os arch key
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux) os="linux" ;;
    darwin) os="darwin" ;;
    msys*|cygwin*|mingw*) os="windows" ;;
    *) fail "Unsupported OS for dbt fusion: $os" ;;
  esac

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) fail "Unsupported architecture for dbt fusion: $arch" ;;
  esac

  key="${os}-${arch}"
  echo "$key"
}

fusion_manifest_path() {
  if [[ -n "${ASDF_DBT_FUSION_MANIFEST_PATH:-}" ]]; then
    echo "$ASDF_DBT_FUSION_MANIFEST_PATH"
    return
  fi

  local manifest_url="${ASDF_DBT_FUSION_MANIFEST_URL:-}"
  if [[ -n "$manifest_url" ]]; then
    local tmp
    tmp="$(mktemp)"
    if ! curl -fsSL "$manifest_url" -o "$tmp"; then
      rm -f "$tmp"
      fail "Failed to download fusion manifest from $manifest_url"
    fi
    echo "$tmp"
    return
  fi

  ensure_default_fusion_manifest
  echo "$PLUGIN_ROOT/share/fusion-manifest.json"
}

cleanup_temp_manifest() {
  local path="$1"
  if [[ -n "${ASDF_DBT_FUSION_MANIFEST_URL:-}" && -f "$path" ]]; then
    rm -f "$path"
  fi
}

ensure_default_fusion_manifest() {
  local manifest="$PLUGIN_ROOT/share/fusion-manifest.json"
  local python_bin
  python_bin="$(get_python_bin)"

  if [[ -f "$manifest" ]]; then
    if "$python_bin" - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    sys.exit(1)

versions = data.get("versions")
if isinstance(versions, dict) and versions:
    sys.exit(0)

sys.exit(1)
PY
    then
      return
    fi
  fi

  local bootstrap_url="${ASDF_DBT_FUSION_MANIFEST_BOOTSTRAP_URL:-$FUSION_MANIFEST_DEFAULT_URL}"
  if [[ -z "$bootstrap_url" ]]; then
    return
  fi

  local tmp
  tmp="$(mktemp)"
  if curl -fsSL "$bootstrap_url" -o "$tmp"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$tmp" "$manifest"
  else
    rm -f "$tmp"
    log "Failed to download default fusion manifest from $bootstrap_url"
  fi
}

# Extract the python version from the requested version string
# Accepts "core-1.8.3" or "1.8.3" -> returns "1.8.3"
parse_core_version() {
  local raw="$1"
  if [[ "$raw" =~ ^core- ]]; then
    echo "${raw#core-}"
  else
    echo "$raw"
  fi
}

parse_fusion_version() {
  local raw="$1"
  if [[ "$raw" =~ ^fusion- ]]; then
    echo "${raw#fusion-}"
  else
    echo "$raw"
  fi
}

# Ensure install dir has bin symlink for python venv
link_venv_entrypoint() {
  local install_dir="$1"
  local entrypoint="$2"

  mkdir -p "$install_dir/bin"
  (cd "$install_dir/bin" && ln -sf "$entrypoint" dbt)
}

# Normalises environment for pip install
create_core_venv_and_install() {
  local install_dir="$1" version="$2"
  local python_bin
  python_bin="$(get_python_bin)"

  if [[ -n "${ASDF_DBT_CORE_BOOTSTRAP_BIN:-}" ]]; then
    mkdir -p "$install_dir/bin"
    cp "$ASDF_DBT_CORE_BOOTSTRAP_BIN" "$install_dir/bin/dbt"
    chmod +x "$install_dir/bin/dbt"
    return
  fi

  "$python_bin" -m venv "$install_dir/venv"
  local venv_python
  venv_python="$install_dir/venv/bin/python"

  local target="dbt-core==${version}"
  local extra_args=()

  if [[ -n "${ASDF_DBT_CORE_DIST_PATH:-}" ]]; then
    target="$ASDF_DBT_CORE_DIST_PATH"
    extra_args+=("--no-index")
  fi

  if [[ -n "${ASDF_DBT_CORE_PIP_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args+=(${ASDF_DBT_CORE_PIP_ARGS})
  fi

  "$venv_python" -m pip install "$target" "${extra_args[@]}"

  local entrypoint
  entrypoint="$install_dir/venv/bin/dbt"
  if [[ ! -x "$entrypoint" ]]; then
    fail "dbt executable not found in virtualenv"
  fi

  link_venv_entrypoint "$install_dir" "$entrypoint"
}

# Download file with optional checksum verification
fetch_file() {
  local url="$1" dest="$2" expected_sha="$3"

  curl -fsSL "$url" -o "$dest"

  if [[ -n "$expected_sha" ]]; then
    local actual
    actual="$(sha256sum "$dest" | awk '{print $1}')"
    if [[ "$expected_sha" != "$actual" ]]; then
      rm -f "$dest"
      fail "Checksum mismatch for $url"
    fi
  fi
}

install_fusion_from_manifest() {
  local install_dir="$1" version="$2"
  local manifest_path
  manifest_path="$(fusion_manifest_path)"
  trap 'cleanup_temp_manifest "$manifest_path"' RETURN

  if [[ ! -f "$manifest_path" ]]; then
    fail "Fusion manifest not found at $manifest_path"
  fi

  local platform_key
  platform_key="$(resolve_fusion_platform_key)"

  local url sha bin_path python_json
  python_json="$(get_python_bin)"
  readarray -t _fusion_fields < <(
    "$python_json" - "$manifest_path" "$version" "$platform_key" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
version = sys.argv[2]
platform = sys.argv[3]

try:
    data = json.loads(manifest_path.read_text())
except FileNotFoundError:
    sys.exit(1)

versions = data.get("versions", {})
record = versions.get(version, {})
platform_info = record.get(platform)

if not platform_info:
    sys.exit(0)

url = platform_info.get("url", "")
sha = platform_info.get("sha256", "")
bin_path = platform_info.get("bin", "dbt")

print(url)
print(sha)
print(bin_path)
PY
  )

  url="${_fusion_fields[0]:-}"
  sha="${_fusion_fields[1]:-}"
  bin_path="${_fusion_fields[2]:-dbt}"

  if [[ -z "$url" || "$url" == "null" ]]; then
    trap - RETURN
    fail "No download URL for fusion version $version and platform $platform_key"
  fi

  mkdir -p "$install_dir"
  local tmp
  tmp="$(mktemp)"
  fetch_file "$url" "$tmp" "$sha"

  if [[ "$url" == *.tar.gz || "$url" == *.tgz ]]; then
    tar -xzf "$tmp" -C "$install_dir"
  else
    tar -xf "$tmp" -C "$install_dir"
  fi
  rm -f "$tmp"

  local entrypoint="$install_dir/$bin_path"
  if [[ ! -x "$entrypoint" ]]; then
    trap - RETURN
    fail "Fusion CLI entrypoint not found at $entrypoint"
  fi

  mkdir -p "$install_dir/bin"
  (cd "$install_dir/bin" && ln -sf "../$bin_path" dbt)
  trap - RETURN
}

