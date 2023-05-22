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
var mirrorPreview = false;
var loopPreview = false;
var canDeleteStage = false;
var b64toBlob = null;
var useInOut = false;
var inIndex = 0;
var outIndex = 0;
var isPlaying = false;
var isSelecting = false;
var hasSelections = false;

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
  inIndex = 0;
  outIndex = 0;
  isPlaying = false;
  isSelecting = false;
  hasSelections = false;
  b64toBlob = (base64, type = "application/octet-stream") =>
  fetch(base64).then((res) => res.blob());

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

function loadFeed(_deviceId = 'NO FEED') {
  const video = document.querySelector("#myVidPlayer");
  video.srcObject = null;

  if (_deviceId != 'NO FEED') {
  navigator.mediaDevices
    .getUserMedia({ video: { deviceId: { exact: _deviceId } } })
    .then(function (device) {
      video.srcObject = device;
      video.onloadedmetadata = (e) => {
        video.play();
      };
      document.getElementById("captureFrameBtn").style.display = "block";
    })
    .catch(function (err) {
      console.log("An error occurred: " + err);
    });
  } else { 
    document.getElementById("captureFrameBtn").style.display = "none";
  }

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
  frameBox.style.borderRadius = "7.5px";
  frameBox.addEventListener('click', (event) => {
    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

      index += 1;
    }

    if (event.shiftKey) selectFrame(index, false); else selectFrame(index);
  });

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
  image.style.borderWidth = "3px";
  image.style.borderColor = "darkgrey";
  image.style.borderType = "none";
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

  const exportFrameBtn = document.createElement("button");
  exportFrameBtn.innerText = "Export";
  exportFrameBtn.style.height = "25px";
  exportFrameBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(exportFrameBtn);

  const replaceFrameBtn = document.createElement("button");
  replaceFrameBtn.innerText = "Replace";
  replaceFrameBtn.style.height = "25px";
  replaceFrameBtn.style.borderRadius = "12.5px";
  optionsMenu.appendChild(replaceFrameBtn);

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

  frameBox.onmouseenter = function () {
    image.style.filter = "blur(1px)";

    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

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

    updateFramesRow();

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

    updateFramesRow();

    updateOnionSkinning();
  };

  hideBtn.onclick = function () {
    let index = 0;
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame != image.src) continue;

      index = i;
    }

    frames[index].visible = !frames[index].visible;

    frames[index].img.style.opacity = frames[index]
      .visible
      ? "100%"
      : "25%";
    hideBtn.innerText = frames[index].visible ? "Hide" : "Unhide";

    updateFramesRow();
  };

  deleteBtn.onclick = function () {
    const newFramesArr = [];
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].frame == image.src) continue;

      newFramesArr.push(frames[i]);
    }

    frames = newFramesArr;
    totalFrames = frames.length;

    updateFramesRow();
  };

  duplicateBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

      index += 1;
    }

    frames[index].framesFor += 1;

    framesForLbl.innerText = `${frames[index].framesFor}`;
    framesForLbl.style.display = "block";

    updateFramesRow();
  };

  reduceBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

      index += 1;
    }

    if (frames[index].framesFor > 1) frames[index].framesFor -= 1;

    framesForLbl.innerText = `${frames[index].framesFor}`;
    framesForLbl.style.display = frames[index].framesFor > 1 ? "block" : "none";

    updateFramesRow();
  };

  exportFrameBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

      index += 1;
    }

    downloadFrame(frames[index].frame, index);
  }

  replaceFrameBtn.onclick = function () {
    let index = 0;
    for (const _ of frames) {
      if (_.id == image.id) break;

      index += 1;
    }

    replaceFrame(index);
  }

  frames.push({
    frame: image.src,
    box: frameBox,
    visible: visible,
    framesFor: framesFor,
    img: image,
    id: image.id,
    selected: false
  });

  updateFramesRow();

  updateOnionSkinning();
}

