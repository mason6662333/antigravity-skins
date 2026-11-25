'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const root = path.join(os.homedir(), 'Library/Application Support/Antigravity Skins');
const selection = path.join(root, 'selection.json');
const fallback = {id:'crayon-shin-chan',revision:'initial'};
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
function selected() {
  try { return read(selection); } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
}
let cached;
function stylesheet(id) {
  if (cached?.id === id) return cached.css;
  const resources = process.resourcesPath;
  let css = fs.readFileSync(path.join(resources, 'shinchan.css'), 'utf8');
  if (id !== fallback.id) {
    const themes = read(path.join(root, 'Library', 'catalog.json'));
    const theme = themes.find(item => item.id === id);
    if (!theme || !/^[a-z0-9-]+$/.test(id) || !/^background\.(png|jpg|webp)$/.test(theme.image) || !/^#[\da-f]{6}$/i.test(theme.accent)) throw Error('无效的皮肤资源');
    const file = path.join(root, 'Library', id, theme.image);
    const mime = {png:'png',jpg:'jpeg',webp:'webp'}[theme.image.split('.')[1]];
    const data = fs.readFileSync(file);
    css = css.replace(/data:image\/png;base64,[A-Za-z0-9+/=]+/, () => 'data:image/'+mime+';base64,'+data.toString('base64'))
      .replaceAll('#cd2316', theme.accent)
      .replace('#b01e13', 'color-mix(in srgb, '+theme.accent+' 70%, black)')
      .replace('#ffa79b', 'color-mix(in srgb, '+theme.accent+' 65%, white)');
    if (id.startsWith('snow-night-homeward')) {
      const opacity = id.endsWith('atmosphere') ? '.81' : id.endsWith('readable') ? '.97' : '.9';
      css += '\nbody.theme-dark { --shin-reading: rgba(12,25,46,'+opacity+'); --shin-rail: rgba(8,18,36,.76); --shin-veil: rgba(8,16,34,.28); }';
    }
  }
  cached = {id,css};
  return css;
}
function acknowledge(request) {
  const current = selected();
  if (current.revision !== request.revision || current.id !== request.id) return;
  const dest = path.join(root, 'applied.json');
  let previous;
  try { previous = read(dest); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  if (previous?.revision === request.revision && previous?.id === request.id) return;
  const recent = [request.id, ...(previous?.recent || [fallback.id]).filter(id => id !== request.id)];
  fs.mkdirSync(root, {recursive:true});
  const tmp = dest+'.'+process.pid+'.tmp';
  fs.writeFileSync(tmp, JSON.stringify({...request,recent}), {mode:0o600});
  fs.renameSync(tmp, dest);
}
exports.attach = function attach(contents, hubURL) {
  const origin = new URL(hubURL).origin;
  let generation = 0, key, last, queued = false, running = false;
  function local() {
    if (contents.isDestroyed()) return false;
    try {
      const page = new URL(contents.getURL());
      return page.origin === origin && page.protocol === 'https:' && page.hostname === '127.0.0.1';
    } catch { return false; }
  }
  async function update() {
    queued = true;
    if (running) return;
    running = true;
    try {
      while (queued && local()) {
        queued = false;
        const request = selected();
        if (last === request.revision) continue;
        const epoch = generation;
        const next = await contents.insertCSS(stylesheet(request.id), {cssOrigin:'user'});
        if (!local() || epoch !== generation) continue;
        const prev = key;
        key = next;
        if (prev) await contents.removeInsertedCSS(prev);
        if (!local() || epoch !== generation) continue;
        acknowledge(request);
        last = request.revision;
      }
    } catch (e) { console.warn('Antigravity Skins:', e.message); }
    finally { running = false; }
  }
  contents.on('did-start-navigation', (_event, _url, inPlace, main) => {
    if (main && !inPlace) { generation++; key = last = undefined; }
  });
  contents.on('did-finish-load', update);
  fs.watchFile(selection, {interval:350, persistent:false}, update);
  contents.once('destroyed', () => fs.unwatchFile(selection, update));
};
