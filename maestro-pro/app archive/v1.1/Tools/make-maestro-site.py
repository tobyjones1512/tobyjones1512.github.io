#!/usr/bin/env python3
"""Builds the Maestro Pro microsite (page, guide, support, privacy) in the website repo.

The guide's text is the app's own Help (Play Along/HelpView.swift), so the two stay the same: edit the Help, run this.
    python3 Tools/make-maestro-site.py [path to tobyjones1512.github.io]
"""
import html, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/On-Device Documents/GitHub/tobyjones1512.github.io")
OUT = os.path.join(SITE, "maestro-pro")
BASE = "https://thecaffeinemediacompany.com/maestro-pro/"
NAME = "Maestro Pro"
EMAIL = "hello@thecaffeinemediacompany.com"
STORE = '<a class="link" href="guide/index.html">Read the guide</a>'

# ---------------------------------------------------------------- the Help, read from the app

SHORTCUTS = {
    "Playback": "Play or Pause Space, Go to Beginning ↩, Previous Bar ←, Next Bar →, Previous Page Page Up, Next Page Page Down, Slower [, Faster ], Metronome K, Count In ⇧K.",
    "View": "Zoom In ⌘=, Zoom Out ⌘-, Fit to Width ⌘0, Follow Playback ⌥⌘F, Dark Sheet Music ⌥⌘D, Turn Pages Like a Book ⌥⌘P, Highlight Notes ⌥⌘1, Highlight Bar ⌥⌘2, Moving Line ⌥⌘3, Inspector ⌥⌘I, Chord View ⇧⌘C, Lyrics Instead of Music ⇧⌘L.",
    "Tools": "Edit Score ⌘E, Annotate ⇧⌘A, Wait for Me ⌥⌘W, Record Myself ⌘R, Tuner ⌘T.",
}

def strings(src, i):
    """The string literals from i until the closing ] that isn't in a string."""
    out = []
    while True:
        while src[i] in " \n\t,": i += 1
        if src[i] == "]": return out, i + 1
        assert src[i] == '"' or src.startswith("Self.shortcutLines", i), src[i:i + 40]
        if src[i] == '"':
            j = src.index('"', i + 1)
            out.append(src[i + 1:j]); i = j + 1
        else:
            out += [f"{g}: {t}" for g, t in SHORTCUTS.items()]; i += len("Self.shortcutLines")

def topics():
    src = open(os.path.join(ROOT, "Play Along/HelpView.swift")).read()
    src = src[src.index("private static let topics"):src.index("var body: some View")]
    result = []
    for block in src.split("Topic(id: ")[1:]:
        tid = re.match(r'"([^"]+)"', block).group(1)
        intro = re.search(r'intro: "(.*?)",\n', block, re.S).group(1)
        secs, i = [], block.index("sections: [") + len("sections: [")
        while True:
            m = re.compile(r'\s*\(\s*"([^"]+)",\s*\[').match(block, i)
            if not m: break
            body, i = strings(block, m.end())
            secs.append((m.group(1), body))
            i = block.index(")", i) + 1
        result.append({"title": tid, "intro": intro, "sections": secs})
    return result

GROUPS = [
    ("Start here", ["Getting Started", "Your Library", "Playing a Score"]),
    ("Practise", ["Tuner & Wait for Me", "Record & Review", "Scales & Arpeggios", "Annotating"]),
    ("Sound and words", ["Backing Tracks & Sound", "Lyrics & Karaoke"]),
    ("Write and keep", ["Writing & Editing Music", "Version History & GitHub", "Share, Export & Print"]),
    ("Together", ["Play Together"]),
    ("Settings and help", ["Keyboard Shortcuts", "Settings & Accessibility", "Troubleshooting"]),
]

CUR = ' aria-current="page"'

def slug(s): return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", s.lower())).strip("-")
def esc(s): return html.escape(s, quote=False)

# ---------------------------------------------------------------- shared shell

