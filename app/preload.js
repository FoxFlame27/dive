// Bridge between the Dive page and the host machine. Only these calls exist.
const { contextBridge, ipcRenderer } = require('electron');
const call = (name) => (...args) => ipcRenderer.invoke(name, ...args);
contextBridge.exposeInMainWorld('dive', {
  platform: process.platform,
  info: call('info'),
  listDir: call('listDir'),
  readText: call('readText'),
  writeText: call('writeText'),
  mkdir: call('mkdir'),
  rename: call('rename'),
  trash: call('trash'),
  exec: call('exec'),
  openPath: call('openPath'),
  openExternal: call('openExternal'),
  sysInfo: call('sysInfo'),
  processes: call('processes'),
  scanTransfer: call('scanTransfer'),
});
