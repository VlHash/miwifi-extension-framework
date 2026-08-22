module("luci.controller.api.mwef", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local json = require "luci.json"

local BASE = "/data/other_vol/xqext"
local VERSION = "0.2.4"
local DEFAULT_PLUGIN_DIR = BASE .. "/plugins"
local LANGUAGE_FILE = BASE .. "/config/language"
local PLUGIN_DIR_FILE = BASE .. "/config/plugin-directory"
local HELPER = BASE .. "/scripts/mwef-pluginctl.sh"
local MAX_UPLOAD = 8 * 1024 * 1024

local allowed_permissions = {
    ["system.read"] = true,
    ["filesystem.read"] = true,
    ["filesystem.write"] = true,
    ["network.client"] = true,
    ["service.control"] = true,
    ["shell.execute"] = true
}

local function trim(value)
    return value and value:match("^%s*(.-)%s*$") or nil
end

local function read_file(path, binary)
    local handle = io.open(path, binary and "rb" or "r")
    if not handle then return nil end
    local value = handle:read("*a")
    handle:close()
    return value
end

local function write_atomic(path, value)
    local temporary = path .. ".tmp"
    local handle = io.open(temporary, "w")
    if not handle then return false end
    handle:write(value)
    handle:close()
    if os.rename(temporary, path) then return true end
    os.remove(temporary)
    return false
end

local function decode_json(path)
    local content = read_file(path)
    if not content then return nil end
    local ok, value = pcall(json.decode, content)
    return ok and value or nil
end

local function valid_session()
    local request_uri = os.getenv("REQUEST_URI") or ""
    local token = request_uri:match(";stok=([a-fA-F0-9]+)")
    if not token or #token < 16 or #token > 64 then return false end
    local session = fs.stat("/tmp/luci-sessions/" .. token)
    return session and session.type == "reg" or false
end

local function respond(data, status)
    http.header("Cache-Control", "no-store")
    http.header("X-Content-Type-Options", "nosniff")
    if status then http.status(status, status == 400 and "Bad Request" or "Internal Server Error") end
    http.prepare_content("application/json")
    http.write(json.encode(data))
end

local function is_post()
    return (os.getenv("REQUEST_METHOD") or "GET") == "POST"
end

local function valid_plugin_id(value)
    return type(value) == "string" and value:match("^[a-z][a-z0-9%-_]*$") and #value <= 48
end

local function valid_plugin_directory(value)
    if type(value) ~= "string" or #value < 7 or #value > 160 then return false end
    if not value:match("^/data/[A-Za-z0-9%._/%-]+$") then return false end
    if value:find("//", 1, true) or value:find("..", 1, true) then return false end
    return true
end

local function settings()
    local language = trim(read_file(LANGUAGE_FILE))
    if language ~= "en" and language ~= "zh-CN" then language = "zh-CN" end
    local plugin_dir = trim(read_file(PLUGIN_DIR_FILE))
    if not valid_plugin_directory(plugin_dir) then plugin_dir = DEFAULT_PLUGIN_DIR end
    return { language = language, pluginDirectory = plugin_dir }
end

local function localized_name(manifest, language)
    if type(manifest.name) == "table" then
        return manifest.name[language] or manifest.name["zh-CN"] or manifest.name.en or manifest.id
    end
    return manifest.name or manifest.id
end

local function list_to_set(values)
    local result = {}
    if type(values) == "table" then
        for _, value in ipairs(values) do result[value] = true end
    end
    return result
end

local function read_lines(path)
    local result = {}
    local content = read_file(path) or ""
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if line and line ~= "" then result[#result + 1] = line end
    end
    return result
end

local function plugin_record(path, id, language)
    local manifest = decode_json(path .. "/mwef-plugin.json")
    if type(manifest) ~= "table" or manifest.id ~= id then return nil end
    return {
        id = id,
        name = localized_name(manifest, language),
        version = tostring(manifest.version or "--"),
        description = type(manifest.description) == "table"
            and (manifest.description[language] or manifest.description["zh-CN"] or manifest.description.en)
            or manifest.description,
        author = manifest.author,
        enabled = fs.stat(path .. "/.enabled") ~= nil,
        builtin = fs.stat(path .. "/.builtin") ~= nil,
        permissions = type(manifest.permissions) == "table" and manifest.permissions or {},
        grants = read_lines(path .. "/.grants")
    }
end

local function list_plugins(current)
    local result = {}
    local iterator = fs.dir(current.pluginDirectory)
    if iterator then
        for id in iterator do
            if valid_plugin_id(id) then
                local stat = fs.stat(current.pluginDirectory .. "/" .. id)
                if stat and stat.type == "dir" then
                    local item = plugin_record(current.pluginDirectory .. "/" .. id, id, current.language)
                    if item then result[#result + 1] = item end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.builtin ~= b.builtin then return a.builtin end
        return a.id < b.id
    end)
    return result
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_helper(...)
    local command = { shell_quote(HELPER) }
    for index = 1, select("#", ...) do
        command[#command + 1] = shell_quote(select(index, ...))
    end
    local result = os.execute(table.concat(command, " ") .. " >/tmp/mwef-helper.log 2>&1")
    return result == 0 or result == true
end

local function validate_manifest(manifest)
    if type(manifest) ~= "table" or tonumber(manifest.schemaVersion) ~= 1 then
        return nil, "Unsupported or missing schemaVersion"
    end
    if not valid_plugin_id(manifest.id) then return nil, "Invalid plugin id" end
    if type(manifest.version) ~= "string" or #manifest.version > 32 then return nil, "Invalid version" end
    if type(manifest.name) ~= "string" and type(manifest.name) ~= "table" then return nil, "Invalid name" end
    if type(manifest.author) ~= "string" or #manifest.author < 1 or #manifest.author > 80 then return nil, "Invalid author" end
    if manifest.permissions ~= nil and type(manifest.permissions) ~= "table" then
        return nil, "permissions must be an array"
    end
    for _, permission in ipairs(manifest.permissions or {}) do
        if not allowed_permissions[permission] then return nil, "Unknown permission: " .. tostring(permission) end
    end
    return manifest
end

local function validate_pending_layout(root, manifest)
    local namespace = root .. "/overlay/www/xqext/plugins"
    local iterator = fs.dir(namespace)
    if iterator then
        for entry in iterator do
            if entry ~= manifest.id then
                return false, "Static assets must use overlay/www/xqext/plugins/" .. manifest.id
            end
        end
    end
    return true
end

local function random_token()
    local random_handle = io.open("/dev/urandom", "rb")
    local random = random_handle and random_handle:read(8) or nil
    if random_handle then random_handle:close() end
    local suffix = ""
    if random then
        for index = 1, math.min(8, #random) do suffix = suffix .. string.format("%02x", random:byte(index)) end
    end
    return tostring(os.time()) .. "-" .. (suffix ~= "" and suffix or tostring(math.random(100000, 999999)))
end

local function status_payload()
    local current = settings()
    return {
        code = 0,
        framework = {
            id = "mwef",
            name = "MiWiFi-Extension-Framework",
            shortName = "MWEF",
            version = VERSION,
            legacyId = "xqext"
        },
        settings = current,
        permissions = {
            "system.read", "filesystem.read", "filesystem.write",
            "network.client", "service.control", "shell.execute"
        },
        plugins = list_plugins(current)
    }
end

local function handle_upload()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = random_token()
    local archive = "/tmp/mwef-upload-" .. token .. ".tar.gz"
    local handle
    local size = 0
    local failed = false
    http.setfilehandler(function(meta, chunk, eof)
        if meta and meta.name == "package" and not handle and not failed then
            handle = io.open(archive, "wb")
            if not handle then failed = true end
        end
        if handle and chunk and #chunk > 0 then
            size = size + #chunk
            if size > MAX_UPLOAD then
                failed = true
            elseif not failed then
                handle:write(chunk)
            end
        end
        if eof and handle then handle:close(); handle = nil end
    end)
    http.formvalue("package")
    if handle then handle:close() end
    if failed or size == 0 or size > MAX_UPLOAD then
        os.remove(archive)
        return respond({ code = 400, message = "Package is empty or exceeds 8 MiB" }, 400)
    end
    if not run_helper("inspect", archive, token) then
        os.remove(archive)
        return respond({ code = 400, message = trim(read_file("/tmp/mwef-helper.log")) or "Invalid package" }, 400)
    end
    local manifest, message = validate_manifest(decode_json("/tmp/mwef-pending-" .. token .. "/mwef-plugin.json"))
    if not manifest then
        run_helper("discard", token)
        return respond({ code = 400, message = message }, 400)
    end
    local layout_ok, layout_message = validate_pending_layout("/tmp/mwef-pending-" .. token, manifest)
    if not layout_ok then
        run_helper("discard", token)
        return respond({ code = 400, message = layout_message }, 400)
    end
    local current = settings()
    respond({
        code = 0,
        pendingToken = token,
        plugin = {
            id = manifest.id,
            name = localized_name(manifest, current.language),
            version = manifest.version,
            description = manifest.description,
            permissions = manifest.permissions or {}
        }
    })
end

local function requested_grants(value, requested)
    local requested_set = list_to_set(requested)
    local result = {}
    local seen = {}
    for item in tostring(value or ""):gmatch("[^,]+") do
        item = trim(item)
        if item and requested_set[item] and allowed_permissions[item] and not seen[item] then
            result[#result + 1] = item
            seen[item] = true
        end
    end
    return result
end

local function handle_install()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = http.formvalue("token") or ""
    if not token:match("^%d+%-[a-fA-F0-9]+$") then return respond({ code = 400, message = "Invalid pending token" }, 400) end
    local manifest, message = validate_manifest(decode_json("/tmp/mwef-pending-" .. token .. "/mwef-plugin.json"))
    if not manifest then return respond({ code = 400, message = message or "Pending package expired" }, 400) end
    local layout_ok, layout_message = validate_pending_layout("/tmp/mwef-pending-" .. token, manifest)
    if not layout_ok then return respond({ code = 400, message = layout_message }, 400) end
    local grants = requested_grants(http.formvalue("grants"), manifest.permissions)
    local current = settings()
    if not run_helper("install", token, current.pluginDirectory, manifest.id, table.concat(grants, ",")) then
        return respond({ code = 500, message = trim(read_file("/tmp/mwef-helper.log")) or "Install failed" }, 500)
    end
    respond(status_payload())
end

local function handle_settings()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local language = http.formvalue("language") or ""
    local plugin_dir = trim(http.formvalue("pluginDirectory") or "")
    if language ~= "en" and language ~= "zh-CN" then return respond({ code = 400, message = "Unsupported language" }, 400) end
    if not valid_plugin_directory(plugin_dir) then return respond({ code = 400, message = "Plugin directory must be a safe path below /data" }, 400) end
    local current = settings()
    if plugin_dir ~= current.pluginDirectory and not run_helper("copy-directory", current.pluginDirectory, plugin_dir) then
        return respond({ code = 500, message = "Unable to prepare plugin directory" }, 500)
    end
    if not write_atomic(LANGUAGE_FILE, language .. "\n") or not write_atomic(PLUGIN_DIR_FILE, plugin_dir .. "\n") then
        return respond({ code = 500, message = "Unable to save settings" }, 500)
    end
    if not run_helper("repatch") then return respond({ code = 500, message = "Settings saved but repatch failed" }, 500) end
    respond(status_payload())
end

local function handle_plugin_action(action)
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local id = http.formvalue("id") or ""
    if not valid_plugin_id(id) then return respond({ code = 400, message = "Invalid plugin id" }, 400) end
    if id == "system" and (action == "disable" or action == "remove") then
        return respond({ code = 400, message = "The built-in system plugin cannot be disabled or removed" }, 400)
    end
    local current = settings()
    local plugin = plugin_record(current.pluginDirectory .. "/" .. id, id, current.language)
    if not plugin then return respond({ code = 400, message = "Plugin not found" }, 400) end
    local argument = ""
    if action == "permissions" then
        argument = table.concat(requested_grants(http.formvalue("grants"), plugin.permissions), ",")
    end
    if not run_helper(action, current.pluginDirectory, id, argument) then
        return respond({ code = 500, message = trim(read_file("/tmp/mwef-helper.log")) or "Plugin action failed" }, 500)
    end
    respond(status_payload())
end

function index()
    -- The authenticated endpoint is registered by luci.controller.web.mwef_manage.
end

function dispatch()
    if not valid_session() then return respond({ code = 401, message = "Invalid token" }, 400) end
    local query = os.getenv("QUERY_STRING") or ""
    local action = query:match("^action=([a-z%-]+)") or query:match("&action=([a-z%-]+)") or "status"
    if action == "status" then return respond(status_payload()) end
    if action == "upload" then return handle_upload() end
    if action == "install" then return handle_install() end
    if action == "settings" then return handle_settings() end
    if action == "enable" or action == "disable" or action == "remove" or action == "permissions" then
        return handle_plugin_action(action)
    end
    respond({ code = 404, message = "Unknown action" }, 400)
end