def head(title, desc, path, depth, og="assets/shots/playing.webp", read=False, extra=""):
    up = "../" * depth
    url = BASE + path
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{esc(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<meta name="theme-color" content="#15100B">
<link rel="icon" href="{up}assets/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="{up}assets/app-icon.png">
<link rel="canonical" href="{url}">
<meta property="og:site_name" content="Caffeine Media">
<meta property="og:locale" content="en_GB">
<meta property="og:type" content="website">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(desc)}">
<meta property="og:image" content="{BASE}{og}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{html.escape(title)}">
<meta name="twitter:description" content="{html.escape(desc)}">
<meta name="twitter:image" content="{BASE}{og}">
<link rel="preload" href="{up}assets/fonts/BodoniModa-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{up}assets/maestro.css">
<script>document.documentElement.classList.add('js')</script>
{extra}</head>
<body{' class="read"' if read else ''}>
<a class="skip" href="#main">Skip to content</a>
"""

def top(depth, current=""):
    up = "../" * depth
    links = [("Features", f"{up}index.html#features"), ("Plans", f"{up}index.html#plans"), ("Compatibility", f"{up}index.html#compatibility"), ("Guide", f"{up}guide/index.html"), ("For Education", f"{up}education.html"), ("Support", f"{up}support.html")]
    items = "".join(f'<a href="{h}"{CUR if n == current else ""}>{n}</a>' for n, h in links)
    return f"""<header class="top">
  <a class="top__brand" href="{up}index.html"><img width="160" height="160" src="{up}assets/app-icon-160.png" alt="">{NAME}</a>
  <nav class="top__links" aria-label="Primary">{items}</nav>
</header>
"""

def foot(depth):
    up = "../" * depth
    return f"""<footer class="foot">
  <nav aria-label="Footer"><a href="{up}index.html">{NAME}</a><a href="{up}guide/index.html">Guide</a><a href="{up}education.html">For Education</a><a href="{up}support.html">Support</a><a href="{up}privacy.html">Privacy</a><a href="https://thecaffeinemediacompany.com/">Caffeine Media</a></nav>
  <p>© <span id="yr">2026</span> {NAME}. Made by Toby Jones in England.</p>
</footer>
<script>document.getElementById('yr').textContent=new Date().getFullYear()</script>
<script src="/assets/cookie-consent.js" defer></script><script src="{up}assets/nav.js" defer></script>
</body>
</html>
"""

# ---------------------------------------------------------------- the product page

FEATURES = [
    ("Your library", "Import PDF, MusicXML, MIDI and karaoke files, or search the web for free scores. Set-lists for a rehearsal or a gig. Scanning paper music with the camera is coming in a future update.", "your-library"),
    ("Playing a score", "Notes light as they sound and the page turns itself. Change the tempo, the key, the instrument, and loop a hard bar.", "playing-a-score"),
    ("Backing tracks", "Play along with a backing track you add, or a song from Apple Music. Match its key and tempo, edit it, stack several.", "backing-tracks-sound"),
    ("Write and edit", "Draw notes in, change them, build a medley. Nine tools, and the editor keeps every bar tidy for you.", "writing-editing-music"),
    ("History and GitHub", "Save versions, branch, merge and roll back, then push the lot to your own GitHub repository.", "version-history-github"),
    ("Lyrics and karaoke", "Words scroll in time like Apple Music. Duets get a singer each, in their own colour.", "lyrics-karaoke"),
    ("Play Together", "Up to eight devices in perfect time, each from its own part, key and instrument.", "play-together"),
    ("Tuner and Wait for Me", "A tuner, a steady-note trainer, and a score that waits until you play the right note.", "tuner-wait-for-me"),
    ("Record and review", "Record yourself against the score, then see every wrong note, late entry and bar to work on.", "record-review"),
    ("Annotate", "Mark up the page with Apple Pencil, like a paper part. Your ink goes into exported PDFs.", "annotating"),
    ("Scales and arpeggios", "Practice material made on demand, in any key. Free on every plan.", "scales-arpeggios"),
    ("Share and print", "MusicXML, PDF, print, a video of the music following along, or a file for another player.", "share-export-print"),
]

def page():
    rows = "".join(f'<li style="--i:{i}"><a href="guide/{s}.html"><b>{esc(n)}</b><span>{esc(d)}</span><span class="go">Read more →</span></a></li>' for i, (n, d, s) in enumerate(FEATURES))
    ld = """<script type="application/ld+json">
{
 "@context": "https://schema.org",
 "@type": "SoftwareApplication",
 "name": "Maestro Pro",
 "applicationCategory": "MusicApplication",
 "operatingSystem": "iOS 17 or later, iPadOS 17 or later, macOS 14 or later",
 "description": "Maestro Pro is a sheet music reader and player for iPhone, iPad or Mac. Notes light up as they sound, the page turns itself, and you can play along with a backing track, a song from Apple Music, the built-in instrument or a metronome.",
 "url": "%s",
 "image": "%sassets/app-icon.png",
 "author": {"@type": "Organization", "name": "Caffeine Media", "url": "https://thecaffeinemediacompany.com/"}
}
</script>
""" % (BASE, BASE)
    letters = lambda w, cls="": "".join(f'<span class="ch">{c}</span>' for c in w)
    s = head("Maestro Pro - Sheet music that plays along, on iPhone, iPad or Mac",
             "Maestro Pro is a sheet music reader and player for iPhone, iPad or Mac. Notes light up as they sound, the page turns itself, and you play along with a backing track, a song from Apple Music, the built-in instrument or a metronome.",
             "", 0, extra=ld)
    s += top(0)
    s += f"""<main id="main">

<section class="hero">
  <div class="hero__stage">
    <div class="staff" aria-hidden="true"></div>
    <div class="playhead" aria-hidden="true"></div>
    <h1 class="title" aria-label="{NAME}"><span aria-hidden="true">{letters("Maestro")} <span class="pro">{letters("Pro")}</span></span></h1>
    <div class="hero__lede">
      <p class="tagline">Sheet music that plays along.</p>
      <div>
        <p class="hero__sub">Notes light up as they sound, the page turns itself, and you play along with a backing track, a song from Apple Music, the built-in instrument or just a metronome. For iPhone, iPad or Mac.</p>
        <div class="actions">
          {STORE}
          <a class="link" href="guide/index.html">Read the guide</a>
        </div>
      </div>
    </div>
  </div>
  <div class="device rise"><div class="device__body"><img fetchpriority="high" width="1100" height="1540" src="assets/shots/playing.webp" alt="Maestro Pro playing Ode to Joy: the current bar glows amber, the notes light as they sound, and the transport bar shows bar 3, beat 4."></div></div>
</section>

<section class="bar" id="features">
  <div class="wrap">
    <div class="split">
      <div class="rise">
        <h2>The page keeps up <em>with you.</em></h2>
        <p><strong>Press play and the music follows itself.</strong> The notes glow as they sound, a soft wash marks the bar, and the page scrolls or curls over like a real book exactly when you need it. Tap any note to start from there.</p>
        <p>Slow a hard passage right down without changing the pitch. Transpose for your clarinet, trumpet or saxophone, and the score is typeset again in the new key rather than just labelled. Count yourself in, loop a bar, switch on a metronome.</p>
      </div>
      <figure class="shot rise"><div class="device"><div class="device__body"><img loading="lazy" width="1100" height="1540" src="assets/shots/inspector.webp" alt="The inspector open beside the score, with tempo, practice speed, loop, key and transposition controls."></div></div><figcaption>The inspector: tempo, practice speed, loop, key and backing tracks.</figcaption></figure>
    </div>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <h2 class="rise">Everything a player <em>needs on the stand.</em></h2>
    <ul class="rows rise">{rows}</ul>
  </div>
</section>

<section class="bar" id="screenshots">
  <div class="wrap">
    <h2 class="rise">See it <em>in use.</em></h2>
    <h3 class="gal__h rise">On iPad</h3>
    <div class="gal"><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-1.webp" alt="Maestro Pro playing Nocturne Op. 9 No. 2 with the current notes lit on the page."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-2.webp" alt="The Maestro Pro library with a list of scores and the Import, Search, Scales and Tuner tiles."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-3.webp" alt="Lyrics on iPad with the current line in focus and a transport bar."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-4.webp" alt="Practising Gymnopédie No. 1 at a slower tempo."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-5.webp" alt="The score editor with the notes toolbar open."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1200" src="assets/shots/store-ipad-6.webp" alt="Search Scores, with Classical, Jazz and Internet tabs."></figure></div>
    <h3 class="gal__h rise">On Mac</h3>
    <div class="gal gal--mac"><figure class="gal__i rise"><img loading="lazy" width="1600" height="1000" src="assets/shots/store-mac-1.webp" alt="Maestro Pro on a Mac playing Nocturne Op. 9 No. 2."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1000" src="assets/shots/store-mac-2.webp" alt="The Maestro Pro library on a Mac."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1000" src="assets/shots/store-mac-3.webp" alt="Lyrics on a Mac with the current line in focus."></figure><figure class="gal__i rise"><img loading="lazy" width="1600" height="1000" src="assets/shots/store-mac-4.webp" alt="Practising Gymnopédie No. 1 on a Mac."></figure></div>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <h2 class="rise">Write it. Change it. <em>Put it right.</em></h2>
    <div class="pair">
      <figure class="shot rise"><div class="device"><div class="device__body"><img loading="lazy" width="1100" height="1540" src="assets/shots/editor.webp" alt="The score editor with the notes toolbar open at the bottom of the page."></div></div><figcaption>The editor: notes, rests, marks, dynamics and bars.</figcaption></figure>
      <div class="rise">
        <p style="color:var(--brass);max-width:52ch"><strong style="color:var(--cream);font-weight:600">Fix a wrong note, add a harmony, or write something new.</strong> Touch a note and slide it up or down, scribble over it to rub it out, tap a length to change it. The editor works out beams, ties and bar lengths for you.</p>
        <p style="color:var(--brass);max-width:52ch">Every save is a version you can come back to. Try an idea on a branch, merge it back bar by bar, spin a version off as a new score, and push the whole history to your own GitHub repository.</p>
        <p><a class="link" href="guide/version-history-github.html">How history and GitHub work</a></p>
      </div>
    </div>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <div class="split">
      <h2 class="rise">Teaching <em>music?</em></h2>
      <div class="rise"><p style="color:var(--brass);max-width:52ch">Maestro Pro gives students a patient practice partner and tutors a quicker way to prepare parts and run an ensemble. The free version can be rolled out to a whole school through Apple's volume purchasing.</p><p><a class="link" href="education.html">For Education</a></p></div>
    </div>
  </div>
</section>

<section class="bar" id="plans">
  <div class="wrap">
    <h2 class="rise">Start free. <em>Step up when you need more.</em></h2>
    <dl class="spec plans rise">
      <dt>Free</dt>
      <dd>Keep up to three scores and view the sheet music for each. Open lyrics files, play along with your own audio files, connect your own GitHub repositories and add tracks from them, and make scales and arpeggios in any key.
        <ul>
          <li>The built-in synth instruments play the score, but nothing follows along on the page: no note highlighting, bar highlighting or moving line until Performer.</li>
          <li>Nothing that needs the internet: no searching for scores, no finding lyrics or singers.</li>
          <li>No equaliser, key changes or other tools.</li>
        </ul></dd>
      <dt>Performer</dt>
      <dd><strong>Everything except the score editor.</strong> A library of any size, and notes, bars and a moving line that follow the music. Search Scores and lyrics online, key changes and the equaliser, backing tracks and Apple Music, Play Together, the tuner, Wait for Me, recording and review, annotation, export and print.</dd>
      <dt>Professional</dt>
      <dd><strong>Everything, including the score editor.</strong> Write and change music, build medleys, and keep version history with branches, merges and GitHub sync.</dd>
    </dl>
    <p class="note">The paid plans are subscriptions, managed in your Apple Account settings. Prices are shown in the app, in your own currency.</p>
  </div>
</section>

<section class="bar" id="compatibility">
  <div class="wrap">
    <h2 class="rise">What you need.</h2>
    <dl class="spec rise">
      <dt>Devices</dt>
      <dd><strong>iPhone</strong>, <strong>iPad</strong> or <strong>Mac</strong>. iPhone Duo is supported too.</dd>
      <dt>iPhone</dt>
      <dd><strong>iOS 17 or later.</strong> That covers iPhone XS and later, including iPhone XR and iPhone SE (2nd generation) and later. The layout adapts to the screen: one column on a phone held upright, and more room when it is turned on its side. On iPhone Duo the music and the controls use the space across both screens, and the playback bar folds away to give lyrics and karaoke the full screen.</dd>
      <dt>iPad</dt>
      <dd><strong>iPadOS 17 or later.</strong> That covers these iPads:
        <ul>
          <li>iPad Pro: 12.9-inch (2nd generation) and later, 11-inch (all), 10.5-inch</li>
          <li>iPad Air: 3rd generation and later</li>
          <li>iPad: 6th generation and later</li>
          <li>iPad mini: 5th generation and later</li>
        </ul>
        Any iPhone or iPad that can run iOS or iPadOS 17 can run Maestro Pro. Newer devices will turn pages, engrave and edit a long score more smoothly.</dd>
      <dt>Mac</dt>
      <dd><strong>macOS 14 Sonoma or later.</strong> You get the keyboard shortcuts, multiple windows and trackpad or mouse drawing.</dd>
      <dt>Apple Pencil</dt>
      <dd><strong>Optional.</strong> You do not need a Pencil to read, play, transpose or edit.
        <ul>
          <li><strong>Annotating</strong> on iPad uses Apple Pencil, so your finger still scrolls and taps. On a Mac you draw with the trackpad or mouse.</li>
          <li><strong>Editing</strong> works with a finger or a Pencil. A setting, Edit with Apple Pencil Only, stops a resting hand changing notes.</li>
          <li>Any Apple Pencil that works with your iPad will do: Apple Pencil (1st generation), (2nd generation), (USB-C) or Pro. Which one your iPad takes is listed on <a href="https://support.apple.com/en-us/108937" rel="noopener" style="color:var(--amber)">Apple’s Pencil compatibility page</a>.</li>
        </ul></dd>
      <dt>Optional extras</dt>
      <dd>
        <ul>
          <li><strong>Microphone</strong> for the tuner, Wait for Me and recording.</li>
          <li><strong>Camera</strong> for scanning printed music, which is coming in a future update.</li>
          <li><strong>Apple Music</strong> subscription to play along with a song and see its lyrics.</li>
          <li><strong>iCloud Drive</strong> to keep your library on all your devices.</li>
          <li><strong>Local network</strong> permission for Play Together. Devices find each other over Wi-Fi and Bluetooth, with no account.</li>
          <li><strong>Internet</strong> to search for scores, lyrics and singers, and for GitHub.</li>
        </ul></dd>
      <dt>Files it opens</dt>
      <dd>PDF, MusicXML (.musicxml, .xml, .mxl), MIDI and karaoke (.mid, .kar), lyrics (.lrc, .txt), CD+Graphics (.cdg) and Maestro Pro scores (.maestropro).</dd>
    </dl>
    <p class="note">Device lists follow Apple’s own for iOS 17, iPadOS 17 and macOS 14.</p>
  </div>
</section>

<section class="bar final">
  <div class="wrap">
    <h2 class="rise">Coming to the <em>App Store.</em></h2>
    <div class="rise">
      <p>Maestro Pro is coming soon to the App Store.</p>
      <div class="actions">{STORE}</div>
    </div>
  </div>
</section>

<div class="wrap"><p class="made-in rise">Created by <a href="https://thecaffeinemediacompany.com">Toby Jones</a> in England, UK</p></div>

</main>
"""
    s += foot(0).replace('<a href="privacy.html">', '<a href="canary/index.html">Canary builds</a><a href="privacy.html">')
    s = s.replace("</body>", """<script>
(function(){
var d=document,t=d.querySelector('.title'),ph=d.querySelector('.playhead'),stage=d.querySelector('.hero__stage');
var chars=[].slice.call(d.querySelectorAll('.title .ch'));
var calm=matchMedia('(prefers-reduced-motion: reduce)').matches;
function finish(){t.classList.add('done');ph.style.opacity=0}
if(calm||!t||!ph){if(t)t.classList.add('done')}
else{
  var sr=stage.getBoundingClientRect(),tr=t.getBoundingClientRect();
  var xs=chars.map(function(c){var r=c.getBoundingClientRect();return r.left-sr.left+r.width*.35});
  var from=chars[0].getBoundingClientRect().left-sr.left-24,to=chars[chars.length-1].getBoundingClientRect().right-sr.left+30;
  ph.style.top=(tr.top-sr.top-8)+'px';ph.style.bottom='auto';ph.style.height=(tr.height+16)+'px';
  var dur=2600,start=null;
  function frame(now){
    if(start===null)start=now;
    var p=Math.min(1,(now-start)/dur),e=1-Math.pow(1-p,2.2),x=from+(to-from)*e;
    ph.style.opacity=p<.04?p/.04:(p>.94?(1-p)/.06:1);ph.style.transform='translateX('+x+'px)';
    chars.forEach(function(c,i){if(x>=xs[i]&&!c.classList.contains('on')&&!c.classList.contains('set')){c.classList.add('on');setTimeout(function(){c.classList.remove('on');c.classList.add('set')},520)}});
    if(p<1)requestAnimationFrame(frame);else finish()
  }
  d.fonts&&d.fonts.ready?d.fonts.ready.then(function(){requestAnimationFrame(frame)}):requestAnimationFrame(frame);
  setTimeout(finish,6000)
}
var io='IntersectionObserver' in window?new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{rootMargin:'0px 0px -8% 0px'}):null;
[].forEach.call(d.querySelectorAll('.spec'),function(sp){[].forEach.call(sp.children,function(c,i){c.style.setProperty('--n',i)})});
[].forEach.call(d.querySelectorAll('.rise'),function(el){io?io.observe(el):el.classList.add('in')})
})();
</script>
</body>""")
    return s


# ---------------------------------------------------------------- for education

STUDENTS = [
    ("Practise at your own pace", "Slow a passage down without changing the pitch, loop the hard bars, count in, switch on a metronome. Speed it up again when it is ready.", "playing-a-score"),
    ("Play along", "Play with a backing track, a song from Apple Music, the built-in instrument or just a metronome, in the right key for your instrument.", "backing-tracks-sound"),
    ("Be listened to", "Wait for Me holds the score until the right note is played in tune. A tuner and a steady-note trainer sit alongside it.", "tuner-wait-for-me"),
    ("Hear yourself back", "Record a take against the score. The review shows wrong notes, late entries and the bars that need work, in plain words.", "record-review"),
    ("Your instrument, your key", "Transpose for B♭, E♭ or F instruments. Scales and arpeggios are made on demand, in any key, ready for the next grade.", "scales-arpeggios"),
    ("Mark it up", "Annotate with Apple Pencil like a paper part. The ink stays with the score and prints in exported PDFs.", "annotating"),
    ("Made to be readable", "Larger text, high contrast, reduced motion and your own colours, so more students can use it comfortably.", "settings-accessibility"),
]

TUTORS = [
    ("Everyone in time", "Link up to eight devices. Play, pause and seek on one and all of them follow, each student on their own part, key and instrument.", "play-together"),
    ("Parts without the wait", "Write a part, fix a note, transpose for each instrument, build a medley. The editor looks after beams, ties and bar lengths.", "writing-editing-music"),
    ("Keep every arrangement", "Each save is a version. Keep one branch per ensemble, merge ideas back, spin a version off as a score for one student, and push the history to your own GitHub repository.", "version-history-github"),
    ("Hand it out", "Send a score and its backing track as one file by AirDrop, Messages or Files. Export MusicXML or PDF, or print.", "share-export-print"),
    ("Plan the lesson", "Set-lists for a lesson, a rehearsal or a concert. Import PDF, MusicXML, MIDI and karaoke files, or search for free scores.", "your-library"),
    ("Teach on the page", "Draw on the score while you explain it, and turn a score into a video of the music following along.", "annotating"),
    ("Choirs and singers", "Lyrics scroll in time, duets get a singer each in their own colour, and karaoke files show their words.", "lyrics-karaoke"),
]

def education():
    def rows(items):
        return "".join(f'<li style="--i:{i}"><a href="guide/{s}.html"><b>{esc(n)}</b><span>{esc(d)}</span><span class="go">Read more →</span></a></li>' for i, (n, d, s) in enumerate(items))
    ld = """<script type="application/ld+json">
{
 "@context": "https://schema.org",
 "@type": "WebPage",
 "name": "Maestro Pro for Education",
 "url": "%seducation.html",
 "description": "How Maestro Pro helps music students practise and music tutors teach, with details of Apple's volume licensing."
}
</script>
""" % BASE
    s = head("Maestro Pro for Education - for music schools, tutors and students",
             "How Maestro Pro helps music students practise and music tutors teach, from slowing a passage down to running a whole ensemble in time. Includes details of Apple's volume licensing for schools.",
             "education.html", 0, og="assets/shots/inspector.webp", extra=ld)
    s += top(0, "For Education")
    s += f"""<main id="main">

