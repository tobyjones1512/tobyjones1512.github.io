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
    frame: false,
  });

  win.loadFile("index.html");

  win.setFullScreen(true);
};

app.whenReady().then(() => {
  createWindow();
});

var totalFrames = 0;
var frames = [];
var isTrailingOnionSkins = false;
var mirrorPreview = true;
var loopPreview = false;
var canDeleteStage = false;

function clamp(num, min, max) {
  return num <= min ? min : num >= max ? max : num;
}

function start() {
  totalFrames = 0;
  frames = [];
  isTrailingOnionSkins = false;
  mirrorPreview = true;
  loopPreview = false;
  canDeleteStage = false;

  getCameras();

  window.onscroll = function () {
    const previewArea = document.getElementById("previewSection");
    const blurBar = document.getElementById("previewBlurBar");
    const frameToolsBar = document.getElementById("frameToolsBar");

    const amountScrolled = window.scrollY;
    //const percentageChangeInHeight = parseFloat(`0.${amountScrolled}`) / 2;
    //const percentage = clamp(1 - percentageChangeInHeight, 0, 0.5);

    //previewArea.style.height = `${720 * percentage}px`;
    //console.log(percentageChangeInHeight);

    previewArea.style.height = amountScrolled == 0 ? "720px" : `${720 / 2}px`;
    previewArea.style.width = amountScrolled == 0 ? "1280px" : `${1280 / 2}px`;

    const topSkin = document.getElementById("onionSkinImg1");
    topSkin.style.height = amountScrolled == 0 ? "720px" : `${720 / 2}px`;
    topSkin.style.width = amountScrolled == 0 ? "1280px" : `${1280 / 2}px`;

    const middleSkin = document.getElementById("onionSkinImg2");
    middleSkin.style.height = amountScrolled == 0 ? "720px" : `${720 / 2}px`;
    middleSkin.style.width = amountScrolled == 0 ? "1280px" : `${1280 / 2}px`;

    const bottomSkin = document.getElementById("onionSkinImg3");
    bottomSkin.style.height = amountScrolled == 0 ? "720px" : `${720 / 2}px`;
    bottomSkin.style.width = amountScrolled == 0 ? "1280px" : `${1280 / 2}px`;

    blurBar.style.height = amountScrolled == 0 ? "720px" : `${720 / 2 + 50}px`;
    frameToolsBar.style.top =
      amountScrolled == 0 ? "725px" : `${720 / 2 + 5}px`;
  };
}

function loadFeed(_deviceId) {
  const video = document.querySelector("#myVidPlayer");

  navigator.mediaDevices
    .getUserMedia({ video: { deviceId: { exact: _deviceId } } })
    .then(function (device) {
      video.srcObject = device;
      video.onloadedmetadata = (e) => {
        video.play();
      };
    })
    .catch(function (err) {
      console.log("An error occurred: " + err);
    });

  document.getElementById("showFeedBtn").style.display = "none";
  document.getElementById("previewToolBar").style.display = "flex";
  document.getElementById("optionsRow").style.display = "flex";
}

