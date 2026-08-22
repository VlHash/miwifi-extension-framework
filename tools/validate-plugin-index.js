'use strict';

var fs = require('fs');

var INDEX_PATH = 'index.json';
var MAX_INDEX_SIZE = 1024 * 1024;
var EXPECTED_SCHEMA = 'https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/index.schema.json';
var PERMISSIONS = {
    'system.read': true,
    'filesystem.read': true,
    'filesystem.write': true,
    'network.client': true,
    'service.control': true,
    'shell.execute': true
};

function fail(message) {
    throw new Error('MWEF plugin index: ' + message);
}

function exactKeys(value, allowed, context) {
    Object.keys(value).forEach(function (key) {
        if (allowed.indexOf(key) === -1) fail(context + ' contains unsupported field ' + key);
    });
}

function nonEmptyString(value, context, maximum) {
    if (typeof value !== 'string' || !value.length || value.length > maximum) {
        fail(context + ' must be a non-empty string of at most ' + maximum + ' characters');
    }
}

function localized(value, context) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) fail(context + ' must be an object');
    exactKeys(value, ['en', 'zh-CN'], context);
    nonEmptyString(value.en, context + '.en', 256);
    nonEmptyString(value['zh-CN'], context + '.zh-CN', 256);
}

function httpsUrl(value, context) {
    nonEmptyString(value, context, 512);
    var parsed;
    try { parsed = new URL(value); } catch (error) { fail(context + ' must be a valid URL'); }
    if (parsed.protocol !== 'https:') fail(context + ' must use HTTPS');
}

function validatePlugin(plugin, ids, index) {
    var context = 'plugins[' + index + ']';
    if (!plugin || typeof plugin !== 'object' || Array.isArray(plugin)) fail(context + ' must be an object');
    exactKeys(plugin, [
        'id', 'name', 'description', 'version', 'author', 'license', 'mwef', 'permissions',
        'archive', 'homepage', 'source', 'published', 'changelog', 'categories'
    ], context);

    if (typeof plugin.id !== 'string' || !/^[a-z][a-z0-9_-]{0,47}$/.test(plugin.id)) fail(context + '.id is invalid');
    if (ids[plugin.id]) fail('duplicate plugin id ' + plugin.id);
    ids[plugin.id] = true;
    localized(plugin.name, context + '.name');
    localized(plugin.description, context + '.description');
    nonEmptyString(plugin.version, context + '.version', 32);
    if (!/^[0-9A-Za-z][0-9A-Za-z.+-]{0,31}$/.test(plugin.version)) fail(context + '.version is invalid');
    nonEmptyString(plugin.author, context + '.author', 80);
    nonEmptyString(plugin.license, context + '.license', 32);
    nonEmptyString(plugin.mwef, context + '.mwef', 64);

    if (!Array.isArray(plugin.permissions)) fail(context + '.permissions must be an array');
    var seenPermissions = {};
    plugin.permissions.forEach(function (permission) {
        if (!PERMISSIONS[permission]) fail(context + ' requests unsupported permission ' + permission);
        if (seenPermissions[permission]) fail(context + ' repeats permission ' + permission);
        seenPermissions[permission] = true;
    });

    if (!plugin.archive || typeof plugin.archive !== 'object' || Array.isArray(plugin.archive)) fail(context + '.archive must be an object');
    exactKeys(plugin.archive, ['url', 'sha256', 'size'], context + '.archive');
    httpsUrl(plugin.archive.url, context + '.archive.url');
    if (typeof plugin.archive.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(plugin.archive.sha256)) fail(context + '.archive.sha256 is invalid');
    if (!Number.isInteger(plugin.archive.size) || plugin.archive.size < 1 || plugin.archive.size > 8388608) fail(context + '.archive.size is invalid');
    httpsUrl(plugin.homepage, context + '.homepage');
    httpsUrl(plugin.source, context + '.source');

    if (plugin.published !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(plugin.published)) fail(context + '.published is invalid');
    if (plugin.changelog !== undefined) httpsUrl(plugin.changelog, context + '.changelog');
    if (plugin.categories !== undefined) {
        if (!Array.isArray(plugin.categories) || plugin.categories.length > 16) fail(context + '.categories is invalid');
        var seenCategories = {};
        plugin.categories.forEach(function (category) {
            if (typeof category !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(category)) fail(context + ' contains an invalid category');
            if (seenCategories[category]) fail(context + ' repeats category ' + category);
            seenCategories[category] = true;
        });
    }
}

if (fs.statSync(INDEX_PATH).size > MAX_INDEX_SIZE) fail('index.json exceeds 1 MiB');
var index = JSON.parse(fs.readFileSync(INDEX_PATH, 'utf8'));
if (!index || typeof index !== 'object' || Array.isArray(index)) fail('index.json must contain an object');
exactKeys(index, ['$schema', 'schemaVersion', 'name', 'maintainer', 'updated', 'plugins'], 'index');
if (index.$schema !== EXPECTED_SCHEMA) fail('$schema is invalid');
if (index.schemaVersion !== 1) fail('unsupported schemaVersion');
nonEmptyString(index.name, 'name', 80);
nonEmptyString(index.maintainer, 'maintainer', 80);
if (typeof index.updated !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(index.updated)) fail('updated is invalid');
if (!Array.isArray(index.plugins) || index.plugins.length > 512) fail('plugins must contain at most 512 entries');

var ids = {};
index.plugins.forEach(function (plugin, position) { validatePlugin(plugin, ids, position); });
process.stdout.write('MWEF plugin index valid: ' + index.plugins.length + ' plugin(s)\n');