function updateFramesRow() {
  const framesRow = document.getElementById("framesBox");

  if (useInOut && outIndex == 0)  {
    inIndex = 0;
    outIndex = frames.length;
  }

  framesRow.innerHTML = "";

  const beforeBtn = document.createElement('button');
  beforeBtn.className = 'middleBtn';
  //framesRow.appendChild(beforeBtn);

  for (let index = 0; index < frames.length; index++) {
    const frame = frames[index];

    frame.img.style.borderColor = frame.selected ? 'darkblue' : 'darkgrey';
    frame.img.style.borderStyle = frame.selected || ( useInOut && index >= inIndex && index < outIndex ) ? "solid" : "none";

    const section = document.createElement('div');
    section.style.display = 'flex';
    //section.className = 'dropdown';

    const dropdownContent = document.createElement('div');
    dropdownContent.className = 'dropdown-content';
    section.appendChild(dropdownContent);

    const middleBtn = document.createElement('button');
    middleBtn.className = 'middleBtn';
    if (useInOut && index == inIndex) middleBtn.style.backgroundColor = "yellow";
    else if (useInOut && index == outIndex) middleBtn.style.backgroundColor = "orange";

    const markInBtn = document.createElement('button');
    markInBtn.innerText = 'Mark In';
    markInBtn.onclick = function () {
      inIndex = index;

      if (!useInOut) toggleUseInOut();
      else updateFramesRow();
    };
    dropdownContent.appendChild(markInBtn);

    const markOutBtn = document.createElement('button');
    markOutBtn.innerText = 'Mark Out';
    markOutBtn.onclick = function () {
      outIndex = index;

      if (!useInOut) toggleUseInOut();
      else updateFramesRow();
    };
    dropdownContent.appendChild(markOutBtn);

    const playFromHereBtn = document.createElement('button');
    playFromHereBtn.innerText = 'Play From';
    playFromHereBtn.onclick = function () {
      previewAnimation(true, index);
    };
    dropdownContent.appendChild(playFromHereBtn);

    const playToOutBtn = document.createElement('button');
    playToOutBtn.innerText = 'Play to Out';
    playToOutBtn.onclick = function () {
      previewAnimation(false, index);
    };
    dropdownContent.appendChild(playToOutBtn);

    const insertFramesBtn = document.createElement('button');
    insertFramesBtn.innerText = 'Insert Frames';
    insertFramesBtn.onclick = function () {
      insertFrames(index);
    };
    dropdownContent.appendChild(insertFramesBtn);

    middleBtn.onclick = function () {
      markInBtn.style.display = useInOut && index < frames.length - 1 && index < outIndex && index != inIndex ? 'block' : 'none';
      markOutBtn.style.display = useInOut && index > 0 && index > inIndex && index != outIndex ? 'block' : 'none';

      dropdownContent.style.display = dropdownContent.style.display == 'block' ? 'none' : 'block';
    }

    middleBtn.onmouseenter = function () {
      const video = document.getElementById("myVidPlayer");
      const onionSkinsDiv = document.getElementById("onionSkins");
      const onionSkinsDivMode = onionSkinsDiv.style.display;
      const topSkin = document.getElementById("onionSkinImg1");
      const topSkinMode = topSkin.style.display;
      const middleSkin = document.getElementById("onionSkinImg2");
      const middleSkinMode = middleSkin.style.display;

      middleBtn.id = `${onionSkinsDivMode}:${topSkinMode}:${middleSkinMode}`;

      topSkin.style.transform = 'scaleX(1)';
      middleSkin.style.transform = 'scaleX(1)';

      video.style.display = 'none';
      onionSkinsDiv.style.display = 'block';
      topSkin.style.display = 'block';
      middleSkin.style.display = 'block';

      topSkin.src = frame.frame;
      try {
        middleSkin.src = frames[index - 1].frame;
      } catch (err) {}
    }
    middleBtn.onmouseleave = function () {
      const video = document.getElementById("myVidPlayer");
      const onionSkinsDiv = document.getElementById("onionSkins");
      const onionSkinsDivMode = middleBtn.id.split(':')[0];
      const topSkin = document.getElementById("onionSkinImg1");
      const topSkinMode = middleBtn.id.split(':')[1];
      const middleSkin = document.getElementById("onionSkinImg2");
      const middleSkinMode = middleBtn.id.split(':')[2];

      topSkin.style.transform = mirrorPreview ? 'scaleX(-1)' : 'scaleX(1)';
      middleSkin.style.transform = mirrorPreview ? 'scaleX(-1)' : 'scaleX(1)';

      video.style.display = 'block';
      onionSkinsDiv.style.display = onionSkinsDivMode;
      topSkin.style.display = topSkinMode;
      middleSkin.style.display = middleSkinMode;

      topSkin.src = '';
      middleSkin.src = '';

      updateOnionSkinning();
    }
    section.appendChild(middleBtn);
    section.appendChild(frame.box);

    if (index == frames.length - 1) {
      const afterBtn = document.createElement('button');
      afterBtn.className = 'middleBtn';
      if (useInOut && index + 1 == inIndex) afterBtn.style.backgroundColor = "yellow";
      else if (useInOut && index + 1 == outIndex) afterBtn.style.backgroundColor = "orange";

      afterBtn.onclick = function() {
        outIndex = index + 1;

        if (!useInOut) toggleUseInOut();
        else updateFramesRow();
      }

      afterBtn.onmouseenter = function () {
        const video = document.getElementById("myVidPlayer");
        const onionSkinsDiv = document.getElementById("onionSkins");
        const onionSkinsDivMode = onionSkinsDiv.style.display;
        const topSkin = document.getElementById("onionSkinImg1");
        const topSkinMode = topSkin.style.display;
        const middleSkin = document.getElementById("onionSkinImg2");
        const middleSkinMode = middleSkin.style.display;
    
        afterBtn.id = `${onionSkinsDivMode}:${topSkinMode}:${middleSkinMode}:${video.srcObject}`;
        
        topSkin.style.transform = 'scaleX(1)';
        middleSkin.style.transform = 'scaleX(1)';
    
        video.style.display = 'none';
        onionSkinsDiv.style.display = 'block';
        topSkin.style.display = 'block';
        middleSkin.style.display = 'block';
    
        topSkin.src = frames[frames.length - 1].frame;
      }
      afterBtn.onmouseleave = function () {
        const video = document.getElementById("myVidPlayer");
        const onionSkinsDiv = document.getElementById("onionSkins");
        const onionSkinsDivMode = afterBtn.id.split(':')[0];
        const topSkin = document.getElementById("onionSkinImg1");
        const topSkinMode = afterBtn.id.split(':')[1];
        const middleSkin = document.getElementById("onionSkinImg2");
        const middleSkinMode = afterBtn.id.split(':')[2];
    
        topSkin.style.transform = mirrorPreview ? 'scaleX(-1)' : 'scaleX(1)';
        middleSkin.style.transform = mirrorPreview ? 'scaleX(-1)' : 'scaleX(1)';
    
        video.style.display = 'block';
        onionSkinsDiv.style.display = onionSkinsDivMode;
        topSkin.style.display = topSkinMode;
        middleSkin.style.display = middleSkinMode;
        topSkin.src = '';
        middleSkin.src = '';
    
        updateOnionSkinning();
      }
      section.appendChild(afterBtn);

    }

    framesRow.appendChild(section);
  }

  let seconds = 0;
  const part = 1 / parseInt(`${document.getElementById('fpsInput').value}`);
  let numFrames = 0;
  for (const fr of frames) {
    if (!fr.visible) continue;

    numFrames += 1 * fr.framesFor;

    seconds += part * fr.framesFor;
  }
  const date = new Date(seconds * 1000);
  const timeString = date.toISOString().substr(11, 8);

  document.getElementById(
    "framesTitle"
  ).innerText = `Frames (${numFrames}, ${timeString}):`;

  document.getElementById("framesSection").style.display =
      frames.length > 0 ? "block" : "none";
}