<section class="hero hero--plain">
  <div class="hero__stage">
    <div class="staff" aria-hidden="true"></div>
    <h1 class="title title--sub done">For <span class="pro">Education.</span></h1>
    <div class="hero__lede">
      <p class="tagline">A practice partner for every student. A time-saver for every tutor.</p>
      <div>
        <p class="hero__sub">Maestro Pro puts each player's own part on their own iPad or Mac, plays along at any speed and in any key, and listens to them play. For music schools, music services, colleges and private tutors.</p>
        <div class="actions">
          {STORE}
          <a class="link" href="#licensing">Volume licensing</a>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <h2 class="rise">Better practice, <em>between lessons.</em></h2>
    <p class="rise" style="color:var(--brass);max-width:60ch">A student with a lesson a week plays alone for the other six days. Maestro Pro gives that time a patient partner: it plays the rest of the music, waits when they stumble, and tells them afterwards where the notes went wrong.</p>
    <ul class="rows rise">{rows(STUDENTS)}</ul>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <h2 class="rise">Less preparation, <em>more teaching.</em></h2>
    <p class="rise" style="color:var(--brass);max-width:60ch">Most of a tutor's evenings go on finding, fixing and printing music for different instruments. Maestro Pro turns that into minutes and keeps a rehearsal together once it starts.</p>
    <ul class="rows rise">{rows(TUTORS)}</ul>
  </div>