function captureFrame(source = "none", visible = true, framesFor = 1) {
  const w = 213.5;
  const h = 120;

  const canvas = document.createElement("canvas");
  const image = document.createElement("img");
  const frameBox = document.createElement("div");
  const buttonsRow = document.createElement("center");
  const video = document.querySelector("#myVidPlayer");
  const context = canvas.getContext("2d");
  const framesRow = document.getElementById("framesBox");
  const flashBox = document.getElementById("captureFlash");
  const captureFrameBtn = document.getElementById("captureFrameBtn");

  //context.fillRect(0, 0, w, h);
  if (source == "none") {
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    context.drawImage(video, 0, 0, video.videoWidth, video.videoHeight);
  }

  //frameBox.className = 'animationFramePreview';
  frameBox.style.position = "relative";
  frameBox.style.display = "inline-block";
  frameBox.style.margin = "5px";
  frameBox.style.padding = "0px";
  frameBox.style.width = `${w}px`;
  frameBox.style.height = `${h}px`;

  if (source == "none") image.src = canvas.toDataURL();
  else image.src = source;
  image.style.position = "absolute";
  image.style.top = "0px";
  image.style.left = "0px";
  image.style.width = "100%";
  image.style.height = "100%";
  image.style.borderRadius = "7.5px";
  image.style.padding = "0px";
  image.style.zIndex = "3";
  image.style.objectFit = "cover";
  image.id = uuidv4();

  let didFlash = false;
  let interval = 0;
  let flash = setInterval(() => {
    if (didFlash) {
      flashBox.style.opacity = "0%";
      captureFrameBtn.disabled = false;
      captureFrameBtn.style.opacity = "100%";
      clearInterval(flash);
    } else {
      flashBox.style.opacity = "100%";
      didFlash = true;
      interval = 2000;
      captureFrameBtn.style.opacity = "50%";
      captureFrameBtn.disabled = true;
    }
  }, interval);

  buttonsRow.style.display = "none";
  buttonsRow.style.justifyContent = "center";
  buttonsRow.style.justifyItems = "center";
  buttonsRow.style.alignContent = "center";
  buttonsRow.style.position = "absolute";
  buttonsRow.style.bottom = "0px";
  buttonsRow.style.left = "0px";
  buttonsRow.style.width = "100%";
  buttonsRow.style.borderRadius = "7.5px";
  buttonsRow.style.padding = "0px";
  buttonsRow.style.zIndex = "200";

  const moveLeftBtn = document.createElement("button");
  moveLeftBtn.innerText = "<";
  moveLeftBtn.style.height = "25px";
  moveLeftBtn.style.borderRadius = "12.5px";
  buttonsRow.appendChild(moveLeftBtn);

  const optionsDiv = document.createElement("div");
  optionsDiv.className = "dropdown";
  buttonsRow.appendChild(optionsDiv);

  const optionsBtn = document.createElement("button");
  optionsBtn.innerText = "Options";
  optionsBtn.style.height = "25px";
  optionsBtn.style.borderRadius = "12.5px";
  optionsDiv.appendChild(optionsBtn);

  const optionsMenu = document.createElement("div");
  optionsMenu.className = "dropdown-content";
  optionsDiv.appendChild(optionsMenu);

  const moveRightBtn = document.createElement("button");
  moveRightBtn.innerText = ">";
  moveRightBtn.style.height = "25px";
  moveRightBtn.style.borderRadius = "12.5px";
  buttonsRow.appendChild(moveRightBtn);

  const hideBtn = document.createElement("button");
  hideBtn.innerText = visible ? "Hide" : "Unhide";
  hideBtn.style.height = "25px";
  hideBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(hideBtn);

  const deleteBtn = document.createElement("button");
  deleteBtn.innerText = "Delete";
  deleteBtn.style.height = "25px";
  deleteBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(deleteBtn);

  const duplicateBtn = document.createElement("button");
  duplicateBtn.innerText = "Extend";
  duplicateBtn.style.height = "25px";
  duplicateBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(duplicateBtn);

  const reduceBtn = document.createElement("button");
  reduceBtn.innerText = "Reduce";
  reduceBtn.style.height = "25px";
  reduceBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(reduceBtn);

  frameBox.appendChild(image);
  frameBox.appendChild(buttonsRow);
  framesRow.appendChild(frameBox);

  const framesForLbl = document.createElement("h1");
  framesForLbl.innerText = `${framesFor}`;
  framesForLbl.style.backgroundColor = "rgba(255, 255, 255, 0.75)";
  framesForLbl.style.color = "black";
  framesForLbl.style.backgroundFilter = "blur(5px)";
  framesForLbl.style.borderRadius = "5px";
  framesForLbl.style.paddingLeft = "5px";
  framesForLbl.style.paddingRight = "5px";
  framesForLbl.style.position = "absolute";
  framesForLbl.style.left = "-8px";
  framesForLbl.style.top = "-20%";
  framesForLbl.style.zIndex = "20";
  framesForLbl.style.cursor = "default";
  framesForLbl.style.display = framesFor == 1 ? "none" : "block";
  frameBox.appendChild(framesForLbl);

  if (!visible) frameBox.style.opacity = "50%";

  document.getElementById(
    "framesTitle"
  ).innerText = `Frames (${framesRow.childElementCount}):`;
  document.getElementById("framesSection").style.display = "block";

  frameBox.onmouseenter = function () {
    image.style.filter = "blur(1px)";

    let index = 0;
    for (const _ of frames) {
      if (_.frame == image.src) break;

      index += 1;
    }
    moveLeftBtn.style.display = index == 0 ? "none" : "block";
    moveRightBtn.style.display = index == frames.length - 1 ? "none" : "block";
    reduceBtn.style.display = frames[index].framesFor > 1 ? "block" : "none";

    buttonsRow.style.display = "flex";

    previewFrame(image.src);
  };

  frameBox.onmouseleave = function () {
    image.style.filter = "blur(0px)";
    buttonsRow.style.display = "none";

    endFramePreview();
  };

  moveLeftBtn.onclick = function () {
    let index = 0;
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame != image.src) continue;

      index = i;
    }

    const tempFrame = frames[index];
    frames[index] = frames[index - 1];
    frames[index - 1] = tempFrame;

    framesRow.innerHTML = "";

    for (const frame of frames) framesRow.appendChild(frame.box);

    updateOnionSkinning();
  };

  moveRightBtn.onclick = function () {
    let index = 0;
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame != image.src) continue;

      index = i;
    }

    const tempFrame = frames[index];
    frames[index] = frames[index + 1];
    frames[index + 1] = tempFrame;

    framesRow.innerHTML = "";

    for (const frame of frames) framesRow.appendChild(frame.box);

    updateOnionSkinning();
  };

  hideBtn.onclick = function () {
    let index = 0;
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame != image.src) continue;

      index = i;
    }

    frames[index].visible = !frames[index].visible;

    document.getElementById(frames[index].id).style.opacity = frames[index]
      .visible
      ? "100%"
      : "25%";
    hideBtn.innerText = frames[index].visible ? "Hide" : "Unhide";

    framesRow.innerHTML = "";

    for (const frame of frames) framesRow.appendChild(frame.box);
  };

  deleteBtn.onclick = function () {
    let index = 0;
    const newFramesArr = [];
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame == image.src) continue;

      newFramesArr.push(frames[i]);
    }

    frames = newFramesArr;
    totalFrames = frames.length;

    framesRow.innerHTML = "";

    for (const frame of frames) framesRow.appendChild(frame.box);

    document.getElementById(
      "framesTitle"
    ).innerText = `Frames (${framesRow.childElementCount}):`;
    document.getElementById("framesSection").style.display =
      framesRow.childElementCount > 0 ? "block" : "none";
  };

  duplicateBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.frame == image.src) break;

      index += 1;
    }

    frames[index].framesFor += 1;

    framesForLbl.innerText = `${frames[index].framesFor}`;
    framesForLbl.style.display = "block";
  };

  reduceBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.frame == image.src) break;

      index += 1;
    }

    if (frames[index].framesFor > 1) frames[index].framesFor -= 1;

    framesForLbl.innerText = `${frames[index].framesFor}`;
    framesForLbl.style.display = frames[index].framesFor > 1 ? "block" : "none";
  };

  frames.push({
    frame: image.src,
    box: frameBox,
    visible: visible,
    framesFor: framesFor,
    id: image.id,
  });

  updateOnionSkinning();
}

