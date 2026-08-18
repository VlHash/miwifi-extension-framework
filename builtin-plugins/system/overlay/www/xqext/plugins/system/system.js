(function () {
    'use strict';

    var config = window.XQEXT_CONFIG || {};
    var interval = config.interval || 2000;
    var maxPoints = config.points || 60;
    var state = {
        previousCpu: null,
        cpu: [],
        ramUsed: [],
        ramCached: [],
        i18n: {},
        timer: null,
        stopped: false
    };

    function byId(id) {
        return document.getElementById(id);
    }

    function tr(key, fallback) {
        return state.i18n[key] || fallback || key;
    }

    function applyTranslations() {
        var nodes = document.querySelectorAll('[data-i18n]');
        for (var index = 0; index < nodes.length; index += 1) {
            var key = nodes[index].getAttribute('data-i18n');
            if (state.i18n[key]) nodes[index].textContent = state.i18n[key];
        }
    }

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function finite(value, fallback) {
        value = Number(value);
        return isFinite(value) ? value : (fallback || 0);
    }

    function pushPoint(list, value) {
        list.push(clamp(finite(value), 0, 100));
        if (list.length > maxPoints) {
            list.shift();
        }
    }

    function formatBytes(bytes) {
        var value = finite(bytes);
        var units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        var unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit += 1;
        }
        var digits = unit === 0 ? 0 : (value >= 100 ? 0 : value >= 10 ? 1 : 2);
        return value.toFixed(digits) + ' ' + units[unit];
    }

    function formatFrequency(hz) {
        hz = finite(hz);
        if (!hz) return '--';
        if (hz >= 1000000000) return (hz / 1000000000).toFixed(2) + ' GHz';
        return Math.round(hz / 1000000) + ' MHz';
    }

    function formatDuration(seconds) {
        seconds = Math.max(0, Math.floor(finite(seconds)));
        var days = Math.floor(seconds / 86400);
        seconds -= days * 86400;
        var hours = Math.floor(seconds / 3600);
        seconds -= hours * 3600;
        var minutes = Math.floor(seconds / 60);
        var secs = seconds - minutes * 60;
        var parts = [];
        if (days) parts.push(days + ' 天');
        if (days || hours) parts.push(hours + ' 小时');
        parts.push(minutes + ' 分');
        parts.push(secs + ' 秒');
        return parts.join(' ');
    }

    function formatDate(epoch) {
        var date = new Date(finite(epoch) * 1000);
        if (isNaN(date.getTime())) return '--';
        function pad(value) { return value < 10 ? '0' + value : String(value); }
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) +
            ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
    }

    function setText(id, value) {
        var node = byId(id);
        if (node) node.textContent = value;
    }

    function clear(node) {
        while (node && node.firstChild) node.removeChild(node.firstChild);
    }

    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }

    function RollingChart(canvas, series) {
        this.canvas = canvas;
        this.context = canvas.getContext('2d');
        this.series = series;
        var self = this;
        if (window.ResizeObserver) {
            this.resizeObserver = new ResizeObserver(function () { self.draw(); });
            this.resizeObserver.observe(canvas.parentNode);
        } else {
            window.addEventListener('resize', function () { self.draw(); });
        }
    }

    RollingChart.prototype.draw = function () {
        var canvas = this.canvas;
        var context = this.context;
        var rect = canvas.getBoundingClientRect();
        var width = Math.max(1, Math.round(rect.width));
        var height = Math.max(1, Math.round(rect.height));
        var ratio = window.devicePixelRatio || 1;
        if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
            canvas.width = Math.round(width * ratio);
            canvas.height = Math.round(height * ratio);
        }
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
        context.clearRect(0, 0, width, height);

        var left = 33;
        var right = 8;
        var top = 8;
        var bottom = 20;
        var plotWidth = width - left - right;
        var plotHeight = height - top - bottom;
        context.font = '9px Consolas, monospace';
        context.textAlign = 'right';
        context.textBaseline = 'middle';

        [0, 25, 50, 75, 100].forEach(function (tick) {
            var y = top + plotHeight * (1 - tick / 100);
            context.beginPath();
            context.strokeStyle = tick === 0 ? '#dfe4eb' : '#edf0f4';
            context.lineWidth = 1;
            context.moveTo(left, Math.round(y) + 0.5);
            context.lineTo(width - right, Math.round(y) + 0.5);
            context.stroke();
            context.fillStyle = '#a0a8b2';
            context.fillText(tick + '%', left - 5, y);
        });

        this.series.forEach(function (serie) {
            var values = serie.values;
            if (!values.length) return;
            var startX = left + plotWidth * Math.max(0, (maxPoints - values.length) / (maxPoints - 1));
            var step = plotWidth / Math.max(1, maxPoints - 1);
            context.beginPath();
            values.forEach(function (value, index) {
                var x = startX + index * step;
                var y = top + plotHeight * (1 - clamp(value, 0, 100) / 100);
                if (index === 0) context.moveTo(x, y);
                else context.lineTo(x, y);
            });
            context.strokeStyle = serie.color;
            context.lineWidth = 2;
            context.lineJoin = 'round';
            context.lineCap = 'round';
            context.stroke();

            if (serie.fill && values.length > 1) {
                var lastX = startX + (values.length - 1) * step;
                context.lineTo(lastX, top + plotHeight);
                context.lineTo(startX, top + plotHeight);
                context.closePath();
                var gradient = context.createLinearGradient(0, top, 0, top + plotHeight);
                gradient.addColorStop(0, serie.fill);
                gradient.addColorStop(1, 'rgba(255,255,255,0)');
                context.fillStyle = gradient;
                context.fill();
            }
        });
    };

    var cpuChart = new RollingChart(byId('xqext-cpu-chart'), [
        { values: state.cpu, color: '#0059fa', fill: 'rgba(0,89,250,.18)' }
    ]);
    var ramChart = new RollingChart(byId('xqext-ram-chart'), [
        { values: state.ramUsed, color: '#0059fa', fill: 'rgba(0,89,250,.10)' },
        { values: state.ramCached, color: '#18b9ee', fill: null }
    ]);

    function calculateCpu(counters) {
        if (!counters || !counters.length) return null;
        var total = counters.reduce(function (sum, value) { return sum + finite(value); }, 0);
        var idle = finite(counters[3]) + finite(counters[4]);
        var current = { total: total, idle: idle };
        if (!state.previousCpu) {
            state.previousCpu = current;
            return null;
        }
        var deltaTotal = current.total - state.previousCpu.total;
        var deltaIdle = current.idle - state.previousCpu.idle;
        state.previousCpu = current;
        if (deltaTotal <= 0) return null;
        return clamp((1 - deltaIdle / deltaTotal) * 100, 0, 100);
    }

    function renderOverview(data) {
        var system = data.system || {};
        var cpu = data.cpu || {};
        var load = data.load || {};
        var started = finite(data.timestamp) - finite(system.uptime);
        var cpuDetails = (cpu.name || '--') + ' · ' + (cpu.cores || '--') + ' 核';
        var loadText = [load.one, load.five, load.fifteen].map(function (value) {
            return finite(value).toFixed(2);
        }).join(' / ');
        var rows = [
            [tr('model', '硬件型号'), system.model || '--'],
            [tr('target', 'Target Platform'), system.target || '--'],
            [tr('kernel', '内核版本'), system.kernel || '--'],
            [tr('uptime', '运行时间'), formatDuration(system.uptime)],
            [tr('cpuSoc', 'CPU / SoC'), cpuDetails],
            [tr('cpuFrequency', 'CPU 频率'), formatFrequency(cpu.current_hz) + ' / ' + formatFrequency(cpu.max_hz)],
            [tr('architecture', '系统架构'), system.architecture || ('ARMv' + (cpu.architecture || '--'))],
            [tr('firmware', '固件版本'), system.firmware || '--'],
            [tr('hostname', '设备名称'), system.hostname || '--'],
            [tr('board', 'Board'), system.board || '--'],
            [tr('load', '系统负载'), loadText],
            [tr('bootTime', '启动时间'), formatDate(started)]
        ];
        var container = byId('xqext-overview');
        clear(container);
        rows.forEach(function (row) {
            var item = element('dl', 'xqext-info-item');
            item.appendChild(element('dt', '', row[0]));
            item.appendChild(element('dd', '', row[1]));
            container.appendChild(item);
        });
        setText('xqext-clock', '路由器时间 ' + formatDate(data.timestamp));
        setText('xqext-router-name', system.hostname || '小米路由器');
        setText('xqext-model-subtitle', (system.model || system.hardware || '小米路由器') + ' ' + tr('subtitleSuffix', '硬件与资源运行状态'));
    }

    function renderCharts(data) {
        var cpu = data.cpu || {};
        var memory = data.memory || {};
        var usage = calculateCpu(cpu.counters);
        if (usage !== null) {
            pushPoint(state.cpu, usage);
            setText('xqext-cpu-value', usage.toFixed(1) + '%');
        }
        var total = Math.max(1, finite(memory.total));
        var usedPercent = finite(memory.used) * 100 / total;
        var cachedPercent = finite(memory.cached) * 100 / total;
        pushPoint(state.ramUsed, usedPercent);
        pushPoint(state.ramCached, cachedPercent);
        setText('xqext-ram-used', usedPercent.toFixed(1) + '%');
        setText('xqext-ram-cache', cachedPercent.toFixed(1) + '%');
        setText('xqext-ram-meta', '已使用 ' + formatBytes(memory.used) + ' · 已缓存 ' +
            formatBytes(memory.cached) + ' · 可用 ' + formatBytes(memory.available) + ' · 总计 ' + formatBytes(memory.total));
        setText('xqext-cpu-meta', (cpu.name || 'CPU') + ' · ' + (cpu.cores || '--') + ' 核 · 当前 ' +
            formatFrequency(cpu.current_hz) + ' · 最高 ' + formatFrequency(cpu.max_hz));
        cpuChart.draw();
        ramChart.draw();
    }

    function sensorLabel(sensor, index) {
        var match = String(sensor.type || '').match(/sensor(\d+)$/i);
        if (match) return 'SoC 传感器 ' + match[1];
        return sensor.type || ('温度传感器 ' + (index + 1));
    }

    function temperatureClass(value) {
        if (value >= 80) return 'hot';
        if (value >= 65) return 'warm';
        return 'cool';
    }

    function renderThermal(sensors) {
        sensors = sensors || [];
        var container = byId('xqext-thermal');
        clear(container);
        var total = 0;
        sensors.forEach(function (sensor) {
            var value = finite(sensor.celsius);
            total += value;
        });
        var average = sensors.length ? total / sensors.length : 0;
        if (sensors.length) {
            var summary = element('button', 'xqext-thermal-summary');
            summary.type = 'button';
            summary.setAttribute('aria-expanded', 'false');
            var item = element('div', 'xqext-thermal-item xqext-thermal-average');
            var label = element('div', 'xqext-thermal-label');
            label.appendChild(element('span', '', tr('averageTemperature', '总体平均温度')));
            label.appendChild(element('span', 'xqext-thermal-value', average.toFixed(1) + '°C  ▾'));
            var progress = element('div', 'xqext-progress ' + temperatureClass(average));
            var bar = element('i');
            bar.style.width = clamp(average, 0, 100) + '%';
            progress.appendChild(bar);
            item.appendChild(label);
            item.appendChild(progress);
            summary.appendChild(item);
            container.appendChild(summary);

            var details = element('div', 'xqext-thermal-details');
            details.hidden = true;
            sensors.forEach(function (sensor, index) {
                var value = finite(sensor.celsius);
                var sensorItem = element('div', 'xqext-thermal-item');
                var sensorLabelNode = element('div', 'xqext-thermal-label');
                var name = element('span', '', sensorLabel(sensor, index));
                name.appendChild(element('small', '', sensor.id || ''));
                sensorLabelNode.appendChild(name);
                sensorLabelNode.appendChild(element('strong', '', value.toFixed(1) + '°C'));
                sensorItem.appendChild(sensorLabelNode);
                sensorItem.appendChild(makeProgress(value, temperatureClass(value)));
                details.appendChild(sensorItem);
            });
            container.appendChild(details);
            summary.onclick = function () {
                details.hidden = !details.hidden;
                summary.setAttribute('aria-expanded', details.hidden ? 'false' : 'true');
                var valueNode = summary.querySelector('.xqext-thermal-value');
                valueNode.textContent = average.toFixed(1) + '°C  ' + (details.hidden ? '▾' : '▴');
            };
        }
        if (!sensors.length) {
            container.appendChild(element('p', 'xqext-muted', '当前固件未暴露温度传感器。'));
        }
        var maxNode = byId('xqext-temp-max');
        maxNode.textContent = sensors.length ? average.toFixed(1) + '°C' : '--°C';
        maxNode.style.color = average >= 80 ? '#ef4444' : average >= 65 ? '#f27922' : '#1dbf73';
    }

    function makeProgress(percent, extraClass) {
        var progress = element('div', 'xqext-progress ' + (extraClass || ''));
        var bar = element('i');
        bar.style.width = clamp(finite(percent), 0, 100) + '%';
        progress.appendChild(bar);
        return progress;
    }

    function renderStorage(data) {
        var storage = data.storage || {};
        var partitions = data.partitions || [];
        var summary = byId('xqext-storage-summary');
        clear(summary);
        var head = element('div', 'xqext-storage-head');
        head.appendChild(element('span', '', '可写分区总占用'));
        head.appendChild(element('strong', '', finite(storage.percent).toFixed(1) + '%'));
        summary.appendChild(head);
        summary.appendChild(makeProgress(storage.percent));
        setText('xqext-storage-total', formatBytes(storage.used) + ' / ' + formatBytes(storage.total));

        var container = byId('xqext-partitions');
        clear(container);
        partitions.forEach(function (partition) {
            var item = element('div', 'xqext-partition');
            var itemHead = element('div', 'xqext-partition-head');
            var title = element('span', 'xqext-partition-title', partition.label || partition.mountpoint);
            title.title = partition.mountpoint || '';
            title.appendChild(element('small', '', partition.fstype || ''));
            itemHead.appendChild(title);
            itemHead.appendChild(element('strong', '', finite(partition.percent).toFixed(1) + '%'));
            item.appendChild(itemHead);
            item.appendChild(makeProgress(partition.percent));
            item.appendChild(element('div', 'xqext-partition-meta',
                formatBytes(partition.used) + ' 已用 / ' + formatBytes(partition.total) + ' 总计 · ' + (partition.mountpoint || '')));
            container.appendChild(item);
        });
        if (!partitions.length) {
            container.appendChild(element('p', 'xqext-muted', '没有找到可显示的可写分区。'));
        }
    }

    function setConnection(mode, message) {
        var wrapper = document.querySelector('.xqext-live');
        if (wrapper) wrapper.className = 'xqext-live ' + mode;
        setText('xqext-status', message);
    }

    function showError(message) {
        var node = byId('xqext-error');
        node.hidden = !message;
        node.textContent = message || '';
    }

    function render(data) {
        renderOverview(data);
        renderCharts(data);
        renderThermal(data.thermal);
        renderStorage(data);
    }

    function requestJson(url) {
        return new Promise(function (resolve, reject) {
            var request = new XMLHttpRequest();
            request.open('GET', url + (url.indexOf('?') >= 0 ? '&' : '?') + '_=' + Date.now(), true);
            request.timeout = 5000;
            request.setRequestHeader('Accept', 'application/json');
            request.onreadystatechange = function () {
                if (request.readyState !== 4) return;
                if (request.status < 200 || request.status >= 300) {
                    reject(new Error('HTTP ' + request.status));
                    return;
                }
                try { resolve(JSON.parse(request.responseText)); }
                catch (error) { reject(new Error('返回数据格式错误')); }
            };
            request.onerror = function () { reject(new Error('网络请求失败')); };
            request.ontimeout = function () { reject(new Error('数据请求超时')); };
            request.send(null);
        });
    }

    function poll() {
        if (state.stopped) return;
        requestJson(config.apiUrl).then(function (data) {
            if (!data || data.code !== 0) throw new Error((data && data.message) || '接口返回异常');
            render(data);
            showError('');
            setConnection('online', '实时更新 · ' + formatDate(data.timestamp).split(' ')[1]);
        }).catch(function (error) {
            setConnection('error', '数据连接异常');
            showError('暂时无法读取系统信息：' + error.message + '。页面会自动重试。');
        }).then(function () {
            if (!state.stopped) state.timer = window.setTimeout(poll, document.hidden ? interval * 3 : interval);
        });
    }

    document.addEventListener('visibilitychange', function () {
        if (!document.hidden && state.timer) {
            window.clearTimeout(state.timer);
            state.timer = window.setTimeout(poll, 100);
        }
    });
    window.addEventListener('beforeunload', function () {
        state.stopped = true;
        if (state.timer) window.clearTimeout(state.timer);
    });

    requestJson(config.i18nUrl).then(function (translations) {
        state.i18n = translations || {};
        applyTranslations();
    }).catch(function () {
        state.i18n = {};
    }).then(poll);
}());
