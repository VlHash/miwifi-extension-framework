module("luci.controller.api.mwef_system", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local json = require "luci.json"

local VERSION = "0.2.0"

local function read_file(path, binary)
    local handle = io.open(path, binary and "rb" or "r")
    if not handle then
        return nil
    end
    local value = handle:read("*a")
    handle:close()
    return value
end

local function trim(value)
    if not value then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

local function read_line(path)
    local value = read_file(path)
    return value and trim(value:match("([^\r\n]+)")) or nil
end

local function parse_release(path)
    local result = {}
    local content = read_file(path) or ""
    for line in content:gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then
            value = trim(value)
            if value and #value >= 2 then
                local first = value:sub(1, 1)
                local last = value:sub(-1)
                if (first == "'" and last == "'") or (first == '"' and last == '"') then
                    value = value:sub(2, -2)
                end
            end
            result[key] = value
        end
    end
    return result
end

local function parse_meminfo()
    local result = {}
    local content = read_file("/proc/meminfo") or ""
    for key, value in content:gmatch("([%w_%(%)]+):%s+(%d+)") do
        result[key] = tonumber(value) * 1024
    end

    local total = result.MemTotal or 0
    local free = result.MemFree or 0
    local buffers = result.Buffers or 0
    local cached = (result.Cached or 0) + (result.SReclaimable or 0)
    local cache_total = buffers + cached
    local used = total - free - cache_total
    if used < 0 then
        used = 0
    end

    return {
        total = total,
        used = used,
        cached = cache_total,
        free = free,
        available = result.MemAvailable or (free + cache_total),
        swap_total = result.SwapTotal or 0,
        swap_free = result.SwapFree or 0
    }
end

local function parse_cpu_stat()
    local line = (read_file("/proc/stat") or ""):match("cpu%s+([^\r\n]+)") or ""
    local values = {}
    for value in line:gmatch("%d+") do
        values[#values + 1] = tonumber(value)
    end
    return values
end

local function read_frequency()
    local current_sum = 0
    local current_count = 0
    local maximum = 0
    for path in fs.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq") do
        local value = tonumber(read_line(path)) or 0
        if value > 0 then
            current_sum = current_sum + value
            current_count = current_count + 1
        end
    end
    for path in fs.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq") do
        local value = tonumber(read_line(path)) or 0
        if value > maximum then
            maximum = value
        end
    end
    return current_count > 0 and math.floor(current_sum * 1000 / current_count) or 0,
        maximum * 1000
end

local function parse_cpuinfo()
    local content = read_file("/proc/cpuinfo") or ""
    local cores = 0
    for _ in content:gmatch("processor%s*:%s*%d+") do
        cores = cores + 1
    end

    local compatible = (read_file("/proc/device-tree/compatible", true) or ""):gsub("%z", " ")
    local soc = compatible:match("qcom,(ipq[%w%-]+)")
    if soc then
        soc = "Qualcomm " .. soc:upper()
    end

    local current_hz, max_hz = read_frequency()
    return {
        name = content:match("model name%s*:%s*([^\r\n]+)") or soc or "ARMv8 Processor",
        cores = cores,
        architecture = content:match("CPU architecture%s*:%s*([^\r\n]+)"),
        implementer = content:match("CPU implementer%s*:%s*([^\r\n]+)"),
        part = content:match("CPU part%s*:%s*([^\r\n]+)"),
        revision = content:match("CPU revision%s*:%s*([^\r\n]+)"),
        current_hz = current_hz,
        max_hz = max_hz,
        counters = parse_cpu_stat()
    }
end

local function parse_load()
    local one, five, fifteen, running, total = (read_line("/proc/loadavg") or ""):
        match("^(%S+)%s+(%S+)%s+(%S+)%s+(%d+)/(%d+)")
    return {
        one = tonumber(one) or 0,
        five = tonumber(five) or 0,
        fifteen = tonumber(fifteen) or 0,
        running = tonumber(running) or 0,
        processes = tonumber(total) or 0
    }
end

local function read_thermal()
    local sensors = {}
    for path in fs.glob("/sys/class/thermal/thermal_zone*") do
        local raw = tonumber(read_line(path .. "/temp"))
        if raw then
            local celsius = raw
            if celsius > 1000 then
                celsius = celsius / 1000
            end
            sensors[#sensors + 1] = {
                id = path:match("(thermal_zone%d+)$") or path,
                type = read_line(path .. "/type") or "thermal",
                celsius = math.floor(celsius * 10 + 0.5) / 10
            }
        end
    end
    table.sort(sensors, function(a, b)
        return a.id < b.id
    end)
    return sensors
end

local partition_labels = {
    ["/data"] = "系统配置",
    ["/data/usr"] = "用户数据",
    ["/data/userdisk"] = "插件存储",
    ["/data/other_vol"] = "持久化扩展区",
    ["/data/etc"] = "安全配置",
    ["/data/other"] = "应用数据"
}

local ignored_mounts = {
    ["/data/docker"] = true,
    ["/data/central"] = true,
    ["/data/other/docker"] = true
}

local ignored_types = {
    proc = true,
    sysfs = true,
    tmpfs = true,
    ramfs = true,
    devtmpfs = true,
    devpts = true,
    cgroup = true,
    debugfs = true,
    bpf = true,
    nsfs = true,
    overlay = true,
    squashfs = true
}

local function decode_mount(value)
    return value:gsub("\\040", " "):gsub("\\011", "\t")
end

local function read_partitions()
    local result = {}
    local seen = {}
    local content = read_file("/proc/mounts") or ""
    local aggregate = { total = 0, used = 0, available = 0 }

    for line in content:gmatch("[^\r\n]+") do
        local device, mountpoint, fstype, options = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if device and mountpoint then
            mountpoint = decode_mount(mountpoint)
            local under_data = mountpoint == "/data" or mountpoint:match("^/data/")
            local nested_docker = mountpoint:match("^/data/other/docker/")
            local writable = options and ("," .. options .. ","):match(",rw,")
            if under_data and writable and not nested_docker and not ignored_mounts[mountpoint]
                and not ignored_types[fstype] and not seen[device] then
                local stat = fs.statvfs(mountpoint)
                if stat and stat.blocks and stat.frsize then
                    local total = stat.blocks * stat.frsize
                    local used = (stat.blocks - stat.bfree) * stat.frsize
                    local available = stat.bavail * stat.frsize
                    local effective_total = used + available
                    local percent = effective_total > 0 and (used * 100 / effective_total) or 0
                    local item = {
                        device = device,
                        mountpoint = mountpoint,
                        fstype = fstype,
                        label = partition_labels[mountpoint] or mountpoint,
                        total = total,
                        used = used,
                        available = available,
                        percent = math.floor(percent * 10 + 0.5) / 10
                    }
                    result[#result + 1] = item
                    seen[device] = true
                    aggregate.total = aggregate.total + effective_total
                    aggregate.used = aggregate.used + used
                    aggregate.available = aggregate.available + available
                end
            end
        end
    end

    table.sort(result, function(a, b)
        return a.mountpoint < b.mountpoint
    end)
    aggregate.percent = aggregate.total > 0
        and math.floor(aggregate.used * 1000 / aggregate.total) / 10 or 0
    return result, aggregate
end

local function safe_xiaomi_info()
    local result = {}
    local ok, sysutil = pcall(require, "xiaoqiang.util.XQSysUtil")
    if not ok or not sysutil then
        return result
    end
    local calls = {
        hardware = "getHardware",
        firmware = "getDisplayRomVersion",
        channel = "getChannel"
    }
    for key, method in pairs(calls) do
        if type(sysutil[method]) == "function" then
            local success, value = pcall(sysutil[method])
            if success then
                result[key] = value
            end
        end
    end
    return result
end

local function collect()
    local release = parse_release("/etc/openwrt_release")
    local osrelease = parse_release("/etc/os-release")
    local uptime = tonumber((read_line("/proc/uptime") or ""):match("^(%S+)")) or 0
    local kernel = (read_file("/proc/version") or ""):match("Linux version%s+(%S+)")
    local partitions, storage = read_partitions()
    local xiaomi = safe_xiaomi_info()

    return {
        code = 0,
        plugin = { id = "system", name = "System Information", version = VERSION },
        timestamp = os.time(),
        system = {
            hostname = read_line("/proc/sys/kernel/hostname"),
            model = read_line("/tmp/sysinfo/model"),
            board = read_line("/tmp/sysinfo/board_name"),
            target = release.DISTRIB_TARGET or osrelease.LEDE_BOARD,
            architecture = release.DISTRIB_ARCH or osrelease.LEDE_ARCH,
            kernel = kernel,
            uptime = uptime,
            firmware = xiaomi.firmware or release.DISTRIB_DESCRIPTION or osrelease.PRETTY_NAME,
            channel = xiaomi.channel,
            hardware = xiaomi.hardware
        },
        cpu = parse_cpuinfo(),
        memory = parse_meminfo(),
        load = parse_load(),
        thermal = read_thermal(),
        partitions = partitions,
        storage = storage
    }
end

local function has_valid_session()
    local request_uri = os.getenv("REQUEST_URI") or ""
    local token = request_uri:match(";stok=([a-fA-F0-9]+)")
    if not token or #token < 16 or #token > 64 then
        return false
    end
    local session = fs.stat("/tmp/luci-sessions/" .. token)
    return session and session.type == "reg" or false
end

function index()
    -- The data route is registered by the web controller so it inherits the
    -- same stok-bearing URL family as the page. This module only implements it.
end

function status()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    if not has_valid_session() then
        http.write(json.encode({ code = 401, message = "Invalid token" }))
        return
    end
    local ok, data = pcall(collect)
    if ok then
        http.write(json.encode(data))
        return
    end
    http.status(500, "Internal Server Error")
    http.write(json.encode({ code = 500, message = tostring(data) }))
end
