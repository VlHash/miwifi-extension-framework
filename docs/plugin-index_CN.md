# MWEF 在线插件索引规范（Schema v1）

[English](plugin-index.md) | **简体中文**

官方在线插件索引发布在仓库的 `plugins` 分支：

```text
https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.json
```

该索引供内置 `mwef-lib-packmanager` 读取，只包含元数据，不会授予权限或执行插件代码。

## 顶层格式

```json
{
  "schemaVersion": 1,
  "name": "MWEF Official Plugin Index",
  "maintainer": "VlHash",
  "updated": "2026-08-22",
  "plugins": []
}
```

- `schemaVersion` 标识索引格式，当前固定为 `1`。
- `name` 和 `maintainer` 标识软件源。
- `updated` 使用 ISO 8601 日期。
- `plugins` 包含零个或多个插件版本记录。

## 插件记录

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

每个条目必须符合 MWEF 的插件 ID、版本、权限和本地化约定。`archive.url` 必须使用 HTTPS，`archive.sha256` 必须填写软件包 SHA-256，`archive.size` 为精确字节数。

## Package 客户端要求

读取该索引的 Package 插件必须：

1. 限制索引下载大小，并在显示条目前使用 `index.schema.json` 校验。
2. 拒绝不支持的 `schemaVersion` 和重复插件 ID。
3. 只下载 HTTPS 归档，并在安装前限制文件大小。
4. 将文件长度和 SHA-256 与索引声明逐一核对，再交给 MWEF 处理。
5. 继续使用 MWEF 现有的软件包检查与权限确认流程；索引条目不得自动授予权限。
6. 把本地化文字和远程 URL 当作不可信输入，不得直接插入 `innerHTML` 或 Shell 命令。

权威索引 Schema 与 `index.json` 一同发布在 `plugins` 分支。
