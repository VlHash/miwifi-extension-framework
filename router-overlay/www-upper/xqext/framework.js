(function () {
    'use strict';

    var config = window.MWEF_CONFIG || {};
    var state = { data: null, i18n: {}, modal: null, update: null, updateBusy: false };
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
    function request(action, method, payload, timeout) {
        return new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            xhr.open(method || 'GET', config.apiUrl + '?action=' + encodeURIComponent(action), true);
            xhr.timeout = timeout || 20000;
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
    function renderContributors(contributors) {
        var container = byId('mwef-contributors');
        var rendered = 0;
        clear(container);

        (contributors || []).forEach(function (contributor) {
            var login = contributor && typeof contributor.login === 'string' ? contributor.login : '';
            if (rendered >= 16 || !/^[A-Za-z0-9-]{1,39}$/.test(login)) return;

            var profile = el('a', 'mwef-contributor');
            profile.href = 'https://github.com/' + encodeURIComponent(login);
            profile.target = '_blank';
            profile.rel = 'noopener noreferrer';
            profile.title = typeof contributor.contributions === 'number'
                ? tr('contributionCount', '{count} contributions').replace('{count}', String(contributor.contributions))
                : login;

            if (typeof contributor.avatar_url === 'string' && /^https:\/\/avatars\.githubusercontent\.com\//.test(contributor.avatar_url)) {
                var avatar = document.createElement('img');
                avatar.src = contributor.avatar_url + (contributor.avatar_url.indexOf('?') === -1 ? '?s=64' : '&s=64');
                avatar.alt = '';
                avatar.width = 32;
                avatar.height = 32;
                avatar.loading = 'lazy';
                avatar.referrerPolicy = 'no-referrer';
                profile.appendChild(avatar);
            } else {
                profile.appendChild(el('span', 'mwef-contributor-fallback', login.charAt(0).toUpperCase()));
            }
            profile.appendChild(el('span', 'mwef-contributor-name', login));
            container.appendChild(profile);
            rendered += 1;
        });

        if (!rendered) {
            renderContributors([{ login: 'VlHash', contributions: null }]);
        }
    }
    function loadContributors() {
        if (!config.contributorsUrl) {
            renderContributors([{ login: 'VlHash', contributions: null }]);
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.open('GET', config.contributorsUrl, true);
        xhr.timeout = 10000;
        xhr.setRequestHeader('Accept', 'application/vnd.github+json');
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) return;
            var contributors = null;
            try { if (xhr.status === 200) contributors = JSON.parse(xhr.responseText); } catch (error) {}
            renderContributors(Array.isArray(contributors) ? contributors : [{ login: 'VlHash', contributions: null }]);
        };
        xhr.onerror = function () { renderContributors([{ login: 'VlHash', contributions: null }]); };
        xhr.ontimeout = xhr.onerror;
        xhr.send(null);
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
        byId('mwef-update-current').textContent = 'v' + data.framework.version;
        byId('mwef-language').value = data.settings.language;
        syncBeautifiedSelect(byId('mwef-language'));
        byId('mwef-plugin-directory').value = data.settings.pluginDirectory;
        renderPlugins(data.plugins);
    }
    function loadLanguage(language) {
        return new Promise(function (resolve) {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '/xqext/i18n/' + encodeURIComponent(language) + '.json?v=0.2.5', true);
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

    function replaceTokens(template, values) {
        var result = template;
        Object.keys(values || {}).forEach(function (key) {
            result = result.replace(new RegExp('\\{' + key + '\\}', 'g'), String(values[key]));
        });
        return result;
    }
    function setUpdateBusy(busy) {
        state.updateBusy = !!busy;
        byId('mwef-check-update').disabled = state.updateBusy;
        byId('mwef-online-update').disabled = state.updateBusy;
        byId('mwef-choose-framework-package').disabled = state.updateBusy;
    }
    function renderUpdateStatus(data) {
        state.update = data;
        var status = byId('mwef-update-status');
        status.textContent = data.updateAvailable
            ? replaceTokens(tr('updateAvailable', '发现新版本 v{version}'), { version: data.latestVersion })
            : replaceTokens(tr('frameworkUpToDate', 'v{version} 是索引中的最新版本'), { version: data.latestVersion });
        var notes = byId('mwef-update-notes');
        if (typeof data.notesUrl === 'string' && /^https:\/\/github\.com\/VlHash\/miwifi-extension-framework\/releases\/tag\//.test(data.notesUrl)) {
            notes.href = data.notesUrl;
            notes.hidden = false;
        } else {
            notes.hidden = true;
            notes.removeAttribute('href');
        }
    }
    function checkFrameworkUpdate(showMessage) {
        setUpdateBusy(true);
        if (showMessage !== false) setMessage(tr('checkingUpdate', '正在检查框架更新…'));
        return request('framework-check', 'GET', null, 60000).then(function (data) {
            renderUpdateStatus(data);
            if (showMessage !== false) setMessage('');
            return data;
        }).catch(function (error) {
            setMessage(error.message, true);
            throw error;
        }).then(function (data) {
            setUpdateBusy(false);
            return data;
        }, function (error) {
            setUpdateBusy(false);
            throw error;
        });
    }
    function finishFrameworkUpdate(data) {
        setMessage(replaceTokens(tr('frameworkUpdateComplete', '框架 v{version} 已安装，正在重新载入…'), { version: data.version }));
        window.setTimeout(function () { window.location.reload(); }, 1600);
    }
    function startOnlineUpdate() {
        var ready = state.update ? Promise.resolve(state.update) : checkFrameworkUpdate(true);
        ready.then(function (data) {
            var current = state.data.framework.version;
            var prompt = data.latestVersion === current
                ? replaceTokens(tr('sameVersionUpdateConfirm', '确定从已验证的在线 Release 重新安装 MWEF v{version}？当前框架会保留用于恢复。'), { version: current })
                : replaceTokens(tr('onlineUpdateConfirm', '确定将 MWEF 从 v{current} 更新到 v{latest}？当前框架会保留在恢复目录。'), {
                    current: current,
                    latest: data.latestVersion
                });
            if (!window.confirm(prompt)) return;
            setUpdateBusy(true);
            setMessage(tr('updatingFramework', '正在验证并更新框架，请勿关闭页面…'));
            request('framework-online', 'POST', {}, 240000).then(finishFrameworkUpdate).catch(function (error) {
                setUpdateBusy(false);
                setMessage(error.message, true);
            });
        }).catch(function () {});
    }
    function uploadFrameworkRelease(file) {
        if (!file) return;
        var lower = file.name.toLowerCase();
        if (lower.slice(-7) !== '.tar.gz' && lower.slice(-4) !== '.tgz') {
            setMessage(tr('frameworkPackageExtension', '请选择 MWEF .tar.gz 或 .tgz Release 包。'), true);
            return;
        }
        if (!file.size || file.size > 16 * 1024 * 1024) {
            setMessage(tr('frameworkPackageSize', '框架 Release 包必须小于 16 MiB。'), true);
            return;
        }
        setUpdateBusy(true);
        setMessage(tr('uploadingFramework', '正在上传并检查框架 Release…'));
        var uploadToken = null;
        request('framework-upload-start', 'POST', { filename: file.name, size: file.size }, 30000).then(function (start) {
            uploadToken = start.uploadToken;
            return uploadFrameworkChunks(file, start.uploadToken, start.chunkSize || 32768);
        }).then(function () {
            return request('framework-upload-finish', 'POST', { token: uploadToken }, 90000);
        }).then(function (data) {
            var prompt = replaceTokens(tr('uploadUpdateConfirm', '确定从上传的 Release 安装 MWEF v{version}？当前已安装 v{current}。'), {
                version: data.release.version,
                current: data.release.currentVersion
            });
            if (!window.confirm(prompt)) {
                request('framework-discard', 'POST', { token: data.pendingToken }, 30000).catch(function () {});
                setUpdateBusy(false);
                setMessage('');
                return;
            }
            setMessage(tr('updatingFramework', '正在验证并更新框架，请勿关闭页面…'));
            request('framework-apply', 'POST', { token: data.pendingToken }, 240000).then(finishFrameworkUpdate).catch(function (error) {
                setUpdateBusy(false);
                setMessage(error.message, true);
            });
        }).catch(function (error) {
            if (uploadToken) request('framework-discard', 'POST', { token: uploadToken }, 30000).catch(function () {});
            setUpdateBusy(false);
            setMessage(error.message, true);
        });
    }
    function uploadFrameworkChunk(token, sequence, blob) {
        return new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            var url = config.apiUrl + '?action=framework-upload-chunk&token=' + encodeURIComponent(token)
                + '&sequence=' + encodeURIComponent(sequence);
            var form = new FormData();
            form.append('chunk', blob, 'chunk.bin');
            xhr.open('POST', url, true);
            xhr.timeout = 45000;
            xhr.setRequestHeader('Accept', 'application/json');
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
            xhr.send(form);
        });
    }
    function uploadFrameworkChunks(file, token, chunkSize) {
        var offset = 0;
        var sequence = 0;
        function next() {
            if (offset >= file.size) return Promise.resolve();
            var end = Math.min(offset + chunkSize, file.size);
            var blob = file.slice(offset, end);
            return uploadFrameworkChunk(token, sequence, blob).then(function () {
                offset = end;
                sequence += 1;
                return next();
            });
        }
        return next();
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
    byId('mwef-check-update').onclick = function () { checkFrameworkUpdate(true).catch(function () {}); };
    byId('mwef-online-update').onclick = startOnlineUpdate;
    byId('mwef-choose-framework-package').onclick = function () { byId('mwef-framework-package').click(); };
    byId('mwef-framework-package').onchange = function () { uploadFrameworkRelease(this.files && this.files[0]); this.value = ''; };
    byId('mwef-modal-close').onclick = closeModal;
    byId('mwef-modal-cancel').onclick = closeModal;
    byId('mwef-modal-confirm').onclick = confirmModal;
    byId('mwef-modal-mask').onclick = function (event) { if (event.target === this) closeModal(); };

    refresh().then(loadContributors);
}());
