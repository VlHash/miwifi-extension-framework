# MWEF Framework Update Index

**English** | [简体中文](FRAMEWORK_INDEX_CN.md)

`framework.json` is the machine-readable release selected by **Framework Settings → Framework Update**. It is intentionally separate from the plugin catalog in `index.json`.

## Publication workflow

1. Build and validate the framework archive.
2. Publish the immutable archive as a GitHub Release asset.
3. Confirm the remote asset size and SHA-256.
4. Update `framework.json` with the version, tag, release notes URL, byte size, SHA-256, and ordered download URLs.
5. Validate the index and push the `plugins` branch.

The first archive URL is the canonical GitHub Release asset. Additional URLs are transport mirrors for the same immutable bytes and must use the same SHA-256. Framework clients accept only the official repository's GitHub Release URL or the explicitly allowlisted `ghfast.top` prefix.

## Client behavior

MWEF downloads this index from the raw GitHub URL, with a `testingcf.jsdelivr.net` branch mirror as fallback. The router validates Schema v1 fields, `framework: mwef`, `author: VlHash`, the version and tag, trusted URL patterns, archive size, and archive SHA-256 before staging. The installed framework is retained for rollback.

Some Xiaomi firmware builds require `curl -k`. Therefore, the hash detects corruption and mirror mismatch but does not authenticate metadata obtained through unauthenticated TLS. Use online update only on a trusted network, or upload a release obtained and verified on another machine.
