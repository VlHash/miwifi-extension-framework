module("luci.controller.web.xqext", package.seeall)

function index()
    local root = entry(
        {"web", "xqext"},
        alias("web", "xqext", "system"),
        _("扩展设置"),
        95
    )
    root.index = true

    local framework = entry(
        {"web", "xqext", "framework"},
        template("web/xqext/framework"),
        _("框架设置"),
        90
    )
    framework.leaf = true
end
