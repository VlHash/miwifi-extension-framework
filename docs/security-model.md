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

## One-click Framework Installer

The repository-root `install.sh` downloads a pinned release archive into `/tmp`, verifies its embedded SHA-256, rejects unsafe tar paths, and rejects links or special files after extracting into a temporary staging directory under `/data/other_vol`. Only then are framework files copied into `/data/other_vol/xqext` and the local framework installer invoked.

GitHub mirrors are optional transport prefixes. They do not disable archive verification. The router-oriented README commands explicitly use `curl -k` and `MWEF_INSECURE=1` for firmware builds whose certificate chain cannot be validated; SHA-256 verification remains mandatory in that mode. This does not authenticate the installer itself: a man-in-the-middle able to replace `install.sh` could also replace its embedded checksum, so insecure transport must be limited to a trusted network.

## Framework Self-update

Framework Settings accepts either the release selected by the official update index or an administrator-uploaded framework archive. Archives are limited to 16 MiB and extracted into a private staging directory on `/data/other_vol`. Browser uploads are serialized into 32 KiB chunks to stay below the Xiaomi Web service request limit; the server records the expected total, rejects out-of-order or oversized chunks, and validates the fully reconstructed archive. The updater allowlists framework paths, rejects traversal, links, and special files, requires the core API/UI/install/update files, and verifies the framework id and `VlHash` author field. Online downloads must match both the byte size and SHA-256 declared by the update index. Uploaded releases are locally hashed and shown only after validation.

The updater serializes framework and plugin transactions, stops only the MWEF OverlayFS mounts, and renames the installed framework into `/data/other_vol/xqext-framework-recovery/` before activating the staged tree. Configuration and plugins are transferred to the new tree. If installation or repatching fails, the new tree is retained as a failed recovery copy and the previous framework is restored and started again. No MTD, block device, firmware partition, or read-only SquashFS write is involved.

The current Xiaomi-router compatibility mode uses `curl -k` for the online index and archive. The index SHA-256 protects against corruption and mismatched mirrors, but it does not authenticate an index obtained over unauthenticated TLS; an active man-in-the-middle could replace both metadata and payload. Use online update only on a trusted network. Uploading a release obtained and verified on another machine avoids router-side network transport, but the administrator remains responsible for the uploaded file's provenance.

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
- A failed framework self-update restores the previous framework; successful updates retain the old core tree in `/data/other_vol/xqext-framework-recovery/`.
- Framework uninstallation detaches the mounts, removes the startup entry, and renames `/data/other_vol/xqext` for recovery.
- The original SquashFS files under `/www` and `/usr/lib/lua/luci` are never modified.