function toggleUseInOut() {
  useInOut = !useInOut;
  document.getElementById('useInOutToggle').className = useInOut ? 'buttonOn' : 'buttonOff';

  updateFramesRow();
}

function selectFrame(index, override = true) {
  const toBe = !frames[index].selected;

  if (override)
    for (const fr of frames)
      fr.selected = false;

  frames[index].selected = toBe;

  hasSelections = false;
  for (const fr of frames) {
    if (fr.selected) {
      hasSelections = true;
      break;
    }
  }

  updateFramesRow();
}

function selectInOut() {
  for (const fr of frames)
    fr.selected = false;

  hasSelections = false;

  for (let i = 0; i < frames.length; i++) {
    if (i < inIndex || i >= outIndex) continue;

    frames[i].selected = true;
    hasSelections = true;
  }

  updateFramesRow();
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

          const cameraBtn2 = document.createElement("button");
          cameraBtn2.innerText = device.label;
          cameraBtn2.onclick = function () {
            loadFeed(device.deviceId);
          };

          document
            .getElementById("showFeedDropdownContent")
            .appendChild(cameraBtn);

          document
            .getElementById("showFeedDropdownContent2")
            .appendChild(cameraBtn2);
        }
      });
    })
    .catch(function (err) {
      console.log(err.name + ": " + err.message);
    });

    const noFeedBtn = document.createElement("button");
    noFeedBtn.innerText = 'No Feed';
    noFeedBtn.onclick = function () {
      loadFeed();
    };

    const noFeedBtn2 = document.createElement("button");
    noFeedBtn2.innerText = 'No Feed';
    noFeedBtn2.onclick = function () {
      loadFeed();
    };

    document.getElementById("showFeedDropdownContent").appendChild(noFeedBtn);
    document.getElementById("showFeedDropdownContent2").appendChild(noFeedBtn2);
}

