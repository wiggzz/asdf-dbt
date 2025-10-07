#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

create_fusion_fixture() {
  local workdir="$TMPDIR/fusion-src"
  mkdir -p "$workdir/dbt-fusion"
  cat <<'SCRIPT' > "$workdir/dbt-fusion/dbt"
#!/usr/bin/env bash
echo "fake dbt fusion $@"
SCRIPT
  chmod +x "$workdir/dbt-fusion/dbt"

  local tarball="$TMPDIR/dbt-fusion.tar.gz"
  tar -czf "$tarball" -C "$workdir" dbt-fusion
  local sha
  sha="$(sha256sum "$tarball" | awk '{print $1}')"

  local manifest="$TMPDIR/fusion-manifest.json"
  sed "s|__URL__|file://$tarball|;s|__SHA__|$sha|" \
    "$ROOT/test/fixtures/fusion-manifest-template.json" > "$manifest"

  echo "$manifest"
}

main() {
  echo "==> Preparing fusion fixture"
  local fusion_manifest
  fusion_manifest="$(create_fusion_fixture)"

  echo "==> Testing list-all output"
  local expected="fusion-0.0.1-test
core-1.7.9
core-1.8.0"
  local output
  output="$(ASDF_DBT_CORE_VERSIONS_PATH="$ROOT/test/fixtures/core-versions.txt" \
    ASDF_DBT_FUSION_MANIFEST_PATH="$fusion_manifest" \
    "$ROOT/bin/list-all" list-all)"
  if [[ "$output" != "$expected" ]]; then
    echo "Unexpected list-all output" >&2
    echo "Expected:\n$expected" >&2
    echo "Got:\n$output" >&2
    exit 1
  fi

  echo "==> Installing dbt core"
  ASDF_INSTALL_PATH="$TMPDIR/core" \
    ASDF_DBT_CORE_BOOTSTRAP_BIN="$ROOT/test/fixtures/dbt-core-stub.sh" \
    "$ROOT/bin/install" install core-1.7.9
  local core_output
  core_output="$(ASDF_INSTALL_PATH="$TMPDIR/core" "$ROOT/bin/exec")"
  if [[ "$core_output" != "fake dbt core from stub" ]]; then
    echo "Unexpected dbt core output: $core_output" >&2
    exit 1
  fi

  echo "==> Installing dbt fusion"
  ASDF_INSTALL_PATH="$TMPDIR/fusion" \
    ASDF_DBT_FUSION_MANIFEST_PATH="$fusion_manifest" \
    "$ROOT/bin/install" install fusion-0.0.1-test
  local fusion_output
  fusion_output="$(ASDF_INSTALL_PATH="$TMPDIR/fusion" "$ROOT/bin/exec" --profile test)"
  if [[ "$fusion_output" != "fake dbt fusion --profile test" ]]; then
    echo "Unexpected dbt fusion output: $fusion_output" >&2
    exit 1
  fi

  echo "All tests passed"
}

main "$@"