</section>

<section class="bar">
  <div class="wrap">
    <div class="split">
      <div class="rise">
        <h2>Nothing to sign up <em>for.</em></h2>
        <p>There are no student accounts and no adverts, and Maestro Pro does not collect personal data. It counts which features are used with anonymous, privacy-friendly analytics (see the privacy page). Scores, recordings and drawings stay on the device, or in the user's own iCloud if they switch it on. Microphone audio is analysed on the device.</p>
        <p>That keeps a data protection review short. Check the details against your own school's policy and read the <a class="link" href="privacy.html">privacy page</a>.</p>
      </div>
      <figure class="shot rise"><div class="device"><div class="device__body"><img loading="lazy" width="1100" height="1540" src="assets/shots/home.webp" alt="The Maestro Pro home screen with Import Score, Search Scores, Scales and Arpeggios and Tuner."></div></div><figcaption>The home screen: import a score, search for one, make a scale or tune up.</figcaption></figure>
    </div>
  </div>
</section>

<section class="bar" id="licensing">
  <div class="wrap">
    <h2 class="rise">Buying for a <em>whole school.</em></h2>
    <p class="rise" style="color:var(--brass);max-width:60ch">Apple lets schools and organisations buy apps in bulk and hand them out to their own devices and people. Here is how that works, and where Maestro Pro's plans fit.</p>
    <dl class="spec rise">
      <dt>What it is</dt>
      <dd>Volume purchasing through <strong>Apps and Books</strong> in Apple's management portals. The organisation gets licences in the quantity it needs and owns them, rather than every student downloading a copy on a personal account.</dd>
      <dt>Who it is for</dt>
      <dd><ul>
        <li><strong>Apple School Manager</strong> is for schools, colleges, universities and local authority or music-service teams. Free to enrol.</li>
        <li><strong>Apple Business Manager</strong> is for other organisations, such as a private music academy or tuition company. Free to enrol.</li>
        <li>Both need the organisation to be verified by Apple. Your IT lead or administrator usually does this once.</li>
      </ul></dd>
      <dt>How it works</dt>
      <dd><ul>
        <li>An administrator signs in to the portal, finds the app in Apps and Books, and chooses how many licences to get.</li>
        <li>Licences are assigned to <strong>devices</strong>, so students need no Apple Account at all, or to <strong>people</strong> with Managed Apple Accounts.</li>
        <li>The app is installed through your mobile device management (MDM) service, such as Jamf, Mosyle or Microsoft Intune, or from the App Store by the person it is assigned to.</li>
        <li>When a student leaves or a device is replaced, the licence is taken back and given to someone else. It is not lost.</li>
      </ul></dd>
      <dt>Where Maestro Pro fits</dt>
      <dd>The <strong>free</strong> version, which keeps up to three scores, can be rolled out to every device this way. <strong>Performer</strong> and <strong>Professional</strong> are subscriptions. Apple's volume purchasing covers apps rather than subscriptions, so each person who needs a paid plan subscribes on their own Apple Account. Apple's terms can change, so check their pages below.</dd>
      <dt>Which plan</dt>
      <dd><ul>
        <li><strong>Free</strong> for a student who only needs to read their part.</li>
        <li><strong>Performer</strong> for students who practise with the full set of tools.</li>
        <li><strong>Professional</strong> for tutors who write and arrange parts.</li>
      </ul>
      <a href="index.html#plans" style="color:var(--amber)">All the plans</a></dd>
      <dt>Availability</dt>
      <dd>Volume purchasing is not offered in every country or region. Check Apple's pages for yours: <a href="https://support.apple.com/guide/apple-school-manager/welcome/web" rel="noopener" style="color:var(--amber)">Apple School Manager</a> and <a href="https://support.apple.com/guide/apple-business-manager/welcome/web" rel="noopener" style="color:var(--amber)">Apple Business Manager</a>.</dd>
    </dl>
    <p class="note">This page describes Apple's scheme as it stands, for guidance only. Apple's own pages have the current terms.</p>
  </div>
