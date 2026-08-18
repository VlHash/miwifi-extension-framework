module("luci.controller.web.mwef_system", package.seeall)

function index()
    local system = entry(
        {"web", "xqext", "system"},
        template("web/xqext/system"),
        _("系统信息"),
        10
    )
    system.leaf = true

    local page = entry(
        {"web", "xqextstatus"},
        call("status"),
        nil
    )
    page.leaf = true
end

function status()
    require("luci.controller.api.mwef_system").status()
end
