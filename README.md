# MiWiFi-Extension-Framework (MWEF)

MWEF 是面向小米路由器原生 WebUI 的可扩展插件框架，作者为 **VlHash**。项目保留早期 `xqext` 的路由、静态资源前缀和持久化目录，因此可从现有安装平滑升级。

当前内置 `system` 系统信息插件，已在 Xiaomi Router BE6500 Pro（`ipq53xx/generic`）上验证。

## 功能

- 原生一级入口“扩展设置”，内含“系统信息”和“框架设置”
- 中文（简体）/ English 语言切换及插件语言包约定
- `.tar.gz` 插件上传、安装前检查、权限确认、启用/停用、权限调整和可恢复移除
- 可配置 `/data` 下的插件安装目录；迁移时复制现有插件并保留旧目录
- 插件 Overlay 自动合并并重新 patch，无需修改只读 SquashFS
- 内置系统信息插件：动态机型/平台/内核/固件、CPU/RAM 图表、平均温度折叠详情、可写分区统计
- `xqext` 兼容路径：`/data/other_vol/xqext`、`/xqext`、`/web/xqext`

## 安全边界

MWEF 不使用 `mtd write`、`mtd erase`、分区刷写或 Bootloader 修改，也不把 SquashFS 重新挂载为可写。补丁和插件仅存放在 `/data` 持久化区域，通过 OverlayFS 生成运行时视图。

插件包会拒绝绝对路径、路径穿越、符号链接和特殊文件。`shell.execute` 等高权限必须由管理员明确批准。当前权限系统是审查与受控执行模型，不是内核级沙箱；详见 [安全模型](docs/security-model.md)。

## 构建框架

```powershell
./scripts/build.ps1
```

产物：`dist/mwef-0.2.2.tar.gz`

## 安装/升级

将归档内容解压到 `/data/other_vol/xqext`，然后执行：

```sh
chmod 755 /data/other_vol/xqext/scripts/*.sh
/data/other_vol/xqext/scripts/install.sh
```

安装脚本会保留旧 XQExt 文件作为迁移备份，重建 Overlay 层，并登记 `firewall.xqext` 开机启动项。不会重启路由器，也不会主动 reload 防火墙。

## 开发插件

- [插件开发规范](docs/plugin-development.md)
- [权限与安全模型](docs/security-model.md)
- [插件 Manifest JSON Schema](schema/mwef-plugin.schema.json)
- [Hello MWEF 示例](examples/hello-mwef)

构建示例插件：

```powershell
./tools/build-plugin.ps1 -Source examples/hello-mwef
```

## 卸载

```sh
/data/other_vol/xqext/scripts/uninstall.sh
```

卸载会解除运行时挂载并移除启动项，随后将整个框架目录重命名为带时间戳的禁用目录，以便恢复。

## License

[MIT](LICENSE) © 2026 VlHash
