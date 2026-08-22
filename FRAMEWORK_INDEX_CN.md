# MWEF 框架更新索引

[English](FRAMEWORK_INDEX.md) | **简体中文**

`framework.json` 是“**框架设置 → 框架更新**”使用的机器可读 Release 记录，与 `index.json` 插件目录相互独立。

## 发布流程

1. 构建并验证框架归档。
2. 将不可变归档发布为 GitHub Release 资产。
3. 确认远端资产大小和 SHA-256。
4. 在 `framework.json` 中更新版本、Tag、发行说明 URL、字节数、SHA-256 和有序下载 URL。
5. 验证索引并推送 `plugins` 分支。

第一个归档 URL 是 GitHub Release 官方资产；后续 URL 只是相同不可变内容的传输镜像，必须共用同一 SHA-256。框架客户端只接受官方仓库的 GitHub Release URL，或明确允许的 `ghfast.top` 前缀。

## 客户端行为

MWEF 默认从 GitHub Raw 获取索引，并以 `testingcf.jsdelivr.net` 分支镜像作为回退。路由器在 staging 前会验证 Schema v1 字段、`framework: mwef`、`author: VlHash`、版本与 Tag、可信 URL 格式、归档大小和 SHA-256，同时保留旧框架用于回滚。

部分小米固件需要 `curl -k`，因此哈希可以发现文件损坏或镜像内容不一致，但无法认证通过未验证 TLS 获得的元数据。请只在可信网络中使用在线更新，或上传在其他电脑上获取并验证的 Release。
