module("luci.controller.api.mwef_packmanager", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local json = require "luci.json"

local BASE = "/data/other_vol/xqext"
local PLUGIN_ID = "mwef-lib-packmanager"
local DEFAULT_PLUGIN_DIR = BASE .. "/plugins"
local PLUGIN_DIR_FILE = BASE .. "/config/plugin-directory"
local LANGUAGE_FILE = BASE .. "/config/language"
local SOURCE_DIRECTORY = BASE .. "/config/mwef-lib-packmanager"
local SOURCE_FILE = SOURCE_DIRECTORY .. "/sources.json"
local CORE_HELPER = BASE .. "/scripts/mwef-pluginctl.sh"
local DEFAULT_INDEX_URL = "https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.json"
local FALLBACK_INDEX_URL = "https://cdn.jsdelivr.net/gh/VlHash/miwifi-extension-framework@plugins/index.json"
local DEFAULT_GITHUB_PROXY = ""
local INDEX_SCHEMA_URL = "https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.schema.json"
local MAX_ARCHIVE_SIZE = 8 * 1024 * 1024
local MAX_PLUGINS = 512
local parse_semver
local compare_versions

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

local function decode_json(path)
    local content = read_file(path)
    if not content then return nil end
    local ok, value = pcall(json.decode, content)
    return ok and value or nil
end

local function write_atomic(path, value)
    local temporary = path .. ".tmp." .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
    local handle = io.open(temporary, "w")
    if not handle then return false end
    handle:write(value)
    handle:close()
    if os.rename(temporary, path) then return true end
    os.remove(temporary)
    return false
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
    if status then
        local labels = { [400] = "Bad Request", [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed", [502] = "Bad Gateway" }
        http.status(status, labels[status] or "Internal Server Error")
    end
    http.prepare_content("application/json")
    http.write(json.encode(data))
end

local function fail(message, status)
    return respond({ code = status or 400, message = message }, status or 400)
end

local function is_post()
    return (os.getenv("REQUEST_METHOD") or "GET") == "POST"
end

local function valid_plugin_id(value)
    return type(value) == "string" and value:match("^[a-z][a-z0-9_-]*$") ~= nil and #value <= 48
end

local function valid_plugin_directory(value)
    if type(value) ~= "string" or #value < 7 or #value > 160 then return false end
    if not value:match("^/data/[A-Za-z0-9%._/%-]+$") then return false end
    return not value:find("//", 1, true) and not value:find("..", 1, true)
end

local function plugin_directory()
    local value = trim(read_file(PLUGIN_DIR_FILE))
    return valid_plugin_directory(value) and value or DEFAULT_PLUGIN_DIR
end

local function language()
    local value = trim(read_file(LANGUAGE_FILE))
    return value == "en" and "en" or "zh-CN"
end

local function localized(value, selected_language)
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return "" end
    return value[selected_language] or value["zh-CN"] or value.en or ""
end

local function valid_url(value, maximum)
    if type(value) ~= "string" or #value < 9 or #value > (maximum or 512) then return false end
    if not value:match("^https://") or value:find("[%z\1-\32\127]") then return false end
    return value:find("[^%w%._~:/?&=+@#,%%-]") == nil
end

local function valid_proxy(value)
    return value == "" or (valid_url(value, 256) and value:sub(-1) == "/")
end

local function source_settings()
    local value = decode_json(SOURCE_FILE)
    if type(value) ~= "table" or type(value.schemaVersion) ~= "number" or value.schemaVersion ~= 1
        or not valid_url(value.indexUrl) or not valid_proxy(value.githubProxy) then
        return { indexUrl = DEFAULT_INDEX_URL, githubProxy = DEFAULT_GITHUB_PROXY }
    end
    return { indexUrl = value.indexUrl, githubProxy = value.githubProxy }
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

local function list_to_set(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[value] = true end
    return result
end

local function missing_grants(required)
    local grants = list_to_set(read_lines(plugin_directory() .. "/" .. PLUGIN_ID .. "/.grants"))
    local missing = {}
    for _, permission in ipairs(required) do
        if not grants[permission] then missing[#missing + 1] = permission end
    end
    return missing
end

local function require_grants(required)
    local missing = missing_grants(required)
    if #missing == 0 then return true end
    fail("Required permissions have not been granted: " .. table.concat(missing, ", "), 403)
    return false
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_script(path, log_path, ...)
    local command = { shell_quote(path) }
    for index = 1, select("#", ...) do
        command[#command + 1] = shell_quote(select(index, ...))
    end
    local result = os.execute(table.concat(command, " ") .. " >" .. shell_quote(log_path) .. " 2>&1")
    return result == 0 or result == true
end

local function pack_helper()
    return plugin_directory() .. "/" .. PLUGIN_ID .. "/scripts/mwef-packmanager.sh"
end

local function pack_log(token)
    return "/tmp/mwef-packmanager-helper-" .. token .. ".log"
end

local function core_log(token)
    return "/tmp/mwef-packmanager-core-" .. token .. ".log"
end

local function run_pack_helper(token, ...)
    return run_script("/bin/sh", pack_log(token), pack_helper(), ...)
end

local function run_core_helper(token, ...)
    return run_script(CORE_HELPER, core_log(token), ...)
end

local function helper_error(path, fallback)
    local value = trim(read_file(path))
    if value then
        value = value:gsub("[\r\n]+", " ")
        if #value > 320 then value = value:sub(1, 320) end
    end
    return value or fallback
end

local function random_token()
    local handle = io.open("/dev/urandom", "rb")
    local bytes = handle and handle:read(8) or nil
    if handle then handle:close() end
    local suffix = ""
    if bytes then
        for index = 1, #bytes do suffix = suffix .. string.format("%02x", bytes:byte(index)) end
    end
    return tostring(os.time()) .. "-" .. (suffix ~= "" and suffix or tostring(math.random(100000, 999999)))
end

local function only_keys(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if not allowed[key] then return false end
    end
    return true
end

local function dense_array(value, maximum)
    if type(value) ~= "table" then return nil end
    local count, highest = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
        count = count + 1
        if key > highest then highest = key end
    end
    if count ~= highest or (maximum and count > maximum) then return nil end
    return count
end

local function valid_text(value, minimum, maximum)
    return type(value) == "string" and #value >= minimum and #value <= maximum
end

local function valid_date(value)
    return type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

local function validate_localized(value)
    local allowed = { en = true, ["zh-CN"] = true }
    return only_keys(value, allowed)
        and valid_text(value.en, 1, 256)
        and valid_text(value["zh-CN"], 1, 256)
end

local function validate_permissions(value)
    local count = dense_array(value)
    if not count then return false end
    local seen = {}
    for _, permission in ipairs(value) do
        if not allowed_permissions[permission] or seen[permission] then return false end
        seen[permission] = true
    end
    return true
end

local function validate_categories(value)
    if value == nil then return true end
    local count = dense_array(value, 16)
    if not count then return false end
    local seen = {}
    for _, category in ipairs(value) do
        if type(category) ~= "string" or #category > 32
            or not category:match("^[a-z][a-z0-9%-]*$") or seen[category] then return false end
        seen[category] = true
    end
    return true
end

local function validate_archive(value)
    local allowed = { url = true, sha256 = true, size = true }
    if not only_keys(value, allowed) or not valid_url(value.url) then return false end
    if type(value.sha256) ~= "string" or #value.sha256 ~= 64 or value.sha256:match("[^a-f0-9]") then return false end
    return type(value.size) == "number" and value.size % 1 == 0
        and value.size >= 1 and value.size <= MAX_ARCHIVE_SIZE
end

local function validate_index_plugin(value)
    local allowed = {
        id = true, name = true, description = true, version = true, author = true,
        license = true, mwef = true, permissions = true, archive = true,
        homepage = true, source = true, published = true, changelog = true, categories = true
    }
    if not only_keys(value, allowed) or not valid_plugin_id(value.id) then return false, "Invalid plugin id" end
    if not validate_localized(value.name) or not validate_localized(value.description) then
        return false, "Invalid localized plugin text: " .. value.id
    end
    if not valid_text(value.version, 1, 32) or not value.version:match("^[0-9A-Za-z][0-9A-Za-z%.+%-]*$") then
        return false, "Invalid plugin version: " .. value.id
    end
    if not parse_semver(value.version) then return false, "Unsupported semantic version: " .. value.id end
    if not valid_text(value.author, 1, 80) or not valid_text(value.license, 1, 32)
        or not valid_text(value.mwef, 1, 64) then return false, "Invalid plugin metadata: " .. value.id end
    local minimum = value.mwef:match("^>=(.+)$")
    if not minimum or not parse_semver(minimum) then return false, "Unsupported MWEF requirement: " .. value.id end
    if not validate_permissions(value.permissions) or not validate_archive(value.archive) then
        return false, "Invalid permissions or archive: " .. value.id
    end
    if not valid_url(value.homepage) or not valid_url(value.source) then
        return false, "Invalid plugin links: " .. value.id
    end
    if value.published ~= nil and not valid_date(value.published) then return false, "Invalid publish date: " .. value.id end
    if value.changelog ~= nil and not valid_url(value.changelog) then return false, "Invalid changelog: " .. value.id end
    if not validate_categories(value.categories) then return false, "Invalid categories: " .. value.id end
    return true
end

local function validate_index(value)
    local allowed = { ["$schema"] = true, schemaVersion = true, name = true, maintainer = true, updated = true, plugins = true }
    if not only_keys(value, allowed) or value["$schema"] ~= INDEX_SCHEMA_URL
        or type(value.schemaVersion) ~= "number" or value.schemaVersion ~= 1 then
        return nil, "Unsupported plugin index schema"
    end
    if not valid_text(value.name, 1, 80) or not valid_text(value.maintainer, 1, 80) or not valid_date(value.updated) then
        return nil, "Invalid plugin index metadata"
    end
    local count = dense_array(value.plugins, MAX_PLUGINS)
    if not count then return nil, "Plugin index must contain a valid array" end
    local seen = {}
    for _, plugin in ipairs(value.plugins) do
        local ok, message = validate_index_plugin(plugin)
        if not ok then return nil, message end
        if seen[plugin.id] then return nil, "Duplicate plugin id: " .. plugin.id end
        seen[plugin.id] = true
    end
    return value
end

local function load_index(index_url, token)
    local path = "/tmp/mwef-packmanager-index-" .. token .. ".json"
    os.remove(path)
    local downloaded = run_pack_helper(token, "fetch-index", index_url, token)
    if not downloaded and index_url == DEFAULT_INDEX_URL then
        os.remove(path)
        downloaded = run_pack_helper(token, "fetch-index", FALLBACK_INDEX_URL, token)
    end
    if not downloaded then
        local message = helper_error(pack_log(token), "Unable to download the plugin index")
        os.remove(path)
        os.remove(pack_log(token))
        return nil, message
    end
    local value = decode_json(path)
    os.remove(path)
    os.remove(pack_log(token))
    if not value then return nil, "The plugin index is not valid JSON" end
    return validate_index(value)
end

local function valid_semver_identifiers(value, prerelease)
    if value == "" or value:sub(1, 1) == "." or value:sub(-1) == "." or value:find("..", 1, true) then return false end
    for identifier in value:gmatch("[^.]+") do
        if not identifier:match("^[0-9A-Za-z%-]+$") then return false end
        if prerelease and identifier:match("^%d+$") and #identifier > 1 and identifier:sub(1, 1) == "0" then return false end
    end
    return true
end

parse_semver = function(value)
    if type(value) ~= "string" or #value < 5 or #value > 64 then return nil end
    local major, minor, patch, suffix = value:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major or (#major > 1 and major:sub(1, 1) == "0")
        or (#minor > 1 and minor:sub(1, 1) == "0") or (#patch > 1 and patch:sub(1, 1) == "0") then return nil end
    local prerelease, build = "", ""
    if suffix ~= "" then
        if suffix:sub(1, 1) == "-" then
            local rest = suffix:sub(2)
            local plus = rest:find("+", 1, true)
            if plus then prerelease, build = rest:sub(1, plus - 1), rest:sub(plus + 1)
            else prerelease = rest end
        elseif suffix:sub(1, 1) == "+" then
            build = suffix:sub(2)
        else
            return nil
        end
    end
    if prerelease ~= "" and not valid_semver_identifiers(prerelease, true) then return nil end
    if suffix:sub(1, 1) == "-" and prerelease == "" then return nil end
    if build ~= "" and not valid_semver_identifiers(build, false) then return nil end
    if suffix:find("+", 1, true) and build == "" then return nil end
    return { major = major, minor = minor, patch = patch, prerelease = prerelease }
end

local function compare_numeric_identifier(left, right)
    if #left < #right then return -1 end
    if #left > #right then return 1 end
    if left == right then return 0 end
    return left < right and -1 or 1
end

local function compare_prerelease(left, right)
    if left == right then return 0 end
    if left == "" then return 1 end
    if right == "" then return -1 end
    local left_parts, right_parts = {}, {}
    for value in left:gmatch("[^.]+") do left_parts[#left_parts + 1] = value end
    for value in right:gmatch("[^.]+") do right_parts[#right_parts + 1] = value end
    local maximum = #left_parts > #right_parts and #left_parts or #right_parts
    for index = 1, maximum do
        local a, b = left_parts[index], right_parts[index]
        if not a then return -1 end
        if not b then return 1 end
        local a_number, b_number = a:match("^%d+$") ~= nil, b:match("^%d+$") ~= nil
        if a_number and b_number then
            local comparison = compare_numeric_identifier(a, b)
            if comparison ~= 0 then return comparison end
        elseif a_number then
            return -1
        elseif b_number then
            return 1
        elseif a ~= b then
            return a < b and -1 or 1
        end
    end
    return 0
end

compare_versions = function(left, right)
    if left == right then return 0 end
    local a, b = parse_semver(left), parse_semver(right)
    if not a or not b then return nil end
    for _, key in ipairs({ "major", "minor", "patch" }) do
        local comparison = compare_numeric_identifier(a[key], b[key])
        if comparison ~= 0 then return comparison end
    end
    return compare_prerelease(a.prerelease, b.prerelease)
end

local function framework_version()
    local manifest = decode_json(BASE .. "/manifest.json")
    return type(manifest) == "table" and tostring(manifest.version or "0.0.0") or "0.0.0"
end

local function compatible_requirement(requirement)
    local minimum = type(requirement) == "string" and requirement:match("^>=(.+)$") or nil
    if not minimum or not parse_semver(minimum) then return false end
    local comparison = compare_versions(framework_version(), minimum)
    return comparison ~= nil and comparison >= 0
end

local function installed_plugins()
    local result, by_id = {}, {}
    local directory = plugin_directory()
    local iterator = fs.dir(directory)
    if iterator then
        for id in iterator do
            if valid_plugin_id(id) then
                local root = directory .. "/" .. id
                local manifest = decode_json(root .. "/mwef-plugin.json")
                if type(manifest) == "table" and manifest.id == id then
                    local builtin_marker = fs.stat(root .. "/.builtin")
                    local item = {
                        id = id,
                        name = localized(manifest.name, language()),
                        description = localized(manifest.description, language()),
                        version = tostring(manifest.version or "--"),
                        enabled = fs.stat(root .. "/.enabled") ~= nil,
                        builtin = builtin_marker and builtin_marker.type == "reg" or false,
                        permissions = type(manifest.permissions) == "table" and manifest.permissions or {},
                        grants = read_lines(root .. "/.grants")
                    }
                    result[#result + 1] = item
                    by_id[id] = item
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.builtin ~= b.builtin then return a.builtin end
        return a.id < b.id
    end)
    return result, by_id
end

local function catalog_payload(index, settings)
    local installed, installed_by_id = installed_plugins()
    local selected_language = language()
    local plugins = {}
    for _, value in ipairs(index.plugins) do
        local local_plugin = installed_by_id[value.id]
        local comparison = local_plugin and compare_versions(value.version, local_plugin.version) or nil
        local compatible = compatible_requirement(value.mwef)
        local status = "available"
        if local_plugin then
            if comparison and comparison > 0 then status = "update"
            elseif comparison and comparison < 0 then status = "newer"
            elseif comparison == 0 then status = "installed"
            else status = "unknown" end
        end
        plugins[#plugins + 1] = {
            id = value.id,
            name = localized(value.name, selected_language),
            description = localized(value.description, selected_language),
            version = value.version,
            author = value.author,
            license = value.license,
            mwef = value.mwef,
            permissions = value.permissions,
            size = value.archive.size,
            homepage = value.homepage,
            source = value.source,
            changelog = value.changelog,
            published = value.published,
            categories = value.categories or {},
            installedVersion = local_plugin and local_plugin.version or nil,
            builtin = local_plugin and local_plugin.builtin or false,
            enabled = local_plugin and local_plugin.enabled or nil,
            compatible = compatible,
            status = status,
            canInstall = compatible and not (local_plugin and local_plugin.builtin)
                and status ~= "newer" and status ~= "unknown"
        }
    end
    table.sort(plugins, function(a, b)
        local priority = { update = 1, available = 2, installed = 3, newer = 4, unknown = 5 }
        if priority[a.status] ~= priority[b.status] then return priority[a.status] < priority[b.status] end
        return a.id < b.id
    end)
    return {
        code = 0,
        settings = settings,
        source = { name = index.name, maintainer = index.maintainer, updated = index.updated },
        plugins = plugins,
        installed = installed
    }
end

local function find_index_plugin(index, id)
    for _, plugin in ipairs(index.plugins) do
        if plugin.id == id then return plugin end
    end
    return nil
end

local function permission_sets_equal(left, right)
    if dense_array(left) ~= dense_array(right) then return false end
    local expected = list_to_set(left)
    for _, permission in ipairs(right or {}) do
        if not expected[permission] then return false end
    end
    return true
end

local function validate_staged_plugin(root, entry)
    local manifest = decode_json(root .. "/mwef-plugin.json")
    if type(manifest) ~= "table" or manifest.id ~= entry.id or manifest.version ~= entry.version
        or manifest.author ~= entry.author or manifest.mwef ~= entry.mwef then
        return nil, "Downloaded package metadata does not match the plugin index"
    end
    if not validate_permissions(manifest.permissions or {}) or not permission_sets_equal(entry.permissions, manifest.permissions or {}) then
        return nil, "Downloaded package permissions do not match the plugin index"
    end
    local namespace = root .. "/overlay/www/xqext/plugins"
    local iterator = fs.dir(namespace)
    if iterator then
        for item in iterator do
            if item ~= manifest.id then return nil, "Downloaded package uses another static namespace" end
        end
    end
    return manifest
end

local function proxied_archive_url(url, proxy)
    if proxy == "" then return url end
    if url:match("^https://github%.com/") or url:match("^https://raw%.githubusercontent%.com/")
        or url:match("^https://codeload%.github%.com/") then
        local result = proxy .. url
        if valid_url(result) then return result end
        return nil
    end
    return url
end

local function handle_status()
    if not require_grants({ "filesystem.read" }) then return end
    local installed = installed_plugins()
    respond({
        code = 0,
        settings = source_settings(),
        frameworkVersion = framework_version(),
        installed = installed,
        missingPermissions = missing_grants({ "filesystem.read", "filesystem.write", "network.client", "shell.execute" })
    })
end

local function handle_catalog()
    if not require_grants({ "filesystem.read", "network.client", "shell.execute" }) then return end
    local settings = source_settings()
    local index, message = load_index(settings.indexUrl, random_token())
    if not index then return fail(message, 502) end
    respond(catalog_payload(index, settings))
end

local function handle_settings()
    if not is_post() then return fail("POST required", 405) end
    if not require_grants({ "filesystem.read", "filesystem.write", "network.client", "shell.execute" }) then return end
    local index_url = trim(http.formvalue("indexUrl") or "") or ""
    local github_proxy = trim(http.formvalue("githubProxy") or "") or ""
    if not valid_url(index_url) then return fail("Plugin index URL must be a safe HTTPS URL", 400) end
    if not valid_proxy(github_proxy) then return fail("GitHub proxy must be empty or a safe HTTPS prefix ending in /", 400) end
    local index, message = load_index(index_url, random_token())
    if not index then return fail(message, 502) end
    if not fs.mkdirr(SOURCE_DIRECTORY) then return fail("Unable to prepare the source settings directory", 500) end
    local serialized = json.encode({ schemaVersion = 1, indexUrl = index_url, githubProxy = github_proxy }) .. "\n"
    if not write_atomic(SOURCE_FILE, serialized) then return fail("Unable to save source settings", 500) end
    respond(catalog_payload(index, { indexUrl = index_url, githubProxy = github_proxy }))
end

local function handle_stage()
    if not is_post() then return fail("POST required", 405) end
    if not require_grants({ "filesystem.read", "filesystem.write", "network.client", "shell.execute" }) then return end
    local id = http.formvalue("id") or ""
    if not valid_plugin_id(id) then return fail("Invalid plugin id", 400) end
    local settings = source_settings()
    local token = random_token()
    local index, message = load_index(settings.indexUrl, token)
    if not index then return fail(message, 502) end
    local entry = find_index_plugin(index, id)
    if not entry then return fail("Plugin is no longer present in the selected source", 404) end
    if not compatible_requirement(entry.mwef) then return fail("Plugin requires a newer MWEF version", 400) end
    local _, installed_by_id = installed_plugins()
    local installed = installed_by_id[id]
    if installed and installed.builtin then return fail("Built-in plugins are updated with the framework", 400) end
    local comparison = installed and compare_versions(entry.version, installed.version) or nil
    if installed and comparison == nil then return fail("Installed and online versions cannot be compared safely", 400) end
    if comparison and comparison < 0 then return fail("Online package is older than the installed version", 400) end
    local archive_url = proxied_archive_url(entry.archive.url, settings.githubProxy)
    if not archive_url then return fail("GitHub proxy produces an invalid package URL", 400) end
    if not run_pack_helper(token, "download", archive_url, entry.archive.sha256, tostring(entry.archive.size), token) then
        local download_message = helper_error(pack_log(token), "Unable to download the plugin package")
        os.remove("/tmp/mwef-upload-" .. token .. ".tar.gz")
        os.remove(pack_log(token))
        return fail(download_message, 502)
    end
    os.remove(pack_log(token))
    if not run_core_helper(token, "inspect", "/tmp/mwef-upload-" .. token .. ".tar.gz", token) then
        local inspect_message = helper_error(core_log(token), "Downloaded plugin package is invalid")
        os.remove("/tmp/mwef-upload-" .. token .. ".tar.gz")
        run_core_helper(token, "discard", token)
        os.remove(core_log(token))
        return fail(inspect_message, 400)
    end
    local pending_root = "/tmp/mwef-pending-" .. token
    local manifest
    manifest, message = validate_staged_plugin(pending_root, entry)
    if not manifest then
        run_core_helper(token, "discard", token)
        os.remove(core_log(token))
        return fail(message, 400)
    end
    os.remove(core_log(token))
    respond({
        code = 0,
        pendingToken = token,
        operation = installed and (comparison == 0 and "reinstall" or "update") or "install",
        plugin = {
            id = entry.id,
            name = localized(entry.name, language()),
            description = localized(entry.description, language()),
            version = entry.version,
            installedVersion = installed and installed.version or nil,
            author = entry.author,
            permissions = entry.permissions,
            grants = installed and installed.grants or {},
            size = entry.archive.size
        }
    })
end

local function handle_discard()
    if not is_post() then return fail("POST required", 405) end
    if not require_grants({ "filesystem.write", "shell.execute" }) then return end
    local token = http.formvalue("token") or ""
    if not token:match("^%d+%-[a-fA-F0-9]+$") or #token > 80 then return fail("Invalid pending token", 400) end
    if not run_core_helper(token, "discard", token) then
        local discard_message = helper_error(core_log(token), "Unable to discard the pending package")
        os.remove(core_log(token))
        return fail(discard_message, 500)
    end
    os.remove(core_log(token))
    respond({ code = 0 })
end

function index()
    -- The authenticated endpoint is registered by luci.controller.web.mwef_packmanager.
end

function dispatch()
    if not valid_session() then return fail("Invalid token", 403) end
    local query = os.getenv("QUERY_STRING") or ""
    local action = query:match("^action=([a-z%-]+)") or query:match("&action=([a-z%-]+)") or "status"
    if action == "status" then return handle_status() end
    if action == "catalog" then return handle_catalog() end
    if action == "settings" then return handle_settings() end
    if action == "stage" then return handle_stage() end
    if action == "discard" then return handle_discard() end
    return fail("Unknown action", 404)
end
