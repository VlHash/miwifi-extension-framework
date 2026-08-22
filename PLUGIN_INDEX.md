# MWEF Official Plugin Index

**English** | [简体中文](PLUGIN_INDEX_CN.md)

This branch publishes the machine-readable catalog used by the future MWEF Package plugin.

## Endpoints

- Index: `https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.json`
- Schema: `https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.schema.json`

Built-in plugins are shipped with the framework and are not listed here.

## Available Plugins

- **NekoCoffee 1.1.0** — A lightweight Xiaomi WebUI-style panel for a local neko traffic companion. The catalog records its immutable release archive, exact size, and SHA-256 checksum.

## Publishing Requirements

Before adding or updating an entry:

1. Validate the plugin package against MWEF Schema v1.
2. Review its declared permissions and source code.
3. Publish the immutable `.tar.gz` archive over HTTPS.
4. Record its exact byte length and lowercase SHA-256.
5. Validate `index.json` against `index.schema.json`.
6. Keep plugin IDs unique and update the top-level `updated` date.

The Package plugin must still use MWEF's package inspection and administrator permission-confirmation flow. Catalog membership never grants permissions automatically.
