const offset = 0.1;

function clamp(num, min, max) {
    return num <= min ? min : num >= max ? max : num;
}

function easeOutSine(y) {
    const x = y / 3;
    return Math.sin((x * Math.PI) / 2);
}
  
function easeOutCubic(y) {
    const x = y / 3;
    return 1 - Math.pow(1 - x, 3);
}

function easeOutQuad(y) {
    const x = y / 3;
    return 1 - (1 - x) * (1 - x);
}

function easeOutQuart(y) {
    const x = y / 3;
    return 1 - Math.pow(1 - x, 4);
}


function getEaseOutSineFrames(framesFor, fps) {
    const framesAmt = [];
    for (let i = offset; i < 1; i+=((1 / framesFor) - offset))
        framesAmt.push(clamp(Math.round(easeOutSine(i) * fps), 1, fps * 10000));

    return framesAmt;
}

function getEaseInSineFrames(framesFor, fps) {
    const tempFramesAmt = getEaseOutSineFrames(framesFor, fps);
    const framesAmt = [];
    for (let i = tempFramesAmt.length - 1; i >= 0; i--)
        framesAmt.push(clamp(Math.round(tempFramesAmt[i] / 2), 1, fps * 10000));

    return framesAmt;
}

function getEaseOutCubicFrames(framesFor, fps) {
    const framesAmt = [];
    for (let i = offset; i < 1; i+=((1 / framesFor) - offset))
        framesAmt.push(clamp(Math.round(easeOutCubic(i) * fps), 1, fps * 10000));

    return framesAmt;
}

function getEaseInCubicFrames(framesFor, fps) {
    const tempFramesAmt = getEaseOutCubicFrames(framesFor, fps);
    const framesAmt = [];
    for (let i = tempFramesAmt.length - 1; i >= 0; i--)
        framesAmt.push(clamp(Math.round(tempFramesAmt[i] / 2), 1, fps * 10000));

    return framesAmt;
}

function getEaseInOutCubicFrames(framesFor, fps) {
    const tempFramesAmt = [];
    const framesAmt = [];
    for (let i = offset; i < 1; i+=((1 / Math.floor(framesFor / 2)) - offset))
        tempFramesAmt.push(clamp(Math.round(easeInOutCubic(i) * fps), 1, fps * 10000));

    for (let i = tempFramesAmt.length - 1; i >= 0; i--) {
        framesAmt.push(tempFramesAmt[i]);
    }

    for (const x of tempFramesAmt) {
        framesAmt.push(x);
    }

    return framesAmt;
}

function doEaseOutCubic(frames) {
    const fps = document.getElementById('fpsInput').value;
    const framesToEase = [];

    for (let i = 0; i < frames.length; i++)
        if (frames[i].selected) framesToEase.push(i);

    const easeFrames = getEaseOutCubicFrames(framesToEase.length, fps);

    let index = 0;
    for (const framesFor of easeFrames) {
        frames[framesToEase[index]].framesFor = framesFor;

        const framesForLbl = document.getElementById(frames[framesToEase[index]].framesForLblId);
        framesForLbl.innerText = `${frames[framesToEase[index]].framesFor}`;
        framesForLbl.style.display = frames[framesToEase[index]].framesFor == 1 ? "none" : "block";

        index ++;
    }

    updateFramesRow();
}

function doEaseInCubic(frames) {
    const fps = document.getElementById('fpsInput').value;
    const framesToEase = [];

    for (let i = 0; i < frames.length; i++)
        if (frames[i].selected) framesToEase.push(i);

    const easeFrames = getEaseInCubicFrames(framesToEase.length, fps);

    let index = 0;
    for (const framesFor of easeFrames) {
        frames[framesToEase[index]].framesFor = framesFor;

        const framesForLbl = document.getElementById(frames[framesToEase[index]].framesForLblId);
        framesForLbl.innerText = `${frames[framesToEase[index]].framesFor}`;
        framesForLbl.style.display = frames[framesToEase[index]].framesFor == 1 ? "none" : "block";

        index ++;
    }

    updateFramesRow();
}

function doEaseOutSine(frames) {
    const fps = document.getElementById('fpsInput').value;
    const framesToEase = [];

    for (let i = 0; i < frames.length; i++)
        if (frames[i].selected) framesToEase.push(i);

    const easeFrames = getEaseOutSineFrames(framesToEase.length, fps);

    let index = 0;
    for (const framesFor of easeFrames) {
        frames[framesToEase[index]].framesFor = framesFor;

        const framesForLbl = document.getElementById(frames[framesToEase[index]].framesForLblId);
        framesForLbl.innerText = `${frames[framesToEase[index]].framesFor}`;
        framesForLbl.style.display = frames[framesToEase[index]].framesFor == 1 ? "none" : "block";

        index ++;
    }

    updateFramesRow();
}

function doEaseInSine(frames) {
    const fps = document.getElementById('fpsInput').value;
    const framesToEase = [];

    for (let i = 0; i < frames.length; i++)
        if (frames[i].selected) framesToEase.push(i);

    const easeFrames = getEaseInSineFrames(framesToEase.length, fps);

    let index = 0;
    for (const framesFor of easeFrames) {
        frames[framesToEase[index]].framesFor = framesFor;

        const framesForLbl = document.getElementById(frames[framesToEase[index]].framesForLblId);
        framesForLbl.innerText = `${frames[framesToEase[index]].framesFor}`;
        framesForLbl.style.display = frames[framesToEase[index]].framesFor == 1 ? "none" : "block";

        index ++;
    }

    updateFramesRow();
}