async function previewAnimation(ignoreUntil = false, currentFrame = -1) {
  isPlaying = true;

  const canvas = document.getElementById("previewCanvas");
  //const ctx = canvas.getContext("2d");

  const fps = document.getElementById("fpsInput").value;
  if (currentFrame == -1) currentFrame = useInOut ? inIndex : 0;
  let until = useInOut ? outIndex - 1 : frames.length;
  let framesFor = 0;

  let showFrame = setInterval(() => {
    try {
      for (const fr of frames)
        fr.img.style.filter = "sepia(0%)";
        
      while (true) {
        if (!hasSelections) {
          if (frames[currentFrame].visible) break;

          currentFrame += 1;
        } else {
          if (frames[currentFrame].selected && frames[currentFrame].visible) break;

          currentFrame += 1;
        }
      }

      if (!ignoreUntil && currentFrame > until) {
        for (const fr of frames)
          fr.img.style.filter = "sepia(0%)";

        if (loopPreview) {
          currentFrame = useInOut ? inIndex : 0;
        } else {
          canvas.style.display = "none";
          isPlaying = false;
          clearInterval(showFrame);
        }
      } else {
        if (framesFor == 0) framesFor = frames[currentFrame].framesFor;

        canvas.src = frames[currentFrame].frame;
        canvas.style.display = "block";
        frames[currentFrame].img.style.filter = "sepia(100%)";
        if (currentFrame > 0)
          frames[currentFrame - 1].img.style.filter = "sepia(0%)";

        framesFor -= 1;
        if (framesFor == 0) currentFrame += 1;
      }
    } catch (err) {
      for (const fr of frames)
        fr.img.style.filter = "sepia(0%)";

      if (loopPreview) {
        currentFrame = useInOut ? inIndex : 0;
      } else {
        canvas.style.display = "none";
        isPlaying = false;
        clearInterval(showFrame);
      }
    }
  }, 1000 / fps);
}

async function downloadFrame(src, num) {
  const zip = new JSZip();
  zip.file(`frame ${num + 1}.png`, b64toBlob(src, "image/png"));
  zip.generateAsync({ type: "blob" }).then((content) => {
    saveAs(content, `frame ${num + 1}.zip`);
  });
}

async function insertFrames(index) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/png';
  input.multiple = true;
  input.onchange = async function(event) {
    const oldFrames = frames;
    clearStage(true);

    let i = 0;
    for (const fr of oldFrames) {
      if (i == index) {
        const files = event.target.files;
        for (let j = 0; j < files.length; j++) {
          let finished = false;
          const reader = new FileReader();
          reader.readAsDataURL(files[j]);
          reader.onloadend = function() {
            captureFrame(reader.result);
            finished = true;
          };

          while (!finished) { await new Promise(resolve => setTimeout(resolve, 125)); }
        }
      }

      captureFrame(fr.frame, fr.visible, fr.framesFor);

      i += 1;
    }
  };
  input.click();  
}

function appendFrames() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/png';
  input.multiple = true;
  input.onchange = function(event) {
    for (const file of event.target.files) {
      const reader = new FileReader();
      reader.readAsDataURL(file);
      reader.onloadend = function() {
        captureFrame(reader.result);
      };
    }
  };
  input.click();  
}

function replaceFrame(index) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/png';
  input.onchange = function(event) {
    const file = event.target.files[0];
    const reader = new FileReader();
    reader.readAsDataURL(file);
    reader.onloadend = function() {
      const img = frames[index].img;
      img.src = reader.result;
      frames[index].frame = img.src;
    };
  };
  input.click();  
}

function exportFrames() {
  let startIndex = useInOut ? inIndex : 0;
  let until = useInOut ? outIndex - 1 : frames.length;
  var imageBlobs = [];
  let i = -1;
  for (const frame of frames) {
    i += 1;
    if (!frame.visible) {
      continue;
    }

    if (i >= startIndex && i <= until) {
      for (let _ = 0; _ < frame.framesFor; _++) {
        imageBlobs.push(frame.frame);
      }
    }
  }

  const name = document.getElementById("filmTitle").innerText;
  //const fps = parseInt(`${document.getElementById('fpsInput').value}`);

  const zip = new JSZip();
  i = 0;
  for (const blob of imageBlobs) {
    zip.file(`${name} - frame ${i}.png`, b64toBlob(blob, "image/png"));
    i++;
  }
  zip.generateAsync({ type: "blob" }).then((content) => {
    saveAs(content, `${name} frames.zip`);
  });
}

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

function clearStage(skipCheck = false) {
  if (canDeleteStage || skipCheck) {
    canDeleteStage = false;
    document.getElementById("clearBtn").innerText = "Clear Stage";

    frames = [];
    totalFrames = 0;

    document.getElementById("framesTitle").innerText = `Frames:`;
    document.getElementById("framesSection").style.display = "none";
    document.getElementById("framesBox").innerHTML = "";

    if(!skipCheck) alert("Stage cleared");

    updateOnionSkinning();

    updateFramesRow();
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
