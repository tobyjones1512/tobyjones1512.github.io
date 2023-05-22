const { app, BrowserWindow } = require("electron");
const fs = require("fs");

app.setName("Stop Motion Tool");

const createWindow = () => {
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 1280,
    minHeight: 720,
    title: "Stop Motion Tool",
    titleBarStyle: "hidden",
    trafficLightPosition: { x: 17.5, y: 17.5 },
    nodeIntegration: true,
    frame: false
  });

  win.loadFile("index.html");

  win.setFullScreen(true);
};

app.whenReady().then(() => {
  createWindow();
});

function uuidv4() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    var r = (Math.random() * 16) | 0,
      v = c == "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}