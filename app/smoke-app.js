// Runs inside Electron: opens the real-machine apps and reports. node_modules/.bin/electron smoke-app.js
const { app, BrowserWindow, ipcMain } = require('electron');
require('./main.js');
app.whenReady().then(() => setTimeout(async () => {
  const win = BrowserWindow.getAllWindows()[0];
  const r = await win.webContents.executeJavaScript(`(async () => { const D = window.__dive; const sleep = ms => new Promise(r => setTimeout(r, ms)); const out = []; try {
    await sleep(800);
    const f = D.WM.get('files') || D.WM.open('files'); await sleep(600); out.push('files real items=' + f.querySelectorAll('.fs-item').length + ' title=' + f.querySelector('.tname').textContent);
    const t = D.WM.open('term'); const inp = t.querySelector('.in input'); inp.value = 'echo hello-from-zsh && uname -s'; inp.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true})); await sleep(1500); out.push('term=' + [...t.querySelectorAll('.term > div')].map(d => d.textContent).join('|').slice(-80));
    const w = D.WM.open('web'); out.push('webview=' + !!w.querySelector('webview')); w.querySelector('#wurl').value = 'https://example.com'; w.querySelector('#wurl').dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true})); await sleep(3000); out.push('web url=' + w.querySelector('#wurl').value + ' title=' + w.querySelector('.tname').textContent);
    const m = D.WM.open('monitor'); await sleep(2500); out.push('monitor cpu=' + m.querySelector('#mCpu').textContent + ' mem=' + m.querySelector('#mMem').textContent + ' procs=' + m.querySelectorAll('#mProc tr').length);
    const x = D.WM.open('transfer'); await sleep(2500); out.push('transfer=' + x.querySelector('.a-head b').textContent);
    const p = D.WM.open('photos'); await sleep(500); out.push('photos=' + (p.querySelector('.iv img')?.src || 'none').slice(0, 60));
  } catch (e) { out.push('ERR ' + e.message + ' ' + e.stack.split('\\n')[1]); } return out; })()`);
  console.log(r.join('\n')); app.quit();
}, 1500));
