# MWEF Online Plugin Index Specification (Schema v1)

**English** | [简体中文](plugin-index_CN.md)

The official online plugin index is published from the repository's `plugins` branch:

```text
https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.json
```

This index is consumed by the built-in `mwef-lib-packmanager`. It is metadata only and does not grant permissions or execute plugin code.

## Top-level Format

```json
{
  "schemaVersion": 1,
  "name": "MWEF Official Plugin Index",
  "maintainer": "VlHash",
  "updated": "2026-08-22",
  "plugins": []
}
```

- `schemaVersion` identifies the index format and is currently fixed at `1`.
- `name` and `maintainer` identify the catalog.
- `updated` is an ISO 8601 calendar date.
- `plugins` contains zero or more plugin release records.

## Plugin Record

```json
{
  "id": "example-plugin",
  "name": {
    "en": "Example Plugin",
    "zh-CN": "示例插件"
  },
  "description": {
    "en": "An example online package.",
    "zh-CN": "在线软件包示例。"
  },
  "version": "1.0.0",
  "author": "VlHash",
  "license": "MIT",
  "mwef": ">=0.2.4",
  "permissions": [],
  "archive": {
    "url": "https://example.invalid/example-plugin-1.0.0.tar.gz",
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "size": 12345
  },
  "homepage": "https://github.com/example/example-plugin",
  "source": "https://github.com/example/example-plugin"
}
```

An entry must follow the MWEF plugin ID, version, permission, and localization conventions. `archive.url` must use HTTPS, `archive.sha256` must contain the package SHA-256, and `archive.size` is the exact byte length.

## Package Client Requirements

A Package plugin consuming this index must:

1. Limit the downloaded index size and validate it against `index.schema.json` before rendering entries.
2. Reject unsupported `schemaVersion` values and duplicate plugin IDs.
3. Download only HTTPS archives and enforce a size limit before installation.
4. Verify both the declared byte length and SHA-256 before passing a package to MWEF.
5. Use the existing MWEF package inspector and permission-confirmation flow; an index entry must never grant permissions automatically.
6. Treat localized text and remote URLs as untrusted input and never insert them directly into `innerHTML` or shell commands.

The authoritative index schema is published alongside `index.json` on the `plugins` branch.
