(function () {
    'use strict';

    var config = window.PACKMANAGER_CONFIG || {};
    var state = {
        i18n: {},
        status: null,
        catalog: null,
        filter: 'all',
        query: '',
        pending: null,
        installPhase: 'idle',
        sourcePhase: 'idle',
        busy: false
    };
    var permissionHelp = {
        'system.read': ['permissionSystemRead', 'permissionSystemReadHelp'],
        'filesystem.read': ['permissionFilesystemRead', 'permissionFilesystemReadHelp'],
        'filesystem.write': ['permissionFilesystemWrite', 'permissionFilesystemWriteHelp'],
        'network.client': ['permissionNetworkClient', 'permissionNetworkClientHelp'],
        'service.control': ['permissionServiceControl', 'permissionServiceControlHelp'],
        'shell.execute': ['permissionShellExecute', 'permissionShellExecuteHelp']
    };

    function byId(id) { return document.getElementById(id); }
    function tr(key, fallback) { return state.i18n[key] || fallback || key; }
    function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); }
    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }
    function encode(values) {
        var parts = [];
        Object.keys(values || {}).forEach(function (key) {
            parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(values[key] == null ? '' : values[key]));
        });
        return parts.join('&');
    }
    function request(baseUrl, action, method, payload, timeout) {
        return new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            xhr.open(method || 'GET', baseUrl + '?action=' + encodeURIComponent(action), true);
            xhr.timeout = timeout || 30000;
            xhr.setRequestHeader('Accept', 'application/json');
            if (payload) {
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
                payload = encode(payload);
            }
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== 4) return;
                var data;
                try { data = JSON.parse(xhr.responseText); }
                catch (error) { reject(new Error(tr('invalidResponse', '服务器返回格式错误'))); return; }
                if (xhr.status < 200 || xhr.status >= 300 || !data || data.code !== 0) {
                    reject(new Error((data && data.message) || ('HTTP ' + xhr.status)));
                    return;
                }
                resolve(data);
            };
            xhr.onerror = function () { reject(new Error(tr('networkError', '网络请求失败'))); };
            xhr.ontimeout = function () { reject(new Error(tr('requestTimeout', '请求超时'))); };
            xhr.send(payload || null);
        });
    }
    function api(action, method, payload, timeout) {
        return request(config.apiUrl, action, method, payload, timeout);
    }
    function coreApi(action, method, payload, timeout) {
        return request(config.coreApiUrl, action, method, payload, timeout);
    }
    function setMessage(message, error) {
        var node = byId('packmanager-message');
        node.hidden = !message;
        node.className = 'mwef-message' + (error ? ' error' : '');
        node.textContent = message || '';
    }
    function setModalError(id, message, focusTarget) {
        var node = byId(id);
        node.hidden = !message;
        node.textContent = message || '';
        if (message && focusTarget && typeof focusTarget.focus === 'function') focusTarget.focus();
    }
    function setSourceState(mode, message) {
        var node = byId('packmanager-source-state');
        node.className = 'packmanager-source-state ' + (mode || '');
        node.lastChild.textContent = message;
    }
    function setBusy(busy) {
        state.busy = !!busy;
        byId('packmanager-refresh').disabled = state.busy;
        byId('packmanager-open-sources').disabled = state.busy;
        var buttons = byId('packmanager-list').querySelectorAll('button');
        for (var index = 0; index < buttons.length; index += 1) {
            buttons[index].disabled = state.busy || buttons[index].getAttribute('data-always-disabled') === '1';
        }
    }
    function applyTranslations() {
        var nodes = document.querySelectorAll('[data-i18n]');
        var index;
        for (index = 0; index < nodes.length; index += 1) {
            var key = nodes[index].getAttribute('data-i18n');
            if (state.i18n[key]) nodes[index].textContent = state.i18n[key];
        }
        nodes = document.querySelectorAll('[data-i18n-placeholder]');
        for (index = 0; index < nodes.length; index += 1) {
            var placeholderKey = nodes[index].getAttribute('data-i18n-placeholder');
            if (state.i18n[placeholderKey]) nodes[index].setAttribute('placeholder', state.i18n[placeholderKey]);
        }
    }
    function loadLanguage() {
        return new Promise(function (resolve) {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', config.i18nUrl, true);
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== 4) return;
                try { if (xhr.status === 200) state.i18n = JSON.parse(xhr.responseText); } catch (error) {}
                applyTranslations();
                resolve();
            };
            xhr.onerror = function () { resolve(); };
            xhr.send(null);
        });
    }
    function formatBytes(value) {
        var bytes = Number(value) || 0;
        if (!bytes) return '--';
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(bytes < 10240 ? 1 : 0) + ' KiB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MiB';
    }
    function button(label, className, handler, disabled) {
        var node = el('button', 'mwef-btn mwef-btn-small ' + (className || ''), label);
        node.type = 'button';
        node.setAttribute('data-always-disabled', disabled ? '1' : '0');
        node.disabled = !!disabled || state.busy;
        if (!disabled) node.onclick = handler;
        return node;
    }
    function safeLink(url, label) {
        if (typeof url !== 'string' || !/^https:\/\//.test(url)) return null;
        var link = el('a', 'packmanager-table-link', label);
        link.href = url;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        return link;
    }

    function sourceEntries() {
        var catalog = state.catalog || { plugins: [], installed: [] };
        var entries = [];
        var seen = {};
        (catalog.plugins || []).forEach(function (plugin) {
            var copy = {};
            Object.keys(plugin).forEach(function (key) { copy[key] = plugin[key]; });
            copy.online = true;
            entries.push(copy);
            seen[copy.id] = true;
        });
        (catalog.installed || []).forEach(function (plugin) {
            if (seen[plugin.id]) return;
            entries.push({
                id: plugin.id,
                name: plugin.name || plugin.id,
                description: plugin.description || '',
                version: plugin.version,
                installedVersion: plugin.version,
                enabled: plugin.enabled,
                builtin: plugin.builtin,
                permissions: plugin.permissions || [],
                grants: plugin.grants || [],
                status: 'local',
                compatible: true,
                canInstall: false,
                online: false
            });
        });
        return entries;
    }
    function matchesFilter(entry) {
        if (state.filter === 'update' && entry.status !== 'update') return false;
        if (state.filter === 'available' && entry.status !== 'available') return false;
        if (state.filter === 'installed' && !entry.installedVersion) return false;
        if (!state.query) return true;
        var haystack = [entry.name, entry.id, entry.description, entry.author, (entry.categories || []).join(' ')].join(' ').toLowerCase();
        return haystack.indexOf(state.query) !== -1;
    }
    function statusBadge(entry) {
        var label = tr('available', '可安装');
        var className = 'mwef-badge packmanager-badge-available';
        if (!entry.compatible) { label = tr('incompatible', '不兼容'); className = 'mwef-badge packmanager-badge-warning'; }
        else if (entry.status === 'update') { label = tr('updateAvailable', '可更新'); className = 'mwef-badge packmanager-badge-update'; }
        else if (entry.status === 'installed') { label = tr('installed', '已安装'); className = 'mwef-badge on'; }
        else if (entry.status === 'newer') { label = tr('localNewer', '本地较新'); className = 'mwef-badge packmanager-badge-warning'; }
        else if (entry.status === 'unknown') { label = tr('versionUnknown', '版本未知'); className = 'mwef-badge packmanager-badge-warning'; }
        else if (entry.status === 'local') { label = entry.enabled === false ? tr('disabled', '已停用') : tr('localPackage', '本地安装'); className = 'mwef-badge' + (entry.enabled === false ? '' : ' on'); }
        return el('span', className, label);
    }
    function stageLabel(entry) {
        if (entry.status === 'update') return tr('upgrade', '升级');
        if (entry.status === 'installed') return tr('reinstall', '重装');
        return tr('install', '安装');
    }
    function renderActions(cell, entry) {
        if (entry.online) {
            var disabled = !entry.canInstall;
            var label = stageLabel(entry);
            if (!entry.compatible) label = tr('requiresNewerFramework', '需更新框架');
            if (entry.builtin) label = tr('frameworkManaged', '随框架更新');
            if (entry.status === 'newer') label = tr('localNewer', '本地较新');
            if (entry.status === 'unknown') label = tr('versionUnknown', '版本未知');
            cell.appendChild(button(label, entry.status === 'available' || entry.status === 'update' ? 'mwef-btn-primary' : '', function () {
                stagePackage(entry);
            }, disabled));
            if (entry.installedVersion && !entry.builtin) {
                cell.appendChild(button(tr('remove', '移除'), 'mwef-btn-danger', function () {
                    if (window.confirm(tr('removeConfirm', '插件会移至恢复目录，确定继续？'))) mutateInstalled('remove', entry.id);
                }));
            } else {
                var onlineLink = safeLink(entry.homepage || entry.source, tr('details', '详情'));
                if (onlineLink) cell.appendChild(onlineLink);
            }
            return;
        }
        if (entry.builtin) {
            cell.appendChild(button(tr('builtIn', '内置'), '', function () {}, true));
            return;
        }
        cell.appendChild(button(entry.enabled === false ? tr('enable', '启用') : tr('disable', '停用'), '', function () {
            mutateInstalled(entry.enabled === false ? 'enable' : 'disable', entry.id);
        }));
        cell.appendChild(button(tr('remove', '移除'), 'mwef-btn-danger', function () {
            if (window.confirm(tr('removeConfirm', '插件会移至恢复目录，确定继续？'))) mutateInstalled('remove', entry.id);
        }));
    }
    function renderEntries() {
        var entries = sourceEntries();
        var counts = { all: entries.length, update: 0, available: 0, installed: 0 };
        entries.forEach(function (entry) {
            if (entry.status === 'update') counts.update += 1;
            if (entry.status === 'available') counts.available += 1;
            if (entry.installedVersion) counts.installed += 1;
        });
        Object.keys(counts).forEach(function (key) { byId('packmanager-count-' + key).textContent = String(counts[key]); });

        var body = byId('packmanager-list');
        clear(body);
        var visible = entries.filter(matchesFilter);
        if (!visible.length) {
            var emptyRow = el('tr');
            var emptyCell = el('td', 'mwef-empty', entries.length ? tr('noMatches', '没有符合筛选条件的软件包') : tr('emptySource', '软件源暂未收录在线插件'));
            emptyCell.colSpan = 5;
            emptyRow.appendChild(emptyCell);
            body.appendChild(emptyRow);
            return;
        }
        visible.forEach(function (entry) {
            var row = el('tr');
            var packageCell = el('td');
            var title = el('span', 'packmanager-package-title');
            title.appendChild(el('strong', '', entry.name || entry.id));
            title.appendChild(el('span', 'packmanager-package-id', entry.id));
            if (entry.builtin) title.appendChild(el('span', 'mwef-badge', tr('builtIn', '内置')));
            packageCell.appendChild(title);
            packageCell.appendChild(el('span', 'packmanager-description', entry.description || tr('noDescription', '暂无简介')));
            var meta = [];
            if (entry.author) meta.push(entry.author);
            if (entry.license) meta.push(entry.license);
            if (entry.mwef) meta.push('MWEF ' + entry.mwef);
            if (meta.length) packageCell.appendChild(el('span', 'packmanager-meta', meta.join(' · ')));
            row.appendChild(packageCell);

            var versionCell = el('td');
            versionCell.appendChild(el('span', 'packmanager-version', entry.version || '--'));
            if (entry.online && entry.installedVersion && entry.installedVersion !== entry.version) {
                versionCell.appendChild(el('span', 'packmanager-version-old', tr('installedVersion', '已安装') + ' ' + entry.installedVersion));
            }
            row.appendChild(versionCell);
            var statusCell = el('td');
            statusCell.appendChild(statusBadge(entry));
            row.appendChild(statusCell);
            row.appendChild(el('td', 'packmanager-size', entry.online ? formatBytes(entry.size) : '--'));
            var actionCell = el('td', 'packmanager-action-cell');
            renderActions(actionCell, entry);
            row.appendChild(actionCell);
            body.appendChild(row);
        });
    }

    function applyCatalog(data) {
        state.catalog = data;
        if (data.source) {
            byId('packmanager-source-name').textContent = data.source.name || tr('customSource', '自定义软件源');
            byId('packmanager-maintainer').textContent = data.source.maintainer || '--';
            byId('packmanager-updated').textContent = data.source.updated || '--';
        }
        setSourceState('ready', tr('sourceReady', '软件源已同步'));
        renderEntries();
    }
    function reconcileInstalled(installed) {
        if (!state.catalog) return;
        var installedById = {};
        (installed || []).forEach(function (plugin) { installedById[plugin.id] = plugin; });
        state.catalog.installed = installed || [];
        (state.catalog.plugins || []).forEach(function (plugin) {
            var local = installedById[plugin.id];
            plugin.installedVersion = local ? local.version : null;
            plugin.builtin = local ? !!local.builtin : false;
            plugin.enabled = local ? !!local.enabled : null;
            if (!local) plugin.status = 'available';
            else if (local.version === plugin.version) plugin.status = 'installed';
        });
    }
    function loadCatalog(showMessage) {
        if (state.busy || state.pending || state.installPhase !== 'idle') return Promise.resolve(null);
        setBusy(true);
        setSourceState('loading', tr('sourceRefreshing', '正在刷新软件源'));
        if (showMessage) setMessage(tr('refreshingPackages', '正在获取并校验插件列表…'));
        return api('catalog', 'GET', null, 90000).then(function (data) {
            applyCatalog(data);
            setBusy(false);
            setMessage('');
            return data;
        }).catch(function (error) {
            setBusy(false);
            setSourceState('error', tr('sourceError', '软件源不可用'));
            setMessage(error.message, true);
            if (!state.catalog && state.status) {
                state.catalog = { plugins: [], installed: state.status.installed || [], settings: state.status.settings || {} };
                renderEntries();
            }
            throw error;
        });
    }

    function permissionOption(permission, checked) {
        var help = permissionHelp[permission] || [permission, ''];
        var label = el('label', 'mwef-permission-option');
        var input = document.createElement('input');
        input.type = 'checkbox';
        input.value = permission;
        input.checked = !!checked;
        var content = el('span');
        content.appendChild(el('strong', '', tr(help[0], permission) + ' · ' + permission));
        content.appendChild(el('small', '', tr(help[1], '')));
        label.appendChild(input);
        label.appendChild(content);
        return label;
    }
    function openInstallModal(data) {
        state.pending = data;
        state.installPhase = 'idle';
        setBusy(true);
        setModalError('packmanager-install-error', '');
        var plugin = data.plugin;
        byId('packmanager-pending-name').textContent = (plugin.name || plugin.id) + ' · ' + plugin.version;
        byId('packmanager-pending-description').textContent = plugin.description || '';
        byId('packmanager-pending-operation').textContent = data.operation === 'update'
            ? tr('upgrade', '升级') : (data.operation === 'reinstall' ? tr('reinstall', '重装') : tr('install', '安装'));
        var summary = byId('packmanager-install-summary');
        clear(summary);
        var version = el('span', '', tr('targetVersion', '目标版本') + ':');
        version.appendChild(el('strong', '', plugin.version));
        summary.appendChild(version);
        var author = el('span', '', tr('author', '作者') + ':');
        author.appendChild(el('strong', '', plugin.author || '--'));
        summary.appendChild(author);
        var size = el('span', '', tr('packageSize', '大小') + ':');
        size.appendChild(el('strong', '', formatBytes(plugin.size)));
        summary.appendChild(size);
        var list = byId('packmanager-permission-list');
        clear(list);
        var grants = {};
        (plugin.grants || []).forEach(function (permission) { grants[permission] = true; });
        (plugin.permissions || []).forEach(function (permission) { list.appendChild(permissionOption(permission, grants[permission])); });
        if (!plugin.permissions || !plugin.permissions.length) {
            list.appendChild(el('p', 'packmanager-permission-empty', tr('noPermissionsRequested', '此插件未申请额外权限。')));
        }
        byId('packmanager-install-confirm').textContent = data.operation === 'update'
            ? tr('confirmUpgrade', '确认升级')
            : (data.operation === 'reinstall' ? tr('confirmReinstall', '确认重装') : tr('confirmInstall', '确认安装'));
        byId('packmanager-install-confirm').disabled = false;
        byId('packmanager-install-cancel').disabled = false;
        byId('packmanager-install-close').disabled = false;
        byId('packmanager-install-mask').hidden = false;
        byId('packmanager-install-confirm').focus();
    }
    function stagePackage(entry) {
        if (state.busy || state.pending) return;
        setBusy(true);
        setMessage(tr('preparingPackage', '正在下载、校验并检查插件包…'));
        api('stage', 'POST', { id: entry.id }, 240000).then(function (data) {
            setBusy(false);
            setMessage('');
            openInstallModal(data);
        }).catch(function (error) {
            setBusy(false);
            setMessage(error.message, true);
            renderEntries();
        });
    }
    function selectedGrants() {
        var result = [];
        var inputs = byId('packmanager-permission-list').querySelectorAll('input:checked');
        for (var index = 0; index < inputs.length; index += 1) result.push(inputs[index].value);
        return result.join(',');
    }
    function closeInstallModal() {
        byId('packmanager-install-mask').hidden = true;
        state.pending = null;
        state.installPhase = 'idle';
        setBusy(false);
    }
    function discardPending() {
        if (state.installPhase !== 'idle') return;
        if (!state.pending) { closeInstallModal(); return; }
        state.installPhase = 'discarding';
        var token = state.pending.pendingToken;
        byId('packmanager-install-confirm').disabled = true;
        byId('packmanager-install-cancel').disabled = true;
        byId('packmanager-install-close').disabled = true;
        api('discard', 'POST', { token: token }, 30000).then(function () {
            closeInstallModal();
        }).catch(function (error) {
            state.installPhase = 'idle';
            byId('packmanager-install-confirm').disabled = false;
            byId('packmanager-install-cancel').disabled = false;
            byId('packmanager-install-close').disabled = false;
            setModalError('packmanager-install-error', error.message);
        });
    }
    function confirmInstall() {
        if (!state.pending || state.installPhase !== 'idle') return;
        var pending = state.pending;
        state.installPhase = 'installing';
        byId('packmanager-install-confirm').disabled = true;
        byId('packmanager-install-cancel').disabled = true;
        byId('packmanager-install-close').disabled = true;
        setModalError('packmanager-install-error', '');
        setMessage(pending.operation === 'update'
            ? tr('upgradingPackage', '正在升级并重新加载插件层…')
            : (pending.operation === 'reinstall' ? tr('reinstallingPackage', '正在重装并重新加载插件层…') : tr('installingPackage', '正在安装并重新加载插件层…')));
        coreApi('install', 'POST', { token: pending.pendingToken, grants: selectedGrants() }, 180000).then(function (data) {
            closeInstallModal();
            reconcileInstalled(data.plugins || []);
            setMessage(tr('installComplete', '插件安装完成。'));
            renderEntries();
            window.setTimeout(function () { loadCatalog(false).catch(function () {}); }, 500);
        }).catch(function (error) {
            state.installPhase = 'idle';
            byId('packmanager-install-confirm').disabled = false;
            byId('packmanager-install-cancel').disabled = false;
            byId('packmanager-install-close').disabled = false;
            setModalError('packmanager-install-error', error.message);
        });
    }

    function mutateInstalled(action, id) {
        if (state.busy || state.pending || state.installPhase !== 'idle') return;
        setBusy(true);
        setMessage(tr('applying', '正在应用并重新加载插件层…'));
        coreApi(action, 'POST', { id: id }, 120000).then(function (data) {
            reconcileInstalled(data.plugins || []);
            setBusy(false);
            setMessage(tr('applied', '操作已完成。'));
            renderEntries();
            loadCatalog(false).catch(function () {});
        }).catch(function (error) {
            setBusy(false);
            setMessage(error.message, true);
            renderEntries();
        });
    }

    function selectIndexPreset(value) {
        var input = byId('packmanager-index-url');
        if (value === 'official') input.value = config.officialIndex;
        else if (value === 'jsdelivr') input.value = config.jsdelivrIndex;
        input.readOnly = value !== 'custom';
    }
    function selectProxyPreset(value) {
        var input = byId('packmanager-proxy-url');
        if (value === 'direct') input.value = '';
        else if (value === 'ghfast') input.value = config.ghfastProxy;
        input.readOnly = value !== 'custom';
    }
    function currentSettings() {
        if (state.catalog && state.catalog.settings) return state.catalog.settings;
        return state.status && state.status.settings ? state.status.settings : { indexUrl: config.officialIndex, githubProxy: '' };
    }
    function openSourceModal() {
        if (state.sourcePhase !== 'idle') return;
        var settings = currentSettings();
        var indexPreset = settings.indexUrl === config.officialIndex ? 'official' : (settings.indexUrl === config.jsdelivrIndex ? 'jsdelivr' : 'custom');
        var proxyPreset = !settings.githubProxy ? 'direct' : (settings.githubProxy === config.ghfastProxy ? 'ghfast' : 'custom');
        byId('packmanager-index-preset').value = indexPreset;
        byId('packmanager-index-url').value = settings.indexUrl || config.officialIndex;
        byId('packmanager-index-url').readOnly = indexPreset !== 'custom';
        byId('packmanager-proxy-preset').value = proxyPreset;
        byId('packmanager-proxy-url').value = settings.githubProxy || '';
        byId('packmanager-proxy-url').readOnly = proxyPreset !== 'custom';
        setModalError('packmanager-source-error', '');
        byId('packmanager-source-save').disabled = false;
        byId('packmanager-source-mask').hidden = false;
        byId('packmanager-index-preset').focus();
    }
    function setSourceModalBusy(busy) {
        var ids = [
            'packmanager-source-close', 'packmanager-source-cancel', 'packmanager-source-defaults',
            'packmanager-index-preset', 'packmanager-index-url', 'packmanager-proxy-preset', 'packmanager-proxy-url'
        ];
        for (var index = 0; index < ids.length; index += 1) byId(ids[index]).disabled = !!busy;
        byId('packmanager-source-save').disabled = !!busy;
    }
    function closeSourceModal(force) {
        if (state.sourcePhase !== 'idle' && !force) return;
        byId('packmanager-source-mask').hidden = true;
    }
    function saveSources() {
        if (state.sourcePhase !== 'idle') return;
        var indexUrl = byId('packmanager-index-url').value.replace(/^\s+|\s+$/g, '');
        var proxyUrl = byId('packmanager-proxy-url').value.replace(/^\s+|\s+$/g, '');
        if (!/^https:\/\/\S+$/.test(indexUrl)) { setModalError('packmanager-source-error', tr('invalidIndexUrl', '插件列表地址必须是 HTTPS URL。'), byId('packmanager-index-url')); return; }
        if (proxyUrl && (!/^https:\/\/\S+\/$/.test(proxyUrl))) { setModalError('packmanager-source-error', tr('invalidProxyUrl', 'GitHub 代理必须是以 / 结尾的 HTTPS 前缀。'), byId('packmanager-proxy-url')); return; }
        state.sourcePhase = 'saving';
        setSourceModalBusy(true);
        setBusy(true);
        setModalError('packmanager-source-error', '');
        setMessage(tr('checkingSource', '正在连接并校验新软件源…'));
        setSourceState('loading', tr('sourceRefreshing', '正在刷新软件源'));
        api('settings', 'POST', { indexUrl: indexUrl, githubProxy: proxyUrl }, 90000).then(function (data) {
            state.sourcePhase = 'idle';
            setSourceModalBusy(false);
            setBusy(false);
            closeSourceModal(true);
            applyCatalog(data);
            setMessage(tr('sourceSaved', '软件源设置已保存。'));
        }).catch(function (error) {
            state.sourcePhase = 'idle';
            setSourceModalBusy(false);
            setBusy(false);
            setSourceState('error', tr('sourceError', '软件源不可用'));
            setModalError('packmanager-source-error', error.message);
        });
    }

    var tabs = document.querySelectorAll('.packmanager-tab');
    for (var tabIndex = 0; tabIndex < tabs.length; tabIndex += 1) {
        tabs[tabIndex].onclick = function () {
            state.filter = this.getAttribute('data-filter') || 'all';
            for (var index = 0; index < tabs.length; index += 1) tabs[index].className = 'packmanager-tab';
            this.className = 'packmanager-tab active';
            renderEntries();
        };
    }
    byId('packmanager-search').oninput = function () { state.query = this.value.toLowerCase().replace(/^\s+|\s+$/g, ''); renderEntries(); };
    byId('packmanager-refresh').onclick = function () { loadCatalog(true).catch(function () {}); };
    byId('packmanager-open-sources').onclick = openSourceModal;
    byId('packmanager-source-close').onclick = closeSourceModal;
    byId('packmanager-source-cancel').onclick = closeSourceModal;
    byId('packmanager-source-save').onclick = saveSources;
    byId('packmanager-source-defaults').onclick = function () {
        byId('packmanager-index-preset').value = 'official';
        selectIndexPreset('official');
        byId('packmanager-proxy-preset').value = 'direct';
        selectProxyPreset('direct');
    };
    byId('packmanager-index-preset').onchange = function () { selectIndexPreset(this.value); };
    byId('packmanager-proxy-preset').onchange = function () { selectProxyPreset(this.value); };
    byId('packmanager-index-url').oninput = function () {
        if (this.value !== config.officialIndex && this.value !== config.jsdelivrIndex) byId('packmanager-index-preset').value = 'custom';
    };
    byId('packmanager-proxy-url').oninput = function () {
        if (this.value && this.value !== config.ghfastProxy) byId('packmanager-proxy-preset').value = 'custom';
    };
    byId('packmanager-source-mask').onclick = function (event) { if (event.target === this) closeSourceModal(); };
    byId('packmanager-install-close').onclick = discardPending;
    byId('packmanager-install-cancel').onclick = discardPending;
    byId('packmanager-install-confirm').onclick = confirmInstall;
    byId('packmanager-install-mask').onclick = function (event) { if (event.target === this) discardPending(); };
    function handleKeydown(event) {
        event = event || window.event;
        if (event.keyCode !== 27) return;
        if (!byId('packmanager-install-mask').hidden) { discardPending(); }
        else if (!byId('packmanager-source-mask').hidden) { closeSourceModal(); }
    }
    if (document.addEventListener) document.addEventListener('keydown', handleKeydown, false);
    else if (document.attachEvent) document.attachEvent('onkeydown', handleKeydown);

    loadLanguage().then(function () {
        return api('status', 'GET', null, 30000);
    }).then(function (data) {
        state.status = data;
        state.catalog = { plugins: [], installed: data.installed || [], settings: data.settings || {} };
        renderEntries();
        return loadCatalog(false);
    }).catch(function (error) {
        setMessage(error.message, true);
        setSourceState('error', tr('sourceError', '软件源不可用'));
    });
}());
