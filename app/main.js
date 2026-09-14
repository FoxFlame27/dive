// Dive demo — desktop app. Hosts the Dive desktop and gives it real access to this machine:
// files in your home folder, a real shell, real web pages, CPU and memory.
const { app, BrowserWindow, Menu, nativeImage, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const fsp = require('fs/promises');
const os = require('os');
const { exec } = require('child_process');

const smoke = process.argv.includes('--smoke');
const HOME = os.homedir();
const safe = p => { const r = path.resolve(p); if (!r.startsWith(HOME) && !r.startsWith('/tmp') && !r.startsWith('/Volumes') && !/^[A-Z]:\\/.test(r)) throw new Error('Outside home: ' + r); return r; };
const TEXT_EXT = new Set(['.txt','.md','.js','.mjs','.ts','.json','.py','.sh','.css','.html','.htm','.xml','.yml','.yaml','.toml','.ini','.cfg','.conf','.csv','.log','.ps1','.bat','.c','.h','.cpp','.java','.rs','.go','.rb','.php','.sql','.tex','']);

ipcMain.handle('info', () => ({ home: HOME, user: os.userInfo().username, host: os.hostname(), platform: process.platform, sep: path.sep }));
ipcMain.handle('listDir', async (_e, p) => {
  const dir = safe(p); const out = [];
  for (const d of await fsp.readdir(dir, { withFileTypes: true })) {
    if (d.name.startsWith('.')) continue;
    let size = 0, mtime = 0;
    try { const st = await fsp.stat(path.join(dir, d.name)); size = st.size; mtime = st.mtimeMs; } catch {}
    out.push({ name: d.name, dir: d.isDirectory(), size, mtime, text: !d.isDirectory() && TEXT_EXT.has(path.extname(d.name).toLowerCase()) });
  }
  return out;
});
ipcMain.handle('readText', async (_e, p) => { const st = await fsp.stat(safe(p)); if (st.size > 2e6) return '[file too large to open here: ' + st.size + ' bytes]'; return fsp.readFile(safe(p), 'utf8'); });
ipcMain.handle('writeText', (_e, p, t) => fsp.writeFile(safe(p), t, 'utf8'));
ipcMain.handle('mkdir', (_e, p) => fsp.mkdir(safe(p), { recursive: true }));
ipcMain.handle('rename', (_e, a, b) => fsp.rename(safe(a), safe(b)));
ipcMain.handle('trash', (_e, p) => shell.trashItem(safe(p)));
ipcMain.handle('openPath', (_e, p) => shell.openPath(safe(p)));
ipcMain.handle('openExternal', (_e, u) => shell.openExternal(u));
ipcMain.handle('exec', (_e, cmd, cwd) => new Promise(res => exec(cmd, { cwd: cwd || HOME, timeout: 20000, maxBuffer: 4e6, shell: process.platform === 'win32' ? 'powershell.exe' : '/bin/zsh', env: { ...process.env, TERM: 'dumb', CLICOLOR: '0' } }, (err, stdout, stderr) => res({ out: stdout, err: stderr, code: err ? (err.code ?? 1) : 0 }))));
let lastCpu = null;
ipcMain.handle('sysInfo', () => {
  const cpus = os.cpus(); const now = cpus.map(c => ({ idle: c.times.idle, total: Object.values(c.times).reduce((a, b) => a + b, 0) }));
  let load = 0; if (lastCpu) { const d = now.map((c, i) => { const t = c.total - lastCpu[i].total, id = c.idle - lastCpu[i].idle; return t ? 1 - id / t : 0; }); load = d.reduce((a, b) => a + b, 0) / d.length; }
  lastCpu = now;
  return { cpu: load, cores: cpus.length, model: cpus[0]?.model || 'CPU', memTotal: os.totalmem(), memFree: os.freemem(), uptime: os.uptime(), platform: `${os.type()} ${os.release()}`, host: os.hostname() };
});
ipcMain.handle('processes', () => new Promise(res => exec(process.platform === 'win32' ? 'powershell -c "Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Id,CPU,WorkingSet,ProcessName | Format-Table -HideTableHeaders"' : 'ps -Ao pid,pcpu,pmem,comm -r | head -16', { timeout: 5000 }, (err, out) => res(out || ''))));
ipcMain.handle('scanTransfer', async () => {
  const dirs = ['Desktop', 'Documents', 'Pictures', 'Downloads', 'Music', 'Videos', 'Movies'];
  const res = [];
  for (const d of dirs) {
    const p = path.join(HOME, d); if (!fs.existsSync(p)) continue;
    let files = 0, bytes = 0;
    const walk = async (dir, depth) => { if (depth > 3) return; let ents = []; try { ents = await fsp.readdir(dir, { withFileTypes: true }); } catch { return; } for (const e of ents) { if (e.name.startsWith('.')) continue; const fp = path.join(dir, e.name); if (e.isDirectory()) await walk(fp, depth + 1); else { files++; try { bytes += (await fsp.stat(fp)).size; } catch {} } } };
    await walk(p, 0); res.push({ name: d, files, bytes });
  }
  return { home: HOME, dirs: res, apps: fs.existsSync('/Applications') ? fs.readdirSync('/Applications').filter(n => n.endsWith('.app')).map(n => n.replace(/\.app$/, '')).slice(0, 40) : [] };
});

function create() {
  const win = new BrowserWindow({
    width: 1440, height: 940, minWidth: 900, minHeight: 600, title: 'Dive', backgroundColor: '#05070a', show: false,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    icon: path.join(__dirname, fs.existsSync(path.join(__dirname, 'icon.png')) ? 'icon.png' : 'icon.icns'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false, webviewTag: true },
  });
  const local = path.join(__dirname, 'dive.html');
  const file = fs.existsSync(local) ? local : path.join(__dirname, '..', 'prototype', 'dive.html');
  win.loadFile(file, { query: { app: '1' }, hash: 'desktop' });
  win.once('ready-to-show', () => { if (smoke) { console.log('SMOKE OK ' + file); setTimeout(() => app.quit(), 1500); } else if (!process.env.DIVE_HEADLESS) win.show(); });
  win.webContents.on('console-message', (_e, level, msg) => { if (smoke && level >= 2) console.log('CONSOLE', msg); });
  win.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
}
app.whenReady().then(() => {
  if (process.platform === 'darwin' && fs.existsSync(path.join(__dirname, 'icon.png'))) app.dock.setIcon(nativeImage.createFromPath(path.join(__dirname, 'icon.png')));
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Dive', submenu: [{ role: 'about' }, { type: 'separator' }, { role: 'togglefullscreen' }, { role: 'reload' }, { type: 'separator' }, { role: 'quit' }] },
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'togglefullscreen' }, { role: 'toggleDevTools' }] },
  ]));
  create();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) create(); });
});
app.on('window-all-closed', () => app.quit());