function toggleOnionSkinning() {
  const btn = document.getElementById("onionBtn");
  const trailsBtn = document.getElementById("trailsBtn");
  const onionSkinsDiv = document.getElementById("onionSkins");
  const turnOn = btn.className == "buttonOff";

  btn.className = turnOn ? "buttonOn" : "buttonOff";

  if (turnOn) {
    onionSkinsDiv.style.display = "block";

    updateOnionSkinning();
  } else {
    onionSkinsDiv.style.display = "none";
    trailsBtn.className = "buttonOff";
    isTrailingOnionSkins = false;
  }
}

function updateOnionSkinning() {
  const topSkin = document.getElementById("onionSkinImg1");
  const middleSkin = document.getElementById("onionSkinImg2");
  const bottomSkin = document.getElementById("onionSkinImg3");

  middleSkin.style.display = "none";
  bottomSkin.style.display = "none";

  if (frames.length == 0) return;

  try {
    topSkin.src = frames[frames.length - 1].frame;

    if (isTrailingOnionSkins) {
      try {
        middleSkin.src = frames[frames.length - 2].frame;
        middleSkin.style.display = "block";

        try {
          bottomSkin.src = frames[frames.length - 3].frame;
          bottomSkin.style.display = "block";
        } catch (err2) {}
      } catch (err1) {}
    }
  } catch (err) {}
}

