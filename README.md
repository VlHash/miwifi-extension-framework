# MiWiFi-Extension-Framework (MWEF)

**English** | [简体中文](README_CN.md)

MWEF is an extensible plugin framework for the native Xiaomi router WebUI, maintained by **VlHash**. It preserves the legacy `xqext` routes, static-resource prefixes, and persistent directory layout so existing installations can be upgraded in place.

The built-in `system` plugin provides a system overview and has been verified on the Xiaomi Router BE6500 Pro (`ipq53xx/generic`).

## Features

- A native top-level **Extensions** entry containing **System Information** and **Framework Settings**
- Simplified Chinese and English UI languages, with a localization convention for plugins
- `.tar.gz` plugin upload, pre-install validation, permission confirmation, enable/disable controls, grant management, and recoverable removal
- A configurable plugin installation directory under `/data`; existing plugins are copied during migration and the previous directory is retained for recovery
- Automatic plugin-overlay merging and WebUI repatching without modifying the read-only SquashFS
- Built-in system information plugin with dynamically detected model/platform/kernel/firmware data, CPU and RAM charts, expandable mean-temperature details, and writable-partition usage
- Compatibility with the existing `xqext` paths: `/data/other_vol/xqext`, `/xqext`, and `/web/xqext`

## Safety Boundary

MWEF does not use `mtd write`, `mtd erase`, firmware-partition flashing, Bootloader modification, or writable SquashFS remounting. Patches and plugins are stored only in persistent `/data` storage, and OverlayFS provides the runtime view.

Plugin packages containing absolute paths, path traversal, symbolic links, or special files are rejected. High-risk permissions such as `shell.execute` require explicit administrator approval. The current permission system is an auditable controlled-execution model, not a kernel-level sandbox; see the [security model](docs/security-model.md) for details.

## Build the Framework

```powershell
./scripts/build.ps1
```

Output: `dist/mwef-0.2.3.tar.gz`

## Install or Upgrade

Extract the archive into `/data/other_vol/xqext`, then run:

```sh
chmod 755 /data/other_vol/xqext/scripts/*.sh
/data/other_vol/xqext/scripts/install.sh
```

The installer keeps legacy XQExt files as a migration backup, rebuilds the OverlayFS layers, and registers the `firewall.xqext` startup entry. It does not reboot the router or proactively reload the firewall.

## Plugin Development

- [Plugin Development Guidelines](docs/plugin-development.md)
- [Permissions and Security Model](docs/security-model.md)
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
