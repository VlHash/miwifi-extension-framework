# MWEF 插件开发规范（Schema v1）

[English](plugin-development.md) | **简体中文**

本文定义 MWEF 0.3.x 插件包格式。插件作者字段示例统一使用 `VlHash`。

## 1. 包格式

发布文件必须是 gzip 压缩的 tar 包，扩展名为 `.tar.gz` 或 `.tgz`，最大 8 MiB。`mwef-plugin.json` 必须位于归档根目录：

```text
mwef-plugin.json
overlay/
  luci/
    controller/
    view/
  www/
i18n/
  zh-CN.json
  en.json
scripts/
```

所有目录均为可选，只有 `mwef-plugin.json` 必需。包内不得包含绝对路径、`..` 路径段、反斜杠路径、符号链接、硬件设备、FIFO 或 Socket。

## 2. Manifest

最小清单：

```json
{
  "schemaVersion": 1,
  "id": "hello-mwef",
  "name": {
    "zh-CN": "Hello MWEF",
    "en": "Hello MWEF"
  },
  "version": "1.0.0",
  "author": "VlHash",
  "license": "MIT",
  "mwef": ">=0.2.0",
  "permissions": []
}
```

字段规则：

- `schemaVersion`：当前固定为 `1`。
- `id`：`^[a-z][a-z0-9_-]{0,47}$`；安装目录、权限记录和静态命名空间均使用此值。
- `name`、`description`：字符串或包含 `zh-CN`/`en` 的对象。
- `version`：建议使用 SemVer，最长 32 字符。
- `author`：作者或组织；本项目生成内容使用 `VlHash`。
- `mwef`：声明最低兼容框架版本。
- `permissions`：仅可使用权限表中的标识。
- `navigation`：可选菜单贡献，包含本地化 `label`、LuCI `route` 数组和 `order`。
- `entrypoints`：供审查工具识别 Web/API 入口。
- `hooks`：可选 Shell 脚本声明；必须放在 `scripts/`，且不会绕过权限系统自动执行。

完整约束见[插件 Manifest JSON Schema](../schema/mwef-plugin.schema.json)。

## 3. Overlay 映射

- `overlay/luci/` 合并到 `/usr/lib/lua/luci/` 的生成层。
- `overlay/www/` 合并到 `/www/` 的生成层。
- `i18n/` 发布到 `/xqext/plugins/<id>/i18n/`。

插件只能写入自己的命名空间，禁止覆盖 MWEF 核心控制器、`web/inc/header.htm`、其他插件文件或系统登录/鉴权逻辑。控制器必须继续使用 LuCI `;stok=...` 会话，禁止另开未经认证的监听端口。

## 4. 导航

```json
"navigation": {
  "label": { "zh-CN": "示例插件", "en": "Example Plugin" },
  "route": ["web", "xqext", "hello_mwef"],
  "order": 100
}
```

启用插件后，MWEF 会从 Manifest 自动生成扩展设置的二级菜单，无需修改核心 `nav.htm`。

## 5. 语言文件

插件至少应提供 `i18n/zh-CN.json` 和 `i18n/en.json`。键名必须稳定，新增键不得改变旧键含义。页面可读取框架配置并加载：

```text
/xqext/plugins/<id>/i18n/<language>.json
```

不得把用户输入直接插入 `innerHTML`；使用 `textContent` 或 LuCI 的转义输出。

## 6. 权限

| 权限 | 用途 |
| --- | --- |
| `system.read` | 读取系统和硬件状态 |
| `filesystem.read` | 读取声明范围内文件 |
| `filesystem.write` | 写入插件或声明的数据目录 |
| `network.client` | 主动访问外部网络 |
| `service.control` | 控制声明的系统服务 |
| `shell.execute` | 执行插件声明的 Shell 脚本 |

插件安装前会显示请求权限。未获授权的权限不得使用。特别是 Lua 控制器以路由器 Web 服务权限运行，审查者会把未声明的文件、网络、服务或 Shell 行为视为违规。

## 7. 小米 WebUI 风格

- 使用原生 `bc.css`、`layout.css` 和 `/xqext/core.css`。
- 主内容使用 `#bd.xqext-page`，遵循 1040px 内容宽度、左右 60px 内边距、白色圆角面板。
- 设置项使用标题分割线、标签/控件两栏、原生蓝色确认按钮。
- 列表使用蓝色表头分隔线；危险操作应明确标识并二次确认。
- 弹窗使用灰色标题栏、遮罩、取消/确认按钮。
- 不覆盖 `body` 的原生蓝色背景。

## 8. 构建与验证

```powershell
./tools/build-plugin.ps1 -Source examples/hello-mwef
```

发布前至少验证 JSON、JavaScript 语法、Lua 语法、Shell 语法、归档路径和中英语言文件。

## 9. 在线分发

计划加入官方在线软件源的插件还必须符合[在线插件索引规范](plugin-index_CN.md)。发布索引元数据不会绕过软件包检查、校验和或管理员权限确认。