function toggleTrailOnionSkins() {
  const btn = document.getElementById("trailsBtn");
  const onionBtn = document.getElementById("onionBtn");

  isTrailingOnionSkins = !isTrailingOnionSkins;
  btn.className = isTrailingOnionSkins ? "buttonOn" : "buttonOff";
  if (onionBtn.className == "buttonOff") toggleOnionSkinning();
  else updateOnionSkinning();
}

function getCameras() {
  navigator.mediaDevices
    .enumerateDevices()
    .then(function (devices) {
      devices.forEach(function (device) {
        if (device.kind.includes("video")) {
          const cameraBtn = document.createElement("button");
          cameraBtn.innerText = device.label;
          cameraBtn.onclick = function () {
            loadFeed(device.deviceId);
          };

          document
            .getElementById("showFeedDropdownContent")
            .appendChild(cameraBtn);
        }
      });
    })
    .catch(function (err) {
      console.log(err.name + ": " + err.message);
    });
}

async function previewAnimation() {
  const canvas = document.getElementById("previewCanvas");
  //const ctx = canvas.getContext("2d");

  const fps = document.getElementById("fpsInput").value;
  let currentFrame = 0;
  let framesFor = 0;

  let showFrame = setInterval(() => {
    try {
      while (true) {
        if (frames[currentFrame].visible) break;
        currentFrame += 1;
      }

      if (framesFor == 0) framesFor = frames[currentFrame].framesFor;

      canvas.src = frames[currentFrame].frame;
      canvas.style.display = "block";

      framesFor -= 1;
      if (framesFor == 0) currentFrame += 1;
    } catch (err) {
      if (loopPreview) {
        currentFrame = 0;
      } else {
        canvas.style.display = "none";
        clearInterval(showFrame);
      }
    }
  }, 1000 / fps);
}

function exportFrames() {
  var imageBlobs = [];
  for (const frame of frames) {
    if (!frame.visible) continue;

    for (let i = 0; i < frame.framesFor; i++) {
      imageBlobs.push(frame.frame);
    }
  }

  const name = document.getElementById("filmTitle").innerText;
  //const fps = parseInt(`${document.getElementById('fpsInput').value}`);

  const zip = new JSZip();
  let i = 1;
  for (const blob of imageBlobs) {
    console.log(i);
    zip.file(`${name} - frame ${i}.png`, b64toBlob(blob, "image/png"));
    i++;
  }
  zip.generateAsync({ type: "blob" }).then((content) => {
    saveAs(content, `${name} frames.zip`);
  });
}

const b64toBlob = (base64, type = "application/octet-stream") =>
  fetch(base64).then((res) => res.blob());

async function exportToWebM() {
  const video = document.querySelector("#myVidPlayer");
  const name = document.getElementById("filmTitle").innerText;
  const images = [];
  const fps = parseInt(`${document.getElementById("fpsInput").value}`);

  const canvas = document.createElement("canvas");
  const previewCanvas = document.getElementById("previewCanvas");
  const stream = canvas.captureStream();
  const recorder = new MediaRecorder(stream, {
    mimeType: "video/webm",
  });
  const chunks = [];

  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;

  recorder.ondataavailable = (event) => {
    chunks.push(event.data);
  };

  for (const frame of frames) {
    if (!frame.visible) continue;
    images.push({
      src: frame.frame,
      framesFor: frame.framesFor,
    });
  }

  previewCanvas.style.display = "block";

  recorder.start();

  const context = canvas.getContext("2d");
  let framesFor = 1;
  for (let i = 0; i < frames.length; i++) {
    framesFor = frames[i].framesFor;

    canvas.width = frames[i].frame.width;
    canvas.height = frames[i].frame.height;

    const image = new Image();
    image.style.objectFit = "cover";
    image.src = frames[i].frame;
    previewCanvas.src = frames[i].frame;

    context.drawImage(image, 0, 0, video.videoWidth, video.videoHeight);

    canvas.toBlob(
      (blob) => {
        recorder.ondataavailable({ data: blob });
      },
      "image/webp",
      1
    );

    await new Promise((r) => setTimeout(r, framesFor * (1000 / fps)));
  }

  recorder.stop();

  const blob = new Blob(chunks, { type: "video/webm" });

  const url = URL.createObjectURL(blob);

  const a = document.createElement("a");

  a.download = `${name}.webm`;

  a.href = url;

  document.body.appendChild(a);

  a.click();

  document.body.removeChild(a);
}

