# mwef-lib-packmanager

The built-in online package manager for MWEF. Open it from **Extensions → Packages**.

## Features

- Reads online plugins from an MWEF Index Schema v1 source.
- Filters all, update, available, and installed packages with local search.
- Enforces the exact byte length and SHA-256 declared by the index.
- Reuses the framework's archive-path checks, extraction checks, permission review, transactional install, upgrade backup, and failure rollback.
- Uses a Xiaomi WebUI-style dialog for the plugin index and GitHub mirror/proxy prefix.
- Provides GitHub Raw, jsDelivr, and `ghfast.top` presets, while allowing custom HTTPS sources.

## Persistent settings

Source settings are stored at:

```text
/data/other_vol/xqext/config/mwef-lib-packmanager/sources.json
```

The framework preserves this `config` directory across plugin and framework updates.

## Security note

The browser submits only a plugin ID. The router selects the archive URL, size, and SHA-256 from the validated index, then compares the staged package ID, version, author, compatibility requirement, and permissions with that index entry.

Like the framework updater, router compatibility mode uses `curl -k`. SHA-256 detects a mirror response that differs from the current index, but an unsigned index cannot prevent an active attacker from replacing both the index and archive. Use trusted sources on a trusted network.