</section>

<section class="bar final">
  <div class="wrap">
    <h2 class="rise">Try it with <em>a class.</em></h2>
    <div class="rise">
      <p>Maestro Pro is coming soon to the App Store.</p>
      <div class="actions"><a class="link" href="index.html#plans">See the plans</a><a class="link" href="index.html#compatibility">Which devices it runs on</a></div>
    </div>
  </div>
</section>

</main>
"""
    s += foot(0)
    s = s.replace("</body>", RISE + "\n</body>")
    return s

RISE = """<script>
(function(){var d=document;var io='IntersectionObserver' in window?new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{rootMargin:'0px 0px -8% 0px'}):null;
[].forEach.call(d.querySelectorAll('.spec'),function(sp){[].forEach.call(sp.children,function(c,i){c.style.setProperty('--n',i)})});
[].forEach.call(d.querySelectorAll('.rise'),function(el){io?io.observe(el):el.classList.add('in')})})();
</script>"""

# ---------------------------------------------------------------- the guide

def guide_nav(tops, current):
    out = ['<details class="guide__nav" open><summary>Guide topics</summary><nav aria-label="Guide">']
    out.append(f'<a href="index.html"{CUR if current == "index" else ""}>Guide home</a>')
    by = {t["title"]: t for t in tops}
    for g, names in GROUPS:
        out.append(f"<h2>{esc(g)}</h2>")
        for n in names:
            if n in by: out.append(f'<a href="{slug(n)}.html"{CUR if current == n else ""}>{esc(n)}</a>')
    out.append("</nav></details>")
    return "\n".join(out)

def guide_pages(tops):
    order = [n for _, names in GROUPS for n in names]
    by = {t["title"]: t for t in tops}
    assert set(order) == set(by), set(order) ^ set(by)
    pages = {}
    # index
    body = ['<a class="back" href="../index.html">← Back to Maestro Pro</a>', "<h1>The guide.</h1>",
            '<p class="guide__lede">Every part of Maestro Pro, one topic to a page. New here? Start with <a href="getting-started.html">Getting Started</a>. The same text is in the app, under Help.</p>']
    for g, names in GROUPS:
        body.append(f'<h2 class="group">{esc(g)}</h2><ul class="topics">')
        for n in names:
            body.append(f'<li><a href="{slug(n)}.html"><b>{esc(n)}</b><span>{esc(by[n]["intro"])}</span></a></li>')
        body.append("</ul>")
    pages["index"] = shell("Guide", "Every feature of Maestro Pro, explained in depth: playing, practising, editing, version history, lyrics, Play Together and more.", "guide/", tops, "index", "\n".join(body), "")
    for i, n in enumerate(order):
        t = by[n]
        toc = '<ul class="toc" aria-label="On this page">' + "".join(f'<li><a href="#{slug(h)}">{esc(h)}</a></li>' for h, _ in t["sections"]) + "</ul>"
        body = ['<a class="back" href="index.html">← Guide</a>', f"<h1>{esc(n)}</h1>", f'<p class="guide__lede">{esc(t["intro"])}</p>', toc]
        for h, paras in t["sections"]:
            body.append(f'<h2 id="{slug(h)}">{esc(h)}</h2>')
            body += [f"<p>{esc(p)}</p>" for p in paras]
        prev = f'<a href="{slug(order[i-1])}.html">← {esc(order[i-1])}</a>' if i else "<span></span>"
        nxt = f'<a href="{slug(order[i+1])}.html">{esc(order[i+1])} →</a>' if i + 1 < len(order) else "<span></span>"
        body.append(f'<div class="pager">{prev}{nxt}</div>')
        pages[slug(n)] = shell(n, t["intro"], f"guide/{slug(n)}.html", tops, n, "\n".join(body), n)
    return pages

def shell(title, desc, path, tops, current, body, crumb):
    s = head(f"{title} - {NAME} guide" if title != "Guide" else f"Guide - {NAME}", desc, path, 1, read=True,
             extra="")
    s += top(1, "Guide")
    s += f'<main id="main" class="guide">\n{guide_nav(tops, current)}\n<article class="guide__body">\n{body}\n</article>\n</main>\n'
    s += foot(1).replace("</body>", "<script>if(matchMedia('(max-width:860px)').matches)document.querySelector('.guide__nav').open=false</script>\n</body>")
    return s

# ---------------------------------------------------------------- support and privacy

def plain(title, desc, path, body):
    s = head(f"{title} - {NAME}", desc, path, 0, read=True) + top(0)
    s += f'<main id="main" class="plain">\n<h1>{esc(title)}</h1>\n{body}\n</main>\n' + foot(0)
    return s

SUPPORT = f"""<p>Maestro Pro is made by one person, Toby Jones. If something is not working, or you have an idea, send an email and you will get a real reply.</p>
<p><a href="mailto:{EMAIL}?subject=Maestro%20Pro%20support">{EMAIL}</a></p>
<h2>Before you write</h2>
<p>The <a href="guide/index.html">guide</a> covers every feature, and <a href="guide/troubleshooting.html">Troubleshooting</a> answers the common questions: no sound, a score that will not follow, a tuner that cannot hear you, notes the app read wrongly from a PDF.</p>
<h2>What helps</h2>
<p>Tell me which iPhone, iPad or Mac you have, which version of iOS, iPadOS or macOS it runs, and what you were doing when it went wrong. If a score is the problem, say what kind of file it is (PDF, MusicXML, MIDI).</p>"""

PRIVACY = f"""<p>Last updated 21 October 2026.</p>
<p>Maestro Pro has no accounts and no adverts, and it does not collect personal data. It does count which features are used, anonymously (see Usage statistics below). Caffeine Media does not receive your scores, recordings or anything else you do in the app.</p>
<h2>What stays on your device</h2>
<p>Your library (scores, backing tracks, lyrics, drawings, recordings and version history) is stored in the app’s folder on your device. If you turn on iCloud Drive, it is kept in the app’s iCloud folder in your own iCloud account, so it is available on your other devices. That storage belongs to you and Apple; the developer cannot see it.</p>
<h2>Permissions</h2>
<ul>
<li><strong>Microphone:</strong> to hear whether you are playing the right note, to tune, and to record you. Audio is processed on the device. Recordings are saved only in your library.</li>
<li><strong>Camera:</strong> scanning printed music with the camera is planned for a future update. The app does not use the camera today.</li>
<li><strong>Apple Music:</strong> to play a song from your subscription alongside a score and show its lyrics. This uses Apple’s own service under your account.</li>
<li><strong>Local network:</strong> so devices can find each other for Play Together. Messages go directly between the devices and are encrypted.</li>
</ul>
<h2>When the app uses the internet</h2>
<p>Only when you ask it to. Searching for scores, lyrics or singers sends your search words (and, to match singers, the song title and artist) to the services that answer: the web search engine used for Search Scores and the sites it finds, GitHub, LRCLIB (lyrics) and Genius (singers). Downloading a free score fetches it from the site that hosts it. Those services have their own privacy policies.</p>
<h2>Usage statistics</h2>
<p>Maestro Pro uses <a href="https://aptabase.com">Aptabase</a>, a privacy-friendly analytics service hosted in the EU, to count how the app is used so I can see which features matter and what to improve. Each event is a short name, such as “play” or “export_pdf”, with a few simple details such as a file type or an on/off choice.</p>
<p>With each event the app also sends the app version, the operating system and its version, the device model, your language and region, a time, and a random session number that changes after an hour of inactivity. There is no account, no name, no email address, no advertising identifier and no fixed device identifier, so events cannot be tied back to you. Aptabase does not use cookies and does not store IP addresses.</p>
<p>Nothing from your library is ever sent: no score or song titles, lyrics, search words, file names, recordings or drawings. The statistics are not shared with advertisers and are not used to track you across other apps or websites.</p>
<h2>GitHub</h2>
<p>If you connect a score to a GitHub repository, the app talks to GitHub using a personal access token you provide. The token is kept in your device’s Keychain and is sent only to GitHub. Pushing sends your score’s versions to the repository you chose, and nothing else.</p>
<h2>Feedback</h2>
<p>Provide Feedback in Settings posts what you type, the title and description, to the public feedback board at <a href="https://thecaffeinemediacompany.fider.io">thecaffeinemediacompany.fider.io</a>, tagged for Maestro Pro. Anything you send there can be read by anyone, so please leave out personal details. Nothing else is sent with it.</p>
<h2>This website</h2>
<p>This website uses Google Analytics after you interact with it, and shows a cookie notice. That applies to the website, not to the app.</p>
<h2>Contact</h2>
<p>Questions about privacy: <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>"""

# ---------------------------------------------------------------- write

def write(rel, text):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(text)

if __name__ == "__main__":
    tops = topics()
    write("index.html", page())
    write("education.html", education())
    write("support.html", plain("Support", "Help and contact for Maestro Pro.", "support.html", SUPPORT))
    write("privacy.html", plain("Privacy", "How Maestro Pro handles your data.", "privacy.html", PRIVACY))
    for name, text in guide_pages(tops).items():
        write(f"guide/{name}.html", text)
    print(len(tops), "topics ->", OUT)
