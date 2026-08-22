# MWEF 官方插件索引

[English](PLUGIN_INDEX.md) | **简体中文**

该分支用于发布机器可读的软件源，供后续 MWEF Package 插件读取。

## 地址

- 索引：`https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.json`
- Schema：`https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.schema.json`

在首个经过审查的在线插件包发布前，软件源暂时保持为空。内置插件随框架发布，不在该索引中重复列出。

## 发布要求

添加或更新条目前必须：

1. 按 MWEF Schema v1 验证插件包。
2. 审查插件声明的权限和源代码。
3. 通过 HTTPS 发布不可变的 `.tar.gz` 归档。
4. 记录精确字节数和小写 SHA-256。
5. 使用 `index.schema.json` 校验 `index.json`。
6. 保证插件 ID 唯一，并更新顶层 `updated` 日期。

Package 插件仍须使用 MWEF 的软件包检查与管理员权限确认流程。加入软件源不会自动授予任何权限。
