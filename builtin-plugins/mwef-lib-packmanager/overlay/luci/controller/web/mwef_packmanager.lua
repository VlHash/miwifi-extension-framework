module("luci.controller.web.mwef_packmanager", package.seeall)

function index()
    local page = entry(
        {"web", "xqext", "packmanager"},
        template("web/xqext/packmanager"),
        _("插件管理"),
        20
    )
    page.leaf = true

    local api = entry(
        {"web", "xqextpackmanager"},
        call("dispatch"),
        nil
    )
    api.leaf = true
end

function dispatch()
    require("luci.controller.api.mwef_packmanager").dispatch()
end
