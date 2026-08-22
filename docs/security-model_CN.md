# MWEF 权限与安全模型

[English](security-model.md) | **简体中文**

## 目标

MWEF 在不修改只读固件、不写 MTD 的前提下，为插件提供可审查、可撤销的安装与运行机制。

## 安装边界

1. 上传包只写入 `/tmp`，上限 8 MiB。
2. 解包前检查每个 tar 路径，拒绝绝对路径、路径穿越和反斜杠路径。
3. 解包后拒绝符号链接和特殊文件。
4. Manifest 通过 Schema v1 约束后才展示权限确认。
5. 安装使用同一文件系统内的 staging 目录；升级前将旧版本移入 `.recovery`。
6. 插件启停后重建生成层，再重新挂载 OverlayFS。

## 框架一键安装器

仓库根目录的 `install.sh` 会把固定版本的发布归档下载到 `/tmp`，核对脚本内置的 SHA-256，拒绝不安全的 tar 路径，并在 `/data/other_vol` 临时 staging 目录解包后拒绝链接和特殊文件。全部检查通过后，才会把框架文件复制到 `/data/other_vol/xqext` 并调用本地框架安装器。

GitHub 镜像只是可选的传输前缀，不会关闭归档校验。针对无法验证证书链的固件，README 中面向路由器的命令会显式使用 `curl -k` 和 `MWEF_INSECURE=1`；该模式下仍强制执行 SHA-256 校验。但这无法认证安装器本身：能够替换 `install.sh` 的中间人也能替换其中内置的校验和，因此不安全传输只能在可信网络中使用。

## 框架自更新

框架设置可以安装官方更新索引指定的 Release，也可以接收管理员上传的框架归档。归档上限为 16 MiB，并先解压至 `/data/other_vol` 下的私有 staging 目录。浏览器上传会拆分为有序的 32 KiB 分片，以低于小米 Web 服务的单请求限制；服务器记录预期总大小，拒绝乱序或超限分片，并验证完整重组后的归档。更新器仅允许框架路径，拒绝路径穿越、链接与特殊文件，要求核心 API、界面、安装和更新脚本齐全，并验证框架 id 及 `VlHash` 作者字段。在线下载必须同时匹配索引中的字节数与 SHA-256；上传包通过检查后会计算本地哈希。

更新器会串行化框架与插件事务，只停止 MWEF 自身的 OverlayFS 挂载；激活 staging 前，将已安装框架重命名保存至 `/data/other_vol/xqext-framework-recovery/`。配置和插件会迁移到新目录。安装或重新 patch 失败时，新目录作为失败恢复副本保留，旧框架被恢复并重新启动。全过程不涉及 MTD、块设备、固件分区或只读 SquashFS 写入。

为兼容当前小米路由固件，在线索引和归档使用 `curl -k`。索引中的 SHA-256 可以发现文件损坏或镜像内容不一致，但无法认证通过未验证 TLS 获得的索引；主动中间人仍可能同时替换元数据与文件。请只在可信网络中使用在线更新。若在其他电脑上获取并验证 Release 后再上传，可以避开路由器侧网络传输，但上传文件的来源仍由管理员负责确认。

## 权限模型

Manifest 的 `permissions` 是请求集合，`.grants` 是管理员批准集合。框架受控 Hook Runner 会在执行脚本前检查 `shell.execute`。插件管理页面可以随时收回或增加批准权限。

MWEF 0.2.x 不声称提供 Linux namespace、seccomp 或独立 Unix 用户级别的强制沙箱。LuCI 控制器通常继承 Web 服务权限，因此源代码审查仍是安全边界的一部分。插件若使用未声明权限、直接调用 Shell、覆盖鉴权代码或逃逸自身目录，应被拒绝。

## Shell 规则

- Shell 文件必须位于 `scripts/`，文件名只能包含字母、数字、点、下划线和连字符。
- 没有 `shell.execute` grant 时，MWEF Hook Runner 拒绝执行。
- 不允许插件通过 Web 参数拼接 Shell 命令。
- 不允许使用 `mtd write`、`mtd erase`、`dd` 写块设备、Bootloader 修改或固件分区操作。
- 服务控制还必须声明 `service.control`。

## 恢复

- 插件移除：移动到插件目录的 `.recovery/`。
- 插件升级失败：恢复上一版本并重新 patch。
- 框架自更新失败：恢复旧框架；更新成功后旧核心保留在 `/data/other_vol/xqext-framework-recovery/`。
- 框架卸载：解除挂载、移除启动项，并把 `/data/other_vol/xqext` 重命名保存。
- 原始 `/www` 与 `/usr/lib/lua/luci` SquashFS 文件不被修改。
