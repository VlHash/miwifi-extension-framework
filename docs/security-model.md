# MWEF 权限与安全模型

## 目标

MWEF 在不修改只读固件、不写 MTD 的前提下，为插件提供可审查、可撤销的安装与运行机制。

## 安装边界

1. 上传包只写入 `/tmp`，上限 8 MiB。
2. 解包前检查每个 tar 路径，拒绝绝对路径、路径穿越和反斜杠路径。
3. 解包后拒绝符号链接和特殊文件。
4. Manifest 通过 Schema v1 约束后才展示权限确认。
5. 安装使用同一文件系统内的 staging 目录；升级前将旧版本移入 `.recovery`。
6. 插件启停后重建生成层，再重新挂载 OverlayFS。

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
- 框架卸载：解除挂载、移除启动项，并把 `/data/other_vol/xqext` 重命名保存。
- 原始 `/www` 与 `/usr/lib/lua/luci` SquashFS 文件不被修改。
