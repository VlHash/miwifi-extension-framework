module("luci.controller.api.mwef", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local json = require "luci.json"

local BASE = "/data/other_vol/xqext"
local VERSION = "0.2.5"
local DEFAULT_PLUGIN_DIR = BASE .. "/plugins"
local LANGUAGE_FILE = BASE .. "/config/language"
local PLUGIN_DIR_FILE = BASE .. "/config/plugin-directory"
local HELPER = BASE .. "/scripts/mwef-pluginctl.sh"
local UPDATE_HELPER = BASE .. "/scripts/mwef-update.sh"
local UPDATE_MANIFEST_FILE = "/tmp/mwef-framework-update.json"
local MAX_UPLOAD = 8 * 1024 * 1024
local MAX_FRAMEWORK_UPLOAD = 16 * 1024 * 1024
local MAX_FRAMEWORK_CHUNK = 32 * 1024
local UPDATE_MANIFEST_URLS = {
    "https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/framework.json",
    "https://testingcf.jsdelivr.net/gh/VlHash/miwifi-extension-framework@plugins/framework.json"
}

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

local function query_value(name)
    local query = os.getenv("QUERY_STRING") or ""
    for key, value in query:gmatch("([^&=]+)=([^&]*)") do
        if key == name then return value end
    end
    return nil
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

local function run_update_helper(...)
    local command = { shell_quote(UPDATE_HELPER) }
    for index = 1, select("#", ...) do
        command[#command + 1] = shell_quote(select(index, ...))
    end
    local result = os.execute(table.concat(command, " ") .. " >/tmp/mwef-update-helper.log 2>&1")
    return result == 0 or result == true
end

local function valid_version(value)
    return type(value) == "string"
        and #value >= 5 and #value <= 32
        and value:match("^%d+%.%d+%.%d+[0-9A-Za-z%.%-]*$") ~= nil
end

local function version_parts(value)
    if not valid_version(value) then return nil end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compare_versions(left, right)
    local a, b = version_parts(left), version_parts(right)
    if not a or not b then return nil end
    for index = 1, 3 do
        if a[index] < b[index] then return -1 end
        if a[index] > b[index] then return 1 end
    end
    return 0
end

local function valid_archive_url(value)
    if type(value) ~= "string" or #value > 360 then return false end
    local direct = "^https://github%.com/VlHash/miwifi%-extension%-framework/releases/download/v[0-9A-Za-z%.%-]+/mwef%-[0-9A-Za-z%.%-]+%.tar%.gz$"
    local mirror = "^https://ghfast%.top/https://github%.com/VlHash/miwifi%-extension%-framework/releases/download/v[0-9A-Za-z%.%-]+/mwef%-[0-9A-Za-z%.%-]+%.tar%.gz$"
    return value:match(direct) ~= nil or value:match(mirror) ~= nil
end

local function validate_update_manifest(value)
    if type(value) ~= "table" or tonumber(value.schemaVersion) ~= 1 or value.framework ~= "mwef" then
        return nil, "Invalid framework update manifest"
    end
    if value.author ~= "VlHash" then return nil, "Invalid framework update author" end
    if not valid_version(value.version) then return nil, "Invalid framework update version" end
    if type(value.tag) ~= "string" or not value.tag:match("^v[0-9A-Za-z%.%-]+$") then
        return nil, "Invalid framework release tag"
    end
    if type(value.archive) ~= "table" then return nil, "Framework archive metadata is missing" end
    local archive = value.archive
    if archive.filename ~= "mwef-" .. value.version .. ".tar.gz" then
        return nil, "Framework archive filename does not match its version"
    end
    if type(archive.sha256) ~= "string" or #archive.sha256 ~= 64 or archive.sha256:match("[^a-fA-F0-9]") then
        return nil, "Invalid framework archive SHA-256"
    end
    archive.size = tonumber(archive.size)
    if not archive.size or archive.size < 1 or archive.size > MAX_FRAMEWORK_UPLOAD or archive.size % 1 ~= 0 then
        return nil, "Invalid framework archive size"
    end
    if type(archive.urls) ~= "table" or #archive.urls < 1 or #archive.urls > 4 then
        return nil, "Framework archive URLs are missing"
    end
    for _, url in ipairs(archive.urls) do
        if not valid_archive_url(url) then return nil, "Untrusted framework archive URL" end
    end
    if value.notesUrl ~= nil then
        if type(value.notesUrl) ~= "string"
            or not value.notesUrl:match("^https://github%.com/VlHash/miwifi%-extension%-framework/releases/tag/v[0-9A-Za-z%.%-]+$") then
            return nil, "Invalid framework release notes URL"
        end
    end
    return value
end

local function fetch_update_manifest()
    local last_message = "Unable to download the framework update manifest"
    for _, url in ipairs(UPDATE_MANIFEST_URLS) do
        if run_update_helper("fetch-manifest", url) then
            local manifest, message = validate_update_manifest(decode_json(UPDATE_MANIFEST_FILE))
            if manifest then return manifest end
            last_message = message or last_message
        else
            last_message = trim(read_file("/tmp/mwef-update-helper.log")) or last_message
        end
    end
    return nil, last_message
end

local function validate_framework_package(root)
    local manifest = decode_json(root .. "/manifest.json")
    if type(manifest) ~= "table" or manifest.id ~= "mwef" then return nil, "Archive is not an MWEF framework release" end
    if manifest.author ~= "VlHash" then return nil, "Invalid framework author" end
    if not valid_version(manifest.version) then return nil, "Invalid framework version" end
    return manifest
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

local function framework_release_record(manifest, source)
    return {
        version = manifest.version,
        author = manifest.author,
        source = source,
        currentVersion = VERSION,
        comparison = compare_versions(manifest.version, VERSION)
    }
end

local function stage_framework_archive(token, archive, size)
    if not run_update_helper("inspect", archive, token, "", "") then
        os.remove(archive)
        return respond({ code = 400, message = trim(read_file("/tmp/mwef-update-helper.log")) or "Invalid framework package" }, 400)
    end
    local pending = "/data/other_vol/.mwef-framework-pending-" .. token
    local manifest, message = validate_framework_package(pending)
    if not manifest then
        run_update_helper("discard", token)
        return respond({ code = 400, message = message }, 400)
    end
    local comparison = compare_versions(manifest.version, VERSION)
    if comparison == nil or comparison < 0 then
        run_update_helper("discard", token)
        return respond({ code = 400, message = "Uploaded framework version is older than the installed version" }, 400)
    end
    local package_info = read_lines(pending .. "/.mwef-package-info")
    respond({
        code = 0,
        pendingToken = token,
        release = framework_release_record(manifest, "upload"),
        sha256 = package_info[2],
        size = tonumber(package_info[3]) or size
    })
end

local function handle_framework_check()
    local manifest, message = fetch_update_manifest()
    if not manifest then return respond({ code = 502, message = message }, 500) end
    respond({
        code = 0,
        currentVersion = VERSION,
        latestVersion = manifest.version,
        updateAvailable = compare_versions(manifest.version, VERSION) == 1,
        channel = manifest.channel or "pre-release",
        tag = manifest.tag,
        notesUrl = manifest.notesUrl,
        publishedAt = manifest.publishedAt
    })
end

local function handle_framework_upload()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = random_token()
    local archive = "/tmp/mwef-framework-upload-" .. token .. ".tar.gz"
    local handle
    local size = 0
    local failed = false
    http.setfilehandler(function(meta, chunk, eof)
        if meta and meta.name == "release" and not handle and not failed then
            handle = io.open(archive, "wb")
            if not handle then failed = true end
        end
        if handle and chunk and #chunk > 0 then
            size = size + #chunk
            if size > MAX_FRAMEWORK_UPLOAD then
                failed = true
            elseif not failed then
                handle:write(chunk)
            end
        end
        if eof and handle then handle:close(); handle = nil end
    end)
    http.formvalue("release")
    if handle then handle:close() end
    if failed or size == 0 or size > MAX_FRAMEWORK_UPLOAD then
        os.remove(archive)
        return respond({ code = 400, message = "Framework package is empty or exceeds 16 MiB" }, 400)
    end
    stage_framework_archive(token, archive, size)
end

local function upload_session_path(token)
    return "/tmp/mwef-framework-upload-session-" .. token
end

local function read_upload_session(token)
    local values = read_lines(upload_session_path(token))
    local expected, received, sequence = tonumber(values[1]), tonumber(values[2]), tonumber(values[3])
    if not expected or not received or not sequence then return nil end
    return { expected = expected, received = received, sequence = sequence }
end

local function write_upload_session(token, session)
    return write_atomic(upload_session_path(token), table.concat({
        tostring(session.expected), tostring(session.received), tostring(session.sequence), ""
    }, "\n"))
end

local function discard_upload_session(token)
    os.remove(upload_session_path(token))
    os.remove("/tmp/mwef-framework-upload-" .. token .. ".tar.gz")
end

local function handle_framework_upload_start()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local size = tonumber(http.formvalue("size") or "")
    local filename = http.formvalue("filename") or ""
    if not size or size % 1 ~= 0 or size < 1 or size > MAX_FRAMEWORK_UPLOAD then
        return respond({ code = 400, message = "Framework package is empty or exceeds 16 MiB" }, 400)
    end
    local lower = filename:lower()
    if #filename > 160 or (lower:sub(-7) ~= ".tar.gz" and lower:sub(-4) ~= ".tgz") then
        return respond({ code = 400, message = "Framework package must be a .tar.gz or .tgz file" }, 400)
    end
    local token = random_token()
    local archive = "/tmp/mwef-framework-upload-" .. token .. ".tar.gz"
    local handle = io.open(archive, "wb")
    if not handle then return respond({ code = 500, message = "Unable to prepare framework upload" }, 500) end
    handle:close()
    if not write_upload_session(token, { expected = size, received = 0, sequence = 0 }) then
        discard_upload_session(token)
        return respond({ code = 500, message = "Unable to prepare framework upload" }, 500)
    end
    respond({ code = 0, uploadToken = token, chunkSize = MAX_FRAMEWORK_CHUNK })
end

local function handle_framework_upload_chunk()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = query_value("token") or ""
    local sequence = tonumber(query_value("sequence") or "")
    if not token:match("^%d+%-[a-fA-F0-9]+$") or not sequence or sequence % 1 ~= 0 then
        return respond({ code = 400, message = "Invalid upload chunk" }, 400)
    end
    local session = read_upload_session(token)
    if not session or sequence ~= session.sequence then
        return respond({ code = 400, message = "Upload session expired or chunk order is invalid" }, 400)
    end
    local archive = "/tmp/mwef-framework-upload-" .. token .. ".tar.gz"
    local handle
    local chunk_size = 0
    local failed = false
    http.setfilehandler(function(meta, chunk, eof)
        if meta and meta.name == "chunk" and not handle and not failed then
            handle = io.open(archive, "ab")
            if not handle then failed = true end
        end
        if handle and chunk and #chunk > 0 then
            chunk_size = chunk_size + #chunk
            if chunk_size > MAX_FRAMEWORK_CHUNK or session.received + chunk_size > session.expected then
                failed = true
            elseif not failed then
                handle:write(chunk)
            end
        end
        if eof and handle then handle:close(); handle = nil end
    end)
    http.formvalue("chunk")
    if handle then handle:close() end
    if failed or chunk_size < 1 or chunk_size > MAX_FRAMEWORK_CHUNK then
        discard_upload_session(token)
        return respond({ code = 400, message = "Framework upload chunk is invalid" }, 400)
    end
    session.received = session.received + chunk_size
    session.sequence = session.sequence + 1
    if not write_upload_session(token, session) then
        discard_upload_session(token)
        return respond({ code = 500, message = "Unable to record framework upload progress" }, 500)
    end
    respond({ code = 0, received = session.received, complete = session.received == session.expected })
end

local function handle_framework_upload_finish()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = http.formvalue("token") or ""
    if not token:match("^%d+%-[a-fA-F0-9]+$") then return respond({ code = 400, message = "Invalid upload token" }, 400) end
    local session = read_upload_session(token)
    if not session or session.received ~= session.expected then
        discard_upload_session(token)
        return respond({ code = 400, message = "Framework upload is incomplete" }, 400)
    end
    os.remove(upload_session_path(token))
    stage_framework_archive(token, "/tmp/mwef-framework-upload-" .. token .. ".tar.gz", session.received)
end

local function handle_framework_discard()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = http.formvalue("token") or ""
    if not token:match("^%d+%-[a-fA-F0-9]+$") then return respond({ code = 400, message = "Invalid pending token" }, 400) end
    discard_upload_session(token)
    if not run_update_helper("discard", token) then
        return respond({ code = 500, message = trim(read_file("/tmp/mwef-update-helper.log")) or "Unable to discard package" }, 500)
    end
    respond({ code = 0 })
end

local function apply_framework_token(token, expected_version, source)
    local pending = "/data/other_vol/.mwef-framework-pending-" .. token
    local manifest, message = validate_framework_package(pending)
    if not manifest then return nil, message or "Pending framework package expired" end
    if expected_version and manifest.version ~= expected_version then
        run_update_helper("discard", token)
        return nil, "Downloaded framework version does not match the update manifest"
    end
    local comparison = compare_versions(manifest.version, VERSION)
    if comparison == nil or comparison < 0 then
        run_update_helper("discard", token)
        return nil, "Framework downgrade is not allowed"
    end
    if not run_update_helper("apply", token) then
        return nil, trim(read_file("/tmp/mwef-update-helper.log")) or "Framework update failed"
    end
    return {
        code = 0,
        updated = true,
        source = source,
        previousVersion = VERSION,
        version = manifest.version
    }
end

local function handle_framework_apply()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local token = http.formvalue("token") or ""
    if not token:match("^%d+%-[a-fA-F0-9]+$") then return respond({ code = 400, message = "Invalid pending token" }, 400) end
    local result, message = apply_framework_token(token, nil, "upload")
    if not result then return respond({ code = 500, message = message }, 500) end
    respond(result)
end

local function handle_framework_online()
    if not is_post() then return respond({ code = 405, message = "POST required" }, 400) end
    local manifest, message = fetch_update_manifest()
    if not manifest then return respond({ code = 502, message = message }, 500) end
    local comparison = compare_versions(manifest.version, VERSION)
    if comparison == nil or comparison < 0 then
        return respond({ code = 400, message = "Online release is older than the installed framework" }, 400)
    end
    local token = random_token()
    local downloaded = false
    local last_message = "Unable to download the framework release"
    for _, url in ipairs(manifest.archive.urls) do
        if run_update_helper("download", url, manifest.archive.sha256, tostring(manifest.archive.size), token) then
            downloaded = true
            break
        end
        last_message = trim(read_file("/tmp/mwef-update-helper.log")) or last_message
    end
    if not downloaded then return respond({ code = 502, message = last_message }, 500) end
    local result
    result, message = apply_framework_token(token, manifest.version, "online")
    if not result then return respond({ code = 500, message = message }, 500) end
    respond(result)
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
    if action == "framework-check" then return handle_framework_check() end
    if action == "framework-upload" then return handle_framework_upload() end
    if action == "framework-upload-start" then return handle_framework_upload_start() end
    if action == "framework-upload-chunk" then return handle_framework_upload_chunk() end
    if action == "framework-upload-finish" then return handle_framework_upload_finish() end
    if action == "framework-apply" then return handle_framework_apply() end
    if action == "framework-discard" then return handle_framework_discard() end
    if action == "framework-online" then return handle_framework_online() end
    if action == "settings" then return handle_settings() end
    if action == "enable" or action == "disable" or action == "remove" or action == "permissions" then
        return handle_plugin_action(action)
    end
    respond({ code = 404, message = "Unknown action" }, 400)
end
