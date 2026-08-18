(function () {
    'use strict';

    var config = window.MWEF_CONFIG || {};
    var state = { data: null, i18n: {}, modal: null };
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
    function applyTranslations() {
        var nodes = document.querySelectorAll('[data-i18n]');
        for (var i = 0; i < nodes.length; i += 1) {
            var key = nodes[i].getAttribute('data-i18n');
            if (state.i18n[key]) nodes[i].textContent = state.i18n[key];
        }
    }
    function encode(values) {
        var parts = [];
        Object.keys(values || {}).forEach(function (key) {
            parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(values[key] == null ? '' : values[key]));
        });
        return parts.join('&');
    }
    function request(action, method, payload) {
        return new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            xhr.open(method || 'GET', config.apiUrl + '?action=' + encodeURIComponent(action), true);
            xhr.timeout = 20000;
            xhr.setRequestHeader('Accept', 'application/json');
            if (payload && !(payload instanceof FormData)) {
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
    function setMessage(message, error) {
        var node = byId('mwef-message');
        node.hidden = !message;
        node.className = 'mwef-message' + (error ? ' error' : '');
        node.textContent = message || '';
    }
    function localized(value) {
        if (!value) return '';
        if (typeof value === 'string') return value;
        var language = state.data && state.data.settings ? state.data.settings.language : 'zh-CN';
        return value[language] || value['zh-CN'] || value.en || '';
    }
    function button(label, className, handler, disabled) {
        var node = el('button', 'mwef-btn mwef-btn-small ' + (className || ''), label);
        node.type = 'button';
        node.disabled = !!disabled;
        if (!disabled) node.onclick = handler;
        return node;
    }
    function syncBeautifiedSelect(select) {
        if (!select) return;
        var jq = window.jQuery || window.$;
        if (jq && typeof jq.selectBeautify === 'function' && !jq(select).siblings('.textContent').length) {
            jq.selectBeautify({ container: '#mwef-general-settings' });
        }
        var dummy = select.parentNode && select.parentNode.querySelector('.textContent .dummy');
        var option = select.options[select.selectedIndex];
        if (dummy && option) dummy.textContent = option.textContent || option.innerText || '';
    }
    function renderPlugins(plugins) {
        var body = byId('mwef-plugin-list');
        clear(body);
        if (!plugins || !plugins.length) {
            var emptyRow = el('tr');
            var emptyCell = el('td', 'mwef-empty', tr('noPlugins', '尚未安装插件'));
            emptyCell.colSpan = 5;
            emptyRow.appendChild(emptyCell);
            body.appendChild(emptyRow);
            return;
        }
        plugins.forEach(function (plugin) {
            var row = el('tr');
            var nameCell = el('td');
            nameCell.appendChild(el('span', 'mwef-plugin-name', plugin.name || plugin.id));
            nameCell.appendChild(el('small', 'mwef-plugin-id', plugin.id +
                (plugin.builtin ? ' · ' + tr('builtIn', '内置') : '')));
            row.appendChild(nameCell);
            row.appendChild(el('td', '', plugin.version || '--'));
            var statusCell = el('td');
            statusCell.appendChild(el('span', 'mwef-badge ' + (plugin.enabled ? 'on' : ''),
                plugin.enabled ? tr('enabled', '已启用') : tr('disabled', '已停用')));
            row.appendChild(statusCell);
            row.appendChild(el('td', 'mwef-permission-text',
                plugin.grants && plugin.grants.length ? plugin.grants.join(', ') : tr('noGrants', '未授予额外权限')));
            var actions = el('td');
            actions.appendChild(button(tr('permissions', '权限'), '', function () { openPermissionEditor(plugin); }));
            if (!plugin.builtin) {
                actions.appendChild(button(plugin.enabled ? tr('disable', '停用') : tr('enable', '启用'), '', function () {
                    mutatePlugin(plugin.enabled ? 'disable' : 'enable', plugin.id);
                }));
                actions.appendChild(button(tr('remove', '移除'), 'mwef-btn-danger', function () {
                    if (window.confirm(tr('removeConfirm', '插件将移至恢复目录，确定继续？'))) mutatePlugin('remove', plugin.id);
                }));
            }
            row.appendChild(actions);
            body.appendChild(row);
        });
    }
    function render(data) {
        state.data = data;
        byId('mwef-name').textContent = data.framework.name;
        byId('mwef-version').textContent = 'v' + data.framework.version;
        byId('mwef-language').value = data.settings.language;
        syncBeautifiedSelect(byId('mwef-language'));
        byId('mwef-plugin-directory').value = data.settings.pluginDirectory;
        renderPlugins(data.plugins);
    }
    function loadLanguage(language) {
        return new Promise(function (resolve) {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '/xqext/i18n/' + encodeURIComponent(language) + '.json?v=0.2.2', true);
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
    function refresh() {
        return request('status').then(function (data) {
            return loadLanguage(data.settings.language).then(function () { render(data); setMessage(''); });
        }).catch(function (error) { setMessage(error.message, true); });
    }
    function mutatePlugin(action, id, grants) {
        setMessage(tr('applying', '正在应用并重新 patch…'));
        request(action, 'POST', { id: id, grants: grants || '' }).then(function (data) {
            render(data);
            setMessage(tr('applied', '操作已完成。'));
        }).catch(function (error) { setMessage(error.message, true); });
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
    function openModal(mode, plugin, token) {
        state.modal = { mode: mode, plugin: plugin, token: token || null };
        byId('mwef-pending-name').textContent = (plugin.name || plugin.id) + ' · ' + (plugin.version || '--');
        byId('mwef-pending-description').textContent = localized(plugin.description);
        var list = byId('mwef-permission-list');
        clear(list);
        var grants = {};
        (plugin.grants || []).forEach(function (item) { grants[item] = true; });
        (plugin.permissions || []).forEach(function (permission) { list.appendChild(permissionOption(permission, grants[permission])); });
        if (!plugin.permissions || !plugin.permissions.length) list.appendChild(el('p', 'mwef-tip', tr('noPermissionsRequested', '此插件未申请额外权限。')));
        byId('mwef-modal-title').textContent = mode === 'install' ? tr('permissionReview', '权限确认') : tr('managePermissions', '管理插件权限');
        byId('mwef-modal-confirm').textContent = mode === 'install' ? tr('confirmInstall', '确认安装') : tr('savePermissions', '保存权限');
        byId('mwef-modal-mask').hidden = false;
    }
    function closeModal() { byId('mwef-modal-mask').hidden = true; state.modal = null; }
    function selectedGrants() {
        var result = [];
        var inputs = byId('mwef-permission-list').querySelectorAll('input:checked');
        for (var i = 0; i < inputs.length; i += 1) result.push(inputs[i].value);
        return result.join(',');
    }
    function openPermissionEditor(plugin) { openModal('permissions', plugin); }
    function confirmModal() {
        if (!state.modal) return;
        var modal = state.modal;
        var grants = selectedGrants();
        closeModal();
        setMessage(tr('applying', '正在应用并重新 patch…'));
        if (modal.mode === 'install') {
            request('install', 'POST', { token: modal.token, grants: grants }).then(function (data) {
                render(data);
                setMessage(tr('installComplete', '插件已安装并完成重新 patch。'));
            }).catch(function (error) { setMessage(error.message, true); });
        } else {
            mutatePlugin('permissions', modal.plugin.id, grants);
        }
    }
    function uploadPackage(file) {
        if (!file) return;
        var lower = file.name.toLowerCase();
        if (lower.slice(-7) !== '.tar.gz' && lower.slice(-4) !== '.tgz') {
            setMessage(tr('packageExtension', '请选择 .tar.gz 或 .tgz 插件包。'), true);
            return;
        }
        var form = new FormData();
        form.append('package', file, file.name);
        setMessage(tr('uploading', '正在上传并检查插件包…'));
        request('upload', 'POST', form).then(function (data) {
            setMessage('');
            openModal('install', data.plugin, data.pendingToken);
        }).catch(function (error) { setMessage(error.message, true); });
    }

    byId('mwef-save-settings').onclick = function () {
        setMessage(tr('applying', '正在保存并重新 patch…'));
        request('settings', 'POST', {
            language: byId('mwef-language').value,
            pluginDirectory: byId('mwef-plugin-directory').value
        }).then(function () { window.location.reload(); })
            .catch(function (error) { setMessage(error.message, true); });
    };
    byId('mwef-choose-package').onclick = function () { byId('mwef-package').click(); };
    byId('mwef-package').onchange = function () { uploadPackage(this.files && this.files[0]); this.value = ''; };
    byId('mwef-modal-close').onclick = closeModal;
    byId('mwef-modal-cancel').onclick = closeModal;
    byId('mwef-modal-confirm').onclick = confirmModal;
    byId('mwef-modal-mask').onclick = function (event) { if (event.target === this) closeModal(); };

    refresh();
}());
