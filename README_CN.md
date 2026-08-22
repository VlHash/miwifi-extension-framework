# MiWiFi-Extension-Framework (MWEF)

[English](README.md) | **简体中文**

MWEF 是面向小米路由器原生 WebUI 的可扩展插件框架。项目保留早期 `xqext` 的路由、静态资源前缀和持久化目录，因此可从现有安装平滑升级。

当前内置 `system` 系统信息插件，已在 Xiaomi Router BE6500 Pro（`ipq53xx/generic`）上验证。

## 功能

- 原生一级入口“扩展设置”，内含“系统信息”和“框架设置”
- 中文（简体）/ English 语言切换及插件语言包约定
- `.tar.gz` 插件上传、安装前检查、权限确认、启用/停用、权限调整和可恢复移除
- 可配置 `/data` 下的插件安装目录；迁移时复制现有插件并保留旧目录
- 插件 Overlay 自动合并并重新 patch，无需修改只读 SquashFS
- 内置系统信息插件：动态机型/平台/内核/固件、CPU/RAM 图表、平均温度折叠详情、可写分区统计
- 框架设置页面底部展示 GitHub Contributors；GitHub 不可访问时使用本地回退内容
- `plugins` 分支提供版本化官方插件索引，为后续在线软件包管理做准备
- `xqext` 兼容路径：`/data/other_vol/xqext`、`/xqext`、`/web/xqext`

## 安全边界

MWEF 不使用 `mtd write`、`mtd erase`、分区刷写或 Bootloader 修改，也不把 SquashFS 重新挂载为可写。补丁和插件仅存放在 `/data` 持久化区域，通过 OverlayFS 生成运行时视图。

插件包会拒绝绝对路径、路径穿越、符号链接和特殊文件。`shell.execute` 等高权限必须由管理员明确批准。当前权限系统是审查与受控执行模型，不是内核级沙箱；详见[安全模型](docs/security-model_CN.md)。

## 构建框架

Unix、Linux 或 macOS：

```sh
chmod +x ./build.sh
./build.sh
```

Windows PowerShell：

```powershell
./scripts/build.ps1
```

两种方式均会生成包结构相同的 `dist/mwef-0.2.4.tar.gz`。

## 安装/升级

### 一键安装

请使用 `root` 执行。安装器会将文件下载到 `/tmp`，校验发布包 SHA-256，拒绝不安全的归档条目，在 `/data` 下完成 staging，然后调用框架安装器。

使用 GitHub 官方源和 `curl`：

```sh
curl -fsSL https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/main/install.sh -o /tmp/mwef-install.sh && sh /tmp/mwef-install.sh
```

使用 GitHub 官方源和 `wget`：

```sh
wget -q -O /tmp/mwef-install.sh https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/main/install.sh && sh /tmp/mwef-install.sh
```

使用 jsDelivr 获取安装器：

```sh
wget -q -O /tmp/mwef-install.sh https://cdn.jsdelivr.net/gh/VlHash/miwifi-extension-framework@main/install.sh && sh /tmp/mwef-install.sh
```

安装器和发布归档均使用 GitHub 镜像：

```sh
wget -q -O /tmp/mwef-install.sh https://ghfast.top/https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/main/install.sh && MWEF_GITHUB_MIRROR=https://ghfast.top sh /tmp/mwef-install.sh
```

`MWEF_GITHUB_MIRROR` 是可选的 URL 前缀。使用镜像不会绕过软件包校验，安装器始终核对内置的发布归档 SHA-256。仅在老旧 TLS 客户端确实无法连接时显式设置 `MWEF_INSECURE=1`，完整性校验仍然强制执行。

### 本地归档

将归档内容解压到 `/data/other_vol/xqext`，然后执行：

```sh
chmod 755 /data/other_vol/xqext/scripts/*.sh
/data/other_vol/xqext/scripts/install.sh
```

安装脚本会保留旧 XQExt 文件作为迁移备份，重建 Overlay 层，并登记 `firewall.xqext` 开机启动项。不会重启路由器，也不会主动 reload 防火墙。

## 开发插件

- [插件开发规范](docs/plugin-development_CN.md)
- [权限与安全模型](docs/security-model_CN.md)
- [在线插件索引规范](docs/plugin-index_CN.md)
- [插件 Manifest JSON Schema](schema/mwef-plugin.schema.json)
- [Hello MWEF 示例](examples/hello-mwef/README_CN.md)

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
