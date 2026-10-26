"use strict";
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("notch", {
  getState: () => ipcRenderer.invoke("get-state"),
  pane: (p) => ipcRenderer.invoke("pane", p),
  refresh: () => ipcRenderer.invoke("refresh"),
  preferences: (p) => ipcRenderer.invoke("preferences", p),
  pin: (key) => ipcRenderer.invoke("pin", key),
  reorder: (a, b) => ipcRenderer.invoke("reorder", a, b),
  open: (key) => ipcRenderer.invoke("open", key),
  colorPicker: (value) => ipcRenderer.invoke("color-picker", value),
  onClose: (callback) => ipcRenderer.on("close-pane", callback),
  quit: () => ipcRenderer.invoke("quit"),
  subscribe: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on("state", listener);
    return () => ipcRenderer.removeListener("state", listener);
  },
});