function togglePreviewMirror() {
  const btn = document.getElementById("mirrorBtn");
  const turnOn = btn.className == "buttonOff";

  btn.className = turnOn ? "buttonOn" : "buttonOff";

  mirrorPreview = turnOn;

  const preview = document.getElementById("myVidPlayer");
  preview.style.transform = `scaleX(${mirrorPreview ? -1 : 1})`;

  const topSkin = document.getElementById("onionSkinImg1");
  topSkin.style.transform = `scaleX(${mirrorPreview ? -1 : 1})`;

  const middleSkin = document.getElementById("onionSkinImg2");
  middleSkin.style.transform = `scaleX(${mirrorPreview ? -1 : 1})`;

  const bottomSkin = document.getElementById("onionSkinImg3");
  bottomSkin.style.transform = `scaleX(${mirrorPreview ? -1 : 1})`;
}

function previewFrame(src) {
  const canvas = document.getElementById("previewCanvas");
  canvas.src = src;
  canvas.style.display = "block";
}

function endFramePreview() {
  const canvas = document.getElementById("previewCanvas");
  canvas.style.display = "none";
}

function toggleLoopPreview() {
  const btn = document.getElementById("loopBtn");
  const turnOn = btn.className == "buttonOff";

  btn.className = turnOn ? "buttonOn" : "buttonOff";

  loopPreview = turnOn;
}

async function downloadProject() {
  var dataStr =
    "data:text/json;charset=utf-8," +
    encodeURIComponent(
      JSON.stringify({
        title: document.getElementById("filmTitle").innerText,
        fps: document.getElementById("fpsInput").value,
        frames: frames,
      })
    );
  var downloadAnchorNode = document.createElement("a");
  downloadAnchorNode.setAttribute("href", dataStr);
  downloadAnchorNode.setAttribute(
    "download",
    document.getElementById("filmTitle").innerText + ".stopmotion"
  );
  document.body.appendChild(downloadAnchorNode); // required for firefox
  downloadAnchorNode.click();
  downloadAnchorNode.remove();
}

function importProject() {
  var input = document.createElement("input");
  input.type = "file";
  input.addEventListener("change", function () {
    var file = this.files[0];
    var reader = new FileReader();
    reader.onload = function (event) {
      var contents = event.target.result;
      var json = JSON.parse(contents);

      document.getElementById("filmTitle").innerText = json.title;
      document.getElementById("fpsInput").value = json.fps;

      for (const frame of json.frames) {
        captureFrame(frame.frame, frame.visible, frame.framesFor);
      }
    };
    reader.readAsText(file);
  });
  input.click();
}

function clearStage() {
  if (canDeleteStage) {
    canDeleteStage = false;
    document.getElementById("clearBtn").innerText = "Clear Stage";

    frames = [];
    totalFrames = 0;

    document.getElementById("framesTitle").innerText = `Frames:`;
    document.getElementById("framesSection").style.display = "none";
    document.getElementById("framesBox").innerHTML = "";

    alert("Stage cleared");

    updateOnionSkinning();
  } else {
    canDeleteStage = true;
    document.getElementById("clearBtn").innerText =
      "Click again to clear the stage";
  }
}

function uuidv4() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    var r = (Math.random() * 16) | 0,
      v = c == "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
