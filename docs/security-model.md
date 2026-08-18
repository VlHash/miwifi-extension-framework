# MWEF Permissions and Security Model

**English** | [简体中文](security-model_CN.md)

## Objective

MWEF provides an auditable and reversible plugin installation and runtime mechanism without modifying read-only firmware or writing to MTD.

## Installation Boundary

1. Uploaded packages are written only to `/tmp` and are limited to 8 MiB.
2. Every tar path is checked before extraction; absolute paths, path traversal, and backslash-separated paths are rejected.
3. Symbolic links and special files are rejected after extraction.
4. Permission confirmation is shown only after the manifest passes Schema v1 validation.
5. Installation uses a staging directory on the same filesystem; the previous version is moved into `.recovery` before an upgrade.
6. Enabling or disabling a plugin rebuilds the generated layers and remounts OverlayFS.

## Permission Model

The manifest `permissions` array is the requested set, while `.grants` stores the set approved by the administrator. The controlled MWEF hook runner checks for `shell.execute` before running a script. Approved permissions can be added or revoked at any time from the plugin-management page.

MWEF 0.2.x does not claim to provide a mandatory sandbox based on Linux namespaces, seccomp, or separate Unix users. LuCI controllers normally inherit the Web service's privileges, so source review remains part of the security boundary. A plugin should be rejected if it uses undeclared permissions, invokes shell commands directly, overwrites authentication code, or escapes its own directory.

## Shell Rules

- Shell files must be located under `scripts/`; filenames may contain only letters, numbers, periods, underscores, and hyphens.
- The MWEF hook runner refuses execution unless the `shell.execute` grant is present.
- Plugins must not construct shell commands from Web parameters.
- `mtd write`, `mtd erase`, block-device writes through `dd`, Bootloader modification, and firmware-partition operations are forbidden.
- Controlling a service also requires the `service.control` permission.

## Recovery

- Plugin removal moves the plugin into the installation directory's `.recovery/` folder.
- A failed plugin upgrade restores the previous version and runs the patch process again.
- Framework uninstallation detaches the mounts, removes the startup entry, and renames `/data/other_vol/xqext` for recovery.
- The original SquashFS files under `/www` and `/usr/lib/lua/luci` are never modified.