async function showCrossfadeDialog(frames) {
    const box = document.createElement('div');
    box.style.position = 'fixed';
    box.style.top = '60px';
    box.style.right = '10px';
    box.style.width = '300px';
    box.style.height = '300px';
    box.style.zIndex = '300';
    box.style.backdropFilter = 'blur(15px)';
    box.style.backgroundColor = 'rgba(255, 255, 255, 0.5)';
    box.style.borderRadius = '15px';
    document.body.appendChild(box);

    const titleBar = document.createElement('center');
    titleBar.innerHTML = '<h2 style="color: black;">Crossfade</h2>';
    box.appendChild(titleBar);

    const equationBar = document.createElement('div');
    equationBar.style.display = 'flex';
    equationBar.style.alignContent = 'center';
    equationBar.style.alignItems = 'center';
    equationBar.style.justifyContent = 'center';
    box.appendChild(equationBar);

    let chosenEquation = 0, secondsFor = 2;

    const previewBar = document.createElement('center');
    box.appendChild(previewBar);

    const crossfadePreview = document.createElement('div');
    crossfadePreview.style.width = '200px';
    crossfadePreview.style.height = '150px';
    crossfadePreview.style.borderRadius = '15px';
    crossfadePreview.style.backgroundColor = 'white';
    previewBar.appendChild(crossfadePreview);

    const crossfadePreviewBlack = document.createElement('div');
    crossfadePreviewBlack.style.width = '100%';
    crossfadePreviewBlack.style.height = '100%';
    crossfadePreviewBlack.style.borderRadius = '15px';
    crossfadePreviewBlack.style.backgroundColor = 'black';
    crossfadePreviewBlack.style.opacity = '50%';
    crossfadePreview.appendChild(crossfadePreviewBlack);

    let percentage = 100;
    const previewAnimation = setInterval(() => {
        switch (chosenEquation) {
            case 1:
                crossfadePreviewBlack.style.opacity = `${easeOutSine(percentage / 100) * 100}%`;
                break;
            case 2:
                crossfadePreviewBlack.style.opacity = `${easeOutQuad(percentage / 100) * 100}%`;
                break;
            case 2:
                crossfadePreviewBlack.style.opacity = `${easeOutQuart(percentage / 100) * 100}%`;
                break;
            default:
                crossfadePreviewBlack.style.opacity = `${easeOutCubic(percentage / 100) * 100}%`;
                break;
        }

        console.log(chosenEquation);

        percentage -= 1;
        if (percentage == -1) percentage = 100;
    }, parseInt(`${document.getElementById('fpsInput').value}`));

    const cubicBtn = document.createElement('button');
    const sineBtn = document.createElement('button');
    const quadBtn = document.createElement('button');
    const quartBtn = document.createElement('button');
    const expoBtn = document.createElement('button');
    equationBar.appendChild(cubicBtn);
    equationBar.appendChild(sineBtn);
    equationBar.appendChild(quadBtn);
    equationBar.appendChild(quartBtn);
    equationBar.appendChild(expoBtn);
    cubicBtn.innerText = 'Cubic';
    cubicBtn.className = 'buttonOn';
    cubicBtn.onclick = function () {
        chosenEquation = 0;
        cubicBtn.className = 'buttonOn';
        sineBtn.className = 'buttonOff';
        quadBtn.className = 'buttonOff';
        quartBtn.className = 'buttonOff';
        expoBtn.className = 'buttonOff';
    }
    sineBtn.innerText = 'Sine';
    sineBtn.className = 'buttonOff';
    sineBtn.onclick = function () {
        chosenEquation = 1;
        cubicBtn.className = 'buttonOff';
        sineBtn.className = 'buttonOn';
        quadBtn.className = 'buttonOff';
        quartBtn.className = 'buttonOff';
        expoBtn.className = 'buttonOff';
    }
    quadBtn.innerText = 'Quad';
    quadBtn.className = 'buttonOff';
    quadBtn.onclick = function () {
        chosenEquation = 2;
        cubicBtn.className = 'buttonOff';
        sineBtn.className = 'buttonOff';
        quadBtn.className = 'buttonOn';
        quartBtn.className = 'buttonOff';
        expoBtn.className = 'buttonOff';
    }
    quartBtn.innerText = 'Quart';
    quartBtn.className = 'buttonOff';
    quartBtn.onclick = function () {
        chosenEquation = 3;
        cubicBtn.className = 'buttonOff';
        sineBtn.className = 'buttonOff';
        quadBtn.className = 'buttonOff';
        quartBtn.className = 'buttonOn';
        expoBtn.className = 'buttonOff';
    }
    expoBtn.innerText = 'Expo';
    expoBtn.className = 'buttonOff';
    expoBtn.onclick = function () {
        chosenEquation = 4;
        cubicBtn.className = 'buttonOff';
        sineBtn.className = 'buttonOff';
        quadBtn.className = 'buttonOff';
        quartBtn.className = 'buttonOff';
        expoBtn.className = 'buttonOn';
    }
}
