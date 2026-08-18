module("luci.controller.web.mwef_manage", package.seeall)

function index()
    local page = entry(
        {"web", "xqextapi"},
        call("dispatch"),
        nil
    )
    page.leaf = true
end

function dispatch()
    require("luci.controller.api.mwef").dispatch()
end
