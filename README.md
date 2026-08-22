# MiWiFi-Extension-Framework (MWEF)

**English** | [简体中文](README_CN.md)

MWEF is an extensible plugin framework for the native Xiaomi router WebUI. It preserves the legacy `xqext` routes, static-resource prefixes, and persistent directory layout so existing installations can be upgraded in place.

The built-in `system` plugin provides a system overview and has been verified on the Xiaomi Router BE6500 Pro (`ipq53xx/generic`).

## Features

- A native top-level **Extensions** entry containing **System Information** and **Framework Settings**
- Simplified Chinese and English UI languages, with a localization convention for plugins
- `.tar.gz` plugin upload, pre-install validation, permission confirmation, enable/disable controls, grant management, and recoverable removal
- A configurable plugin installation directory under `/data`; existing plugins are copied during migration and the previous directory is retained for recovery
- Automatic plugin-overlay merging and WebUI repatching without modifying the read-only SquashFS
- Built-in system information plugin with dynamically detected model/platform/kernel/firmware data, CPU and RAM charts, expandable mean-temperature details, and writable-partition usage
- A GitHub Contributors bar on the Framework Settings page, with a local fallback when GitHub is unavailable
- Framework Settings can check the official update index, install a verified online release, or validate and install an uploaded framework release package
- A versioned official plugin index on the `plugins` branch for future online package management
- Compatibility with the existing `xqext` paths: `/data/other_vol/xqext`, `/xqext`, and `/web/xqext`

## Safety Boundary

MWEF does not use `mtd write`, `mtd erase`, firmware-partition flashing, Bootloader modification, or writable SquashFS remounting. Patches and plugins are stored only in persistent `/data` storage, and OverlayFS provides the runtime view.

Plugin packages containing absolute paths, path traversal, symbolic links, or special files are rejected. High-risk permissions such as `shell.execute` require explicit administrator approval. The current permission system is an auditable controlled-execution model, not a kernel-level sandbox; see the [security model](docs/security-model.md) for details.

## Build the Framework

On Unix, Linux, or macOS:

```sh
chmod +x ./build.sh
./build.sh
```

On Windows PowerShell:

```powershell
./scripts/build.ps1
```

Both build methods produce `dist/mwef-0.2.5.tar.gz` with the same package layout.

## Install or Upgrade

### One-click installer

Run as `root`. The router-oriented commands below use `curl -k` because some Xiaomi firmware builds cannot validate the available certificate chain. `MWEF_INSECURE=1` applies the same behavior to the release-archive download. The installer downloads into `/tmp`, verifies the pinned release SHA-256, rejects unsafe archive entries, stages files under `/data`, and then invokes the framework installer.

GitHub source:

```sh
export url='https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/main' \
  && MWEF_INSECURE=1 sh -c "$(curl -kfsSL "$url/install.sh")"
```

jsDelivr GitHub mirror:

```sh
export url='https://testingcf.jsdelivr.net/gh/VlHash/miwifi-extension-framework@main' \
  && MWEF_INSECURE=1 sh -c "$(curl -kfsSL "$url/install.sh")"
```

GitHub mirror for both the installer and release archive:

```sh
export url='https://ghfast.top/https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/main' \
  && MWEF_GITHUB_MIRROR='https://ghfast.top' MWEF_INSECURE=1 sh -c "$(curl -kfsSL "$url/install.sh")"
```

`MWEF_GITHUB_MIRROR` is an optional URL prefix. The embedded release SHA-256 is always checked, including when a mirror or `MWEF_INSECURE=1` is used. However, `curl -k` does not authenticate the server that supplies `install.sh`; a man-in-the-middle could replace the installer and its embedded checksum. Use these commands only on a trusted network and prefer normal certificate verification whenever the router supports it.

### Local archive

Extract the archive into `/data/other_vol/xqext`, then run:

```sh
chmod 755 /data/other_vol/xqext/scripts/*.sh
/data/other_vol/xqext/scripts/install.sh
```

The installer keeps legacy XQExt files as a migration backup, rebuilds the OverlayFS layers, and registers the `firewall.xqext` startup entry. It does not reboot the router or proactively reload the firewall.

### Update from Framework Settings

Open **Extensions → Framework Settings → Framework Update** to either:

- check the official `plugins`-branch update index and install its release; or
- upload an official `mwef-<version>.tar.gz` release package.

Online and uploaded releases are limited to 16 MiB. Browser uploads use ordered 32 KiB chunks to remain compatible with the Xiaomi Web service's request-size limit; the router checks the reconstructed archive's final size and hash. MWEF rejects unexpected archive paths, links, and special files before activation. Online releases must also match the size and SHA-256 in the update index. The current `/data/other_vol/xqext` framework is moved to `/data/other_vol/xqext-framework-recovery/` before the staged release is activated; if installation or repatching fails, MWEF restores the previous framework. Plugins and settings are carried into the new version. Framework downgrades are rejected by the WebUI updater.

## Plugin Development

- [Plugin Development Guidelines](docs/plugin-development.md)
- [Permissions and Security Model](docs/security-model.md)
- [Online Plugin Index Specification](docs/plugin-index.md)
- [Plugin Manifest JSON Schema](schema/mwef-plugin.schema.json)
- [Hello MWEF Example](examples/hello-mwef)

Build the example plugin with:

```powershell
./tools/build-plugin.ps1 -Source examples/hello-mwef
```

## Uninstall

```sh
/data/other_vol/xqext/scripts/uninstall.sh
```

Uninstallation detaches the runtime mounts, removes the startup entry, and renames the entire framework directory with a timestamped disabled suffix so it can be restored.

## License

[MIT](LICENSE) © 2026 VlHash
