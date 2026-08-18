module("luci.controller.web.mwef_hello", package.seeall)

function index()
    local page = entry(
        {"web", "xqext", "hello_mwef"},
        template("web/xqext/hello_mwef"),
        _("Hello MWEF"),
        100
    )
    page.leaf = true
end
