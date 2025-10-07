# asdf-dbt

An [asdf](https://asdf-vm.com) plugin for installing the dbt Core and dbt Fusion CLIs.

## Features

- Install dbt Core releases into isolated Python virtual environments (no global Python pollution).
- Install dbt Fusion CLI releases published to the dbt CDN.
- Works with the standard `asdf list-all`, `asdf install`, and `asdf exec` flows.

## Version naming

Two families of versions are exposed:

- `core-x.y.z` – install the dbt Core Python package at version `x.y.z`.
- `fusion-x.y.z` – install the dbt Fusion CLI binary release `x.y.z` for your platform.

If you omit the `core-` prefix when installing, the plugin assumes you want dbt Core:

```sh
asdf install dbt 1.7.8
```

## Installing dbt Core

The plugin creates an isolated virtual environment inside the installation directory using the system `python3` (configurable through `ASDF_DBT_PYTHON_BIN`). The dbt Core package is then installed with `pip`. You can customise how pip installs by using the following environment variables:

- `ASDF_DBT_CORE_DIST_PATH` – path/URL to a wheel or sdist archive for offline installs (implies `--no-index`).
- `ASDF_DBT_CORE_PIP_ARGS` – additional arguments passed to `pip install`.
- `ASDF_DBT_PYTHON_BIN` – absolute path to the Python interpreter used to create the virtual environment.

## Installing dbt Fusion

dbt Fusion builds are distributed as tarballs from a CDN. The plugin consumes a JSON manifest describing the available versions and per-platform assets. By default the manifest located at `share/fusion-manifest.json` is used, but you will typically want to keep it in sync with upstream releases.

You can customise where the manifest comes from:

- `ASDF_DBT_FUSION_MANIFEST_URL` – HTTP(S) URL to download the manifest.
- `ASDF_DBT_FUSION_MANIFEST_PATH` – local path to a manifest file (skips downloading).

Each manifest entry has the following shape:

```json
{
  "versions": {
    "0.6.4": {
      "linux-x86_64": {
        "url": "https://…/dbt-fusion-0.6.4-linux-x86_64.tar.gz",
        "sha256": "…",
        "bin": "dbt-fusion"
      }
    }
  }
}
```

Use `bin/list-all` to see the available versions once the manifest is populated.

### Updating the manifest

When you have access to the upstream manifest (for example by running the official install script shown in the dbt docs), drop it into `share/fusion-manifest.json` or host it somewhere and point `ASDF_DBT_FUSION_MANIFEST_URL` at it. The repository includes `scripts/update-fusion-manifest.py` to help automate the download when network access is available.

## Development

### Requirements

- Bash 3+
- Python 3.8+
- curl, tar, sha256sum

### Tests

A simple end-to-end test suite lives under `test/`. Run it with:

```sh
./test/run-tests.sh
```

The tests fabricate local dbt Core and dbt Fusion artifacts to exercise the installer paths without contacting the network.
They rely on the internal `ASDF_DBT_CORE_BOOTSTRAP_BIN` hook to drop in a stub `dbt` executable instead of invoking `pip`.

## License

MIT
