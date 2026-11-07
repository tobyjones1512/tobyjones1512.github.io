#!/usr/bin/env python3
"""Localised App Store screenshots (iPhone, iPhone Duo, iPad, Mac) and the paywall captures.

Raw simulator captures: AppStore/raw (iPad/Mac, older) and AppStore/raw2 (iPhone, Duo, paywalls).
Output: AppStore/Screenshots/<Language>/<Device>/<n>-<key>.png and AppStore/Paywalls/<Device>/*.png
Run: python3 Tools/make-localised-shots.py [lang ...]
"""
import importlib.util
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("base", os.path.join(HERE, "make-store-shots.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

ROOT = base.ROOT
RAW2 = os.path.join(ROOT, "raw2")
AMBER, CREAM, MUTED = base.AMBER, base.CREAM, base.MUTED

# (headline, subline) per slide key, per language.
T = {
    "en": {
        "sheetP": ("Your sheet music.\nAlways in your pocket.", "Open any score from your iPad or Mac, crisp and ready to read."),
        "tunerP": ("A pro tuner,\nright in your pocket", "Hold a note and see how sharp or flat you are, to the cent."),
        "plansP": ("Free to read.\nUnlock it all.", "Performer or Professional, weekly or yearly."),
        "trialP": ("Try it free\nfor 3 days", "Every weekly plan starts with a free trial."),
        "playD": ("Unfold the\nfull stage", "Every note lights up as it plays, on your Duo's big screen."),
        "chordsD": ("Every chord,\nin plain sight", "A clear chord chart that follows the music."),
        "libD": ("Your library,\none tap away", "Scores, lyrics and a tuner, right where you need them."),
        "plansD": ("Unlock\neverything", "Performer or Professional. Weekly or yearly."),
        "play": ("Watch every note\ncome alive", "Notes light up as they sound. Pages turn themselves. You just play."),
        "lib": ("Your entire library.\nOne tap.", "Scores, lyrics, scales and a tuner, all in one beautiful place."),
        "libMac": ("Your entire library.\nOne click.", "Scores, lyrics, scales and a tuner, all in one beautiful place."),
        "lyrics": ("Karaoke-grade lyrics,\nbuilt in", "Every line glows in time, so you never lose your place."),
        "practise": ("Practise smarter,\nnot longer", "Slow it down, loop the hard bar, change the key."),
        "edit": ("Write music.\nRight on the page.", "A full score editor for notes, rests, dynamics and more."),
        "search": ("Find free scores\nin seconds", "Browse classical to jazz and add them with one tap."),
        "chords": ("See every chord\nat a glance", "A clear chord chart that follows the music."),
        "plans": ("Free to try.\nEasy to love.", "Performer or Professional, weekly or yearly. Start with 3 free days."),
    },
    "fr": {
        "sheetP": ("Vos partitions.\nToujours dans la poche.", "Ouvrez toute partition de votre iPad ou Mac, nette et prête à lire."),
        "tunerP": ("Un accordeur pro,\ndans votre poche", "Jouez une note et voyez si elle est haute ou basse, au cent près."),
        "plansP": ("Lecture gratuite.\nDébloquez tout.", "Performer ou Professional, à la semaine ou à l'année."),
        "trialP": ("Essayez gratuitement\npendant 3 jours", "Chaque formule hebdomadaire commence par un essai gratuit."),
        "playD": ("Dépliez\nla grande scène", "Chaque note s'illumine en jouant, sur le grand écran de votre Duo."),
        "chordsD": ("Chaque accord,\nsous vos yeux", "Une grille d'accords claire qui suit la musique."),
        "libD": ("Votre bibliothèque,\nà portée de doigt", "Partitions, paroles et accordeur, exactement où il faut."),
        "plansD": ("Débloquez\ntout", "Performer ou Professional. À la semaine ou à l'année."),
        "play": ("Voyez chaque note\ns'animer", "Les notes s'allument au son. Les pages se tournent seules. Vous jouez, c'est tout."),
        "lib": ("Toute votre bibliothèque.\nD'une touche.", "Partitions, paroles, gammes et accordeur, réunis en un bel endroit."),
        "libMac": ("Toute votre bibliothèque.\nD'un clic.", "Partitions, paroles, gammes et accordeur, réunis en un bel endroit."),
        "lyrics": ("Des paroles dignes\ndu karaoké", "Chaque ligne s'illumine en rythme, sans jamais perdre le fil."),
        "practise": ("Travaillez mieux,\npas plus longtemps", "Ralentissez, bouclez la mesure difficile, changez de tonalité."),
        "edit": ("Écrivez la musique.\nDirectement sur la page.", "Un éditeur complet : notes, silences, nuances et plus encore."),
        "search": ("Trouvez des partitions\ngratuites en un instant", "Du classique au jazz, ajoutez-les d'une simple touche."),
        "chords": ("Chaque accord\nd'un coup d'œil", "Une grille d'accords claire qui suit la musique."),
        "plans": ("Gratuit pour essayer.\nFacile à adorer.", "Performer ou Professional, à la semaine ou à l'année. 3 jours offerts."),
    },
    "de": {
        "sheetP": ("Deine Noten.\nImmer dabei.", "Öffne jede Partitur von iPad oder Mac, gestochen scharf und sofort lesbar."),
        "tunerP": ("Ein Profi-Stimmgerät\nin der Tasche", "Spiel einen Ton und sieh auf den Cent genau, ob er zu hoch oder zu tief ist."),
        "plansP": ("Lesen ist gratis.\nSchalte alles frei.", "Performer oder Professional, wöchentlich oder jährlich."),
        "trialP": ("3 Tage\nkostenlos testen", "Jedes Wochenabo startet mit einer kostenlosen Testphase."),
        "playD": ("Klapp die große\nBühne auf", "Jede Note leuchtet beim Spielen auf, auf dem großen Display deines Duo."),
        "chordsD": ("Jeder Akkord\nauf einen Blick", "Ein klares Akkordschema, das der Musik folgt."),
        "libD": ("Deine Bibliothek,\nein Tipp entfernt", "Noten, Songtexte und Stimmgerät genau dort, wo du sie brauchst."),
        "plansD": ("Alles\nfreischalten", "Performer oder Professional. Wöchentlich oder jährlich."),
        "play": ("Erlebe jede Note\nlebendig", "Noten leuchten im Takt auf. Seiten blättern von selbst. Du spielst einfach."),
        "lib": ("Deine ganze Bibliothek.\nEin Tipp.", "Noten, Texte, Tonleitern und Stimmgerät an einem schönen Ort."),
        "libMac": ("Deine ganze Bibliothek.\nEin Klick.", "Noten, Texte, Tonleitern und Stimmgerät an einem schönen Ort."),
        "lyrics": ("Songtexte in\nKaraoke-Qualität", "Jede Zeile leuchtet im Takt, sodass du nie die Stelle verlierst."),
        "practise": ("Smarter üben,\nnicht länger", "Langsamer spielen, schwere Takte wiederholen, Tonart ändern."),
        "edit": ("Schreibe Musik.\nDirekt auf dem Blatt.", "Ein vollständiger Partitureditor für Noten, Pausen, Dynamik und mehr."),
        "search": ("Gratis-Noten\nin Sekunden finden", "Von Klassik bis Jazz stöbern und mit einem Tipp hinzufügen."),
        "chords": ("Jeden Akkord\nauf einen Blick", "Ein klares Akkordschema, das der Musik folgt."),
        "plans": ("Gratis testen.\nLeicht lieben.", "Performer oder Professional, wöchentlich oder jährlich. Starte mit 3 Gratistagen."),
    },
    "es": {
        "sheetP": ("Tus partituras.\nSiempre contigo.", "Abre cualquier partitura de tu iPad o Mac, nítida y lista para leer."),
        "tunerP": ("Un afinador pro\nen tu bolsillo", "Toca una nota y mira cuánto te desvías, al céntimo."),
        "plansP": ("Leer es gratis.\nDesbloquea todo.", "Performer o Professional, semanal o anual."),
        "trialP": ("Pruébalo gratis\n3 días", "Cada plan semanal empieza con una prueba gratuita."),
        "playD": ("Despliega\nel gran escenario", "Cada nota se ilumina al sonar, en la gran pantalla de tu Duo."),
        "chordsD": ("Cada acorde,\na la vista", "Un cifrado de acordes claro que sigue la música."),
        "libD": ("Tu biblioteca,\na un toque", "Partituras, letras y afinador justo donde los necesitas."),
        "plansD": ("Desbloquea\ntodo", "Performer o Professional. Semanal o anual."),
        "play": ("Mira cada nota\ncobrar vida", "Las notas se iluminan al sonar. Las páginas pasan solas. Tú solo tocas."),
        "lib": ("Toda tu biblioteca.\nUn toque.", "Partituras, letras, escalas y afinador en un solo lugar precioso."),
        "libMac": ("Toda tu biblioteca.\nUn clic.", "Partituras, letras, escalas y afinador en un solo lugar precioso."),
        "lyrics": ("Letras con nivel\nde karaoke", "Cada línea brilla a tiempo, para que nunca pierdas el hilo."),
        "practise": ("Practica mejor,\nno más tiempo", "Reduce la velocidad, repite el compás difícil, cambia la tonalidad."),
        "edit": ("Escribe música.\nSobre la propia página.", "Un editor completo de notas, silencios, dinámicas y más."),
        "search": ("Encuentra partituras\ngratis en segundos", "Del clásico al jazz, añádelas con un toque."),
        "chords": ("Cada acorde\nde un vistazo", "Un cifrado de acordes claro que sigue la música."),
        "plans": ("Gratis para probar.\nFácil de amar.", "Performer o Professional, semanal o anual. Empieza con 3 días gratis."),
    },
    "zh": {
        "sheetP": ("你的乐谱，\n随身携带", "打开 iPad 或 Mac 上的任何乐谱，清晰锐利，随时阅读。"),
        "tunerP": ("口袋里的\n专业调音器", "弹一个音，精确到音分显示偏高还是偏低。"),
        "plansP": ("阅读免费，\n解锁全部功能", "Performer 或 Professional，按周或按年订阅。"),
        "trialP": ("免费试用\n3 天", "每个周订阅方案都包含免费试用。"),
        "playD": ("展开屏幕，\n尽享大舞台", "音符随演奏逐一亮起，在 Duo 的大屏幕上呈现。"),
        "chordsD": ("每个和弦，\n一目了然", "清晰的和弦图，紧随音乐前进。"),
        "libD": ("你的乐谱库，\n轻点即达", "乐谱、歌词和调音器，就在你需要的地方。"),
        "plansD": ("解锁\n全部功能", "Performer 或 Professional。按周或按年。"),
        "play": ("看每个音符\n鲜活起来", "音符随声音亮起，页面自动翻动，你只管演奏。"),
        "lib": ("整个乐谱库，\n轻轻一点", "乐谱、歌词、音阶和调音器，尽在一处。"),
        "libMac": ("整个乐谱库，\n轻轻一点击", "乐谱、歌词、音阶和调音器，尽在一处。"),
        "lyrics": ("卡拉 OK 级\n歌词显示", "每一行随节拍亮起，让你永不迷失位置。"),
        "practise": ("更聪明地练，\n而不是更久", "放慢速度、循环难点小节、随时变调。"),
        "edit": ("写下音乐，\n就在乐谱上", "完整的乐谱编辑器：音符、休止符、力度等一应俱全。"),
        "search": ("几秒钟找到\n免费乐谱", "从古典到爵士，轻点即可添加。"),
        "chords": ("每个和弦\n一目了然", "清晰的和弦图，紧随音乐前进。"),
        "plans": ("免费体验，\n轻松爱上", "Performer 或 Professional，按周或按年。先免费试用 3 天。"),
    },
    "ja": {
        "sheetP": ("あなたの楽譜を、\nいつでもポケットに", "iPad や Mac の楽譜をどれでも開いて、くっきり読みやすく。"),
        "tunerP": ("プロ仕様のチューナーを\nポケットに", "音を鳴らせば、高いか低いかをセント単位で表示。"),
        "plansP": ("閲覧は無料。\nすべてを解放", "Performer か Professional、週払いか年払いで。"),
        "trialP": ("3 日間\n無料で体験", "週間プランはすべて無料体験から始まります。"),
        "playD": ("開いて広がる、\nフルステージ", "演奏に合わせて音符が光る。Duo の大画面で。"),
        "chordsD": ("すべてのコードが\nひと目で", "音楽に合わせて進む、見やすいコード譜。"),
        "libD": ("ライブラリは\nワンタップで", "楽譜、歌詞、チューナーを必要な場所に。"),
        "plansD": ("すべてを\nアンロック", "Performer か Professional。週払いか年払いで。"),
        "play": ("音符が\n生きて見える", "音に合わせて音符が光り、ページは自動でめくれる。あなたは弾くだけ。"),
        "lib": ("ライブラリ全体を、\nワンタップで", "楽譜、歌詞、スケール、チューナーをひとつの美しい場所に。"),
        "libMac": ("ライブラリ全体を、\nワンクリックで", "楽譜、歌詞、スケール、チューナーをひとつの美しい場所に。"),
        "lyrics": ("カラオケ級の\n歌詞表示", "一行ずつ拍に合わせて光り、見失いません。"),
        "practise": ("長くより、\n賢く練習", "テンポを落とし、難しい小節をループ、キーも変更。"),
        "edit": ("楽譜の上で、\n音楽を書く", "音符、休符、強弱記号まで扱えるフル機能の楽譜エディタ。"),
        "search": ("無料の楽譜が\n数秒で見つかる", "クラシックからジャズまで、ワンタップで追加。"),
        "chords": ("すべてのコードが\nひと目で", "音楽に合わせて進む、見やすいコード譜。"),
        "plans": ("無料で試せる。\nきっと好きになる。", "Performer か Professional、週払いか年払い。まず 3 日間無料。"),
    },
    "sv": {
        "sheetP": ("Dina noter.\nAlltid i fickan.", "Öppna vilken partitur som helst från din iPad eller Mac, skarpt och lättläst."),
        "tunerP": ("En proffsstämmare\ni fickan", "Spela en ton och se hur hög eller låg den är, på cent när."),
        "plansP": ("Gratis att läsa.\nLås upp allt.", "Performer eller Professional, varje vecka eller varje år."),
        "trialP": ("Prova gratis\ni 3 dagar", "Alla veckoplaner börjar med en gratis provperiod."),
        "playD": ("Fäll ut\nhela scenen", "Varje ton lyser upp när den spelas, på Duons stora skärm."),
        "chordsD": ("Varje ackord,\ntydligt i bild", "Ett tydligt ackordschema som följer musiken."),
        "libD": ("Ditt bibliotek,\nett tryck bort", "Noter, sångtexter och stämmare precis där du behöver dem."),
        "plansD": ("Lås upp\nallt", "Performer eller Professional. Varje vecka eller varje år."),
        "play": ("Se varje ton\nvakna till liv", "Tonerna lyser upp när de klingar. Sidorna bläddrar sig själva. Du bara spelar."),
        "lib": ("Hela ditt bibliotek.\nEtt tryck.", "Noter, texter, skalor och stämmare på ett vackert ställe."),
        "libMac": ("Hela ditt bibliotek.\nEtt klick.", "Noter, texter, skalor och stämmare på ett vackert ställe."),
        "lyrics": ("Sångtexter i\nkaraokeklass", "Varje rad lyser i takt, så du aldrig tappar bort dig."),
        "practise": ("Öva smartare,\ninte längre", "Sänk tempot, loopa det svåra taktslaget, byt tonart."),
        "edit": ("Skriv musik.\nDirekt på sidan.", "En komplett partitureditor för toner, pauser, dynamik och mer."),
        "search": ("Hitta gratis noter\npå sekunder", "Bläddra från klassiskt till jazz och lägg till med ett tryck."),
        "chords": ("Se varje ackord\npå en blick", "Ett tydligt ackordschema som följer musiken."),
        "plans": ("Gratis att prova.\nLätt att älska.", "Performer eller Professional, varje vecka eller år. Börja med 3 gratisdagar."),
    },
    "pt": {
        "sheetP": ("Suas partituras.\nSempre no bolso.", "Abra qualquer partitura do seu iPad ou Mac, nítida e pronta para ler."),
        "tunerP": ("Um afinador profissional\nno bolso", "Toque uma nota e veja se está alta ou baixa, ao centésimo."),
        "plansP": ("Ler é grátis.\nDesbloqueie tudo.", "Performer ou Professional, semanal ou anual."),
        "trialP": ("Experimente grátis\npor 3 dias", "Todo plano semanal começa com um teste gratuito."),
        "playD": ("Desdobre o\npalco inteiro", "Cada nota se ilumina ao soar, na tela grande do seu Duo."),
        "chordsD": ("Cada acorde,\nà vista", "Uma cifra de acordes clara que acompanha a música."),
        "libD": ("Sua biblioteca,\na um toque", "Partituras, letras e afinador onde você precisa."),
        "plansD": ("Desbloqueie\ntudo", "Performer ou Professional. Semanal ou anual."),
        "play": ("Veja cada nota\nganhar vida", "As notas acendem ao soar. As páginas viram sozinhas. Você só toca."),
        "lib": ("Toda a sua biblioteca.\nUm toque.", "Partituras, letras, escalas e afinador num só lugar bonito."),
        "libMac": ("Toda a sua biblioteca.\nUm clique.", "Partituras, letras, escalas e afinador num só lugar bonito."),
        "lyrics": ("Letras com nível\nde karaokê", "Cada linha brilha no tempo, para você nunca se perder."),
        "practise": ("Pratique melhor,\nnão por mais tempo", "Desacelere, repita o compasso difícil, mude o tom."),
        "edit": ("Escreva música.\nDireto na página.", "Um editor completo de notas, pausas, dinâmicas e mais."),
        "search": ("Encontre partituras\ngrátis em segundos", "Do clássico ao jazz, adicione com um toque."),
        "chords": ("Cada acorde\nnum relance", "Uma cifra de acordes clara que acompanha a música."),
        "plans": ("Grátis para testar.\nFácil de amar.", "Performer ou Professional, semanal ou anual. Comece com 3 dias grátis."),
    },
    "it": {
        "sheetP": ("I tuoi spartiti.\nSempre in tasca.", "Apri qualsiasi spartito dal tuo iPad o Mac, nitido e pronto da leggere."),
        "tunerP": ("Un accordatore pro\nin tasca", "Suona una nota e vedi se è calante o crescente, al centesimo."),
        "plansP": ("Leggere è gratis.\nSblocca tutto.", "Performer o Professional, settimanale o annuale."),
        "trialP": ("Prova gratis\nper 3 giorni", "Ogni piano settimanale inizia con una prova gratuita."),
        "playD": ("Apri il\npalco intero", "Ogni nota si illumina mentre suona, sul grande schermo del tuo Duo."),
        "chordsD": ("Ogni accordo,\nsotto i tuoi occhi", "Una griglia di accordi chiara che segue la musica."),
        "libD": ("La tua libreria,\na un tocco", "Spartiti, testi e accordatore proprio dove servono."),
        "plansD": ("Sblocca\ntutto", "Performer o Professional. Settimanale o annuale."),
        "play": ("Guarda ogni nota\nprendere vita", "Le note si accendono mentre suonano. Le pagine si girano da sole. Tu suoni e basta."),
        "lib": ("Tutta la tua libreria.\nUn tocco.", "Spartiti, testi, scale e accordatore in un unico posto splendido."),
        "libMac": ("Tutta la tua libreria.\nUn clic.", "Spartiti, testi, scale e accordatore in un unico posto splendido."),
        "lyrics": ("Testi da\nkaraoke", "Ogni riga si illumina a tempo, così non perdi mai il segno."),
        "practise": ("Studia meglio,\nnon più a lungo", "Rallenta, ripeti la battuta difficile, cambia tonalità."),
        "edit": ("Scrivi musica.\nDirettamente sulla pagina.", "Un editor completo per note, pause, dinamiche e altro."),
        "search": ("Trova spartiti\ngratis in pochi secondi", "Dal classico al jazz, aggiungili con un tocco."),
        "chords": ("Ogni accordo\nin un colpo d'occhio", "Una griglia di accordi chiara che segue la musica."),
        "plans": ("Gratis da provare.\nFacile da amare.", "Performer o Professional, settimanale o annuale. Inizia con 3 giorni gratis."),
    },
}

CJK = {"zh", "ja"}
NAMES = {"en": "English", "fr": "French", "de": "German", "es": "Spanish", "zh": "Chinese (Simplified)", "ja": "Japanese", "sv": "Swedish", "pt": "Portuguese", "it": "Italian"}
SONGTI, HEITI, UNI = "/System/Library/Fonts/Supplemental/Songti.ttc", "/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"


def fonts(lang, hsize, ssize):
    if lang == "zh":
        return ImageFont.truetype(SONGTI, hsize, index=1), ImageFont.truetype(HEITI, ssize, index=1)
    if lang == "ja":
        return ImageFont.truetype(UNI, hsize), ImageFont.truetype(UNI, ssize)
    return base.font(base.BODONI, hsize, 1), base.font(base.SANS, ssize)


def wrap(d, text, f, maxw, cjk):
    out = []
    for para in text.split("\n"):
        if cjk:
            cur = ""
            for ch in para:
                if d.textlength(cur + ch, font=f) > maxw and cur and ch not in "。、，．）」』！？：；":
                    out.append(cur); cur = ch
                else:
                    cur += ch
            out.append(cur)
        else:
            out += base.wrap(d, para, f, maxw)
    return out


def background(W, H):
    c = base.background(W, H).convert("RGBA")
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W * 0.05, H * 0.28, W * 0.95, H * 1.05), fill=(86, 54, 20))
    glow = glow.filter(ImageFilter.GaussianBlur(W // 6))
    return ImageChops.add(c.convert("RGB"), glow).convert("RGBA")


def slide(size, shot, key, lang, kind, mac=False):
    """kind: 'wide' (text above a landscape device) or 'tall' (text above a portrait device bleeding off the bottom)."""
    W, H = size
    head, sub = T[lang][key]
    c = background(W, H)
    d = ImageDraw.Draw(c)
    cj = lang in CJK
    if kind == "side":  # words on the left, a portrait card on the right
        dh = round(H * 0.88)
        dev = base.device(shot, round(dh * shot.width / shot.height), 10, round(W * 0.02))
        x = W - (dev[0].width - 2 * dev[1]) - round(W * 0.08)
        base.put(c, dev, x, (H - (dev[0].height - 2 * dev[1])) // 2)
        fh, fs = fonts(lang, round(W * 0.052 * (0.92 if cj else 1)), round(W * 0.0225))
        maxw = x - round(W * 0.14)
        y = H * 0.30
        for ln in wrap(d, head, fh, maxw, cj):
            d.text((W * 0.07, y), ln, font=fh, fill=CREAM); y += fh.size * 1.14
        y += fh.size * 0.2
        for ln in wrap(d, sub, fs, maxw, cj):
            d.text((W * 0.07, y), ln, font=fs, fill=AMBER); y += fs.size * 1.4
        return c.convert("RGB")
    hs = round(W * (0.050 if kind == "wide" else 0.086)) * (0.92 if cj else 1)
    ss = round(W * (0.0215 if kind == "wide" else 0.036))
    fh, fs = fonts(lang, round(hs), ss)
    maxw = W * (0.9 if kind == "wide" else 0.88)
    y = H * (0.05 if kind == "wide" else 0.055)
    for ln in wrap(d, head, fh, maxw, cj):
        d.text(((W - d.textlength(ln, font=fh)) / 2, y), ln, font=fh, fill=CREAM)
        y += fh.size * 1.14
    y += fh.size * 0.12
    for ln in wrap(d, sub, fs, maxw * (0.92 if kind == "wide" else 0.96), cj):
        d.text(((W - d.textlength(ln, font=fs)) / 2, y), ln, font=fs, fill=AMBER)
        y += fs.size * 1.38
    top = y + H * 0.03
    if kind == "wide":
        avail = H - top - H * 0.04 - (W * 0.03 if mac else 0)
        dw = min(round(W * 0.88), round((avail - (0 if mac else 2 * W * 0.011)) * shot.width / shot.height))
        dev = base.device(shot, dw, round(W * 0.011), round(W * 0.03), mac)
        base.put(c, dev, (W - (dev[0].width - 2 * dev[1])) // 2, round(H - (dev[0].height - 2 * dev[1]) - H * 0.04))
    else:
        dw = round(W * 0.84)
        dev = base.device(shot, dw, round(W * 0.016), round(W * 0.075))
        base.put(c, dev, (W - (dev[0].width - 2 * dev[1])) // 2, round(top))
    return c.convert("RGB")


# Banner text: (header tagline, search-banner tagline, three lines).
BANNER = {
    "en": ("Sheet music that plays along.", "Read it. Hear it. Play it.", ["Scores, lyrics and backing tracks", "Loop, slow down and change key", "For iPad, Mac and iPhone"]),
    "fr": ("La partition qui vous suit.", "Lisez-la. Écoutez-la. Jouez-la.", ["Partitions, paroles et accompagnements", "Bouclez, ralentissez, changez de ton", "Pour iPad, Mac et iPhone"]),
    "de": ("Noten, die mitspielen.", "Lesen. Hören. Spielen.", ["Partituren, Songtexte und Playbacks", "Wiederholen, verlangsamen, Tonart ändern", "Für iPad, Mac und iPhone"]),
    "es": ("Partituras que tocan contigo.", "Léela. Escúchala. Tócala.", ["Partituras, letras y pistas de acompañamiento", "Repite, ralentiza y cambia de tono", "Para iPad, Mac y iPhone"]),
    "zh": ("会跟着你演奏的乐谱。", "看谱。听音。演奏。", ["乐谱、歌词和伴奏", "循环、变速、变调", "适用于 iPad、Mac 和 iPhone"]),
    "ja": ("一緒に演奏してくれる楽譜。", "読む。聴く。弾く。", ["楽譜、歌詞、伴奏トラック", "ループ、スロー再生、キー変更", "iPad、Mac、iPhone に対応"]),
    "sv": ("Noter som spelar med dig.", "Läs. Hör. Spela.", ["Noter, sångtexter och kompspår", "Loopa, sänk tempot och byt tonart", "För iPad, Mac och iPhone"]),
    "pt": ("Partituras que tocam consigo.", "Leia. Oiça. Toque.", ["Partituras, letras e acompanhamentos", "Repita, abrande e mude de tom", "Para iPad, Mac e iPhone"]),
    "it": ("Spartiti che suonano con te.", "Leggilo. Ascoltalo. Suonalo.", ["Spartiti, testi e basi", "Ripeti, rallenta e cambia tonalità", "Per iPad, Mac e iPhone"]),
}


def fit(lang, text, size, maxw, serif=False):
    """The largest font up to `size` that keeps the text within maxw."""
    d = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    while size > 20:
        f = fonts(lang, size, size)[0 if serif else 1]
        if d.textlength(text, font=f) <= maxw:
            return f
        size -= 4
    return f


def banner(kind, lang):
    W, H = 5244, 2950
    c = background(W, H)
    d = ImageDraw.Draw(c)
    icon = Image.open(base.ICON).convert("RGBA")
    isz = 520 if kind == "header" else 440
    c.alpha_composite(base.rounded(icon.resize((isz, isz), Image.LANCZOS), isz // 5), (330, 760 if kind == "header" else 880))
    x0, y = 330, (760 if kind == "header" else 880)
    d.text((x0 + isz + 90, y - 20), "Maestro Pro", font=base.font(base.BODONI, 330 if kind == "header" else 300, 1), fill=CREAM)
    head, search, lines = BANNER[lang]
    tag = head if kind == "header" else search
    d.text((x0 + isz + 98, y + 360), tag, font=fit(lang, tag, 128, 2000), fill=AMBER)
    for i, line in enumerate(lines):
        d.text((x0 + 8, 1620 + i * 130), line, font=fit(lang, line, 84, 2500), fill=MUTED)
    sh = {"header": [("nocturne", 1900, 330), ("home", 1700, 1500)], "search": [("practise", 2560, 620)]}[kind]
    for n, w, y2 in sh:
        dev = base.device(base.land(n), w, 38, 100)
        base.put(c, dev, W - (dev[0].width - 2 * dev[1]) - (250 if n != "home" else 600), y2)
    return c.convert("RGB")


def r2(name):
    return Image.open(os.path.join(RAW2, name + ".png")).convert("RGB")


def landscape(name):
    """A landscape capture taken sideways in a portrait simulator, turned upright (status bar on the right, as in raw/)."""
    im = r2(name).rotate(-90, expand=True)
    return im.crop((0, 0, 2672, im.height))


def macshot(name):
    im = r2(name).rotate(-90, expand=True).crop((0, 172, 2680, 1892))
    s = 2880 / im.width
    im = im.resize((2880, round(im.height * s)), Image.LANCZOS)
    top = max(0, (im.height - 1800) // 2)
    return im.crop((0, top, 2880, top + 1800))


def sets():
    duo = lambda n: r2(n)
    return {
        "iPhone": ((1206, 2622), "tall", [("sheetP", r2("ph-sheet")), ("tunerP", r2("ph-tuner")), ("plansP", r2("ph-pw-year")), ("trialP", r2("ph-pw-week"))]),
        "iPhone Duo": ((1398, 2034), "tall", [("playD", duo("duo-play")), ("chordsD", duo("duo-chords")), ("libD", duo("duo-home")), ("plansD", duo("duo-pw-open"))]),
        "iPad": ((2732, 2048), "wide", [("play", base.land("nocturne")), ("lib", base.land("home")), ("lyrics", base.land("lyrics")), ("practise", base.land("practise")),
                                         ("edit", base.port("edit")), ("search", base.port("search")), ("chords", landscape("pad-chords")), ("plans", card("pad-pw-year"), "side")]),
        "Mac": ((2880, 1800), "wide", [("play", base.mac("mnoc")), ("libMac", base.mac("mhome")), ("lyrics", base.mac("mlyr")), ("practise", base.mac("mpractise")),
                                       ("chords", macshot("mac-chords")), ("plans", card("pad-pw-year"), "side")]),
    }


def card(name):
    """Just the paywall sheet of a portrait iPad capture, with its rounded corners."""
    im = r2(name).crop((458, 458, 1612, 2244))
    return base.rounded(im, 70).convert("RGBA").convert("RGB") if False else im


def paywalls():
    """The paywalls as the App Store Connect review screenshots want them: native, unframed."""
    out = os.path.join(ROOT, "Paywalls")
    for dev, files in {"iPhone": [("ph-pw-year", "1-performer-annual"), ("ph-pw-week", "2-professional-weekly-trial")],
                       "iPhone Duo (front screen)": [("duo-pw-front", "1-professional-weekly-trial")],
                       "iPhone Duo (opened)": [("duo-pw-open", "1-performer-annual")],
                       "iPad": [("pad-pw-year", "1-performer-annual"), ("pad-pw-week", "2-professional-weekly-trial")]}.items():
        os.makedirs(os.path.join(out, dev), exist_ok=True)
        for src, n in files:
            im = r2(src)
            if dev == "iPhone": im = im.resize((1206, 2622), Image.LANCZOS)   # a supported iPhone size
            im.save(os.path.join(out, dev, n + ".png"), optimize=True)
    os.makedirs(os.path.join(out, "Mac"), exist_ok=True)
    macshot("mac-pw").save(os.path.join(out, "Mac", "1-performer-annual.png"), optimize=True)


def main():
    langs = sys.argv[1:] or list(T)
    s = sets()
    paywalls()
    for lang in langs:
        for dev, (size, kind, items) in s.items():
            folder = os.path.join(ROOT, "Screenshots", NAMES[lang], dev)
            os.makedirs(folder, exist_ok=True)
            for i, (key, shot, *k) in enumerate(items, 1):
                slide(size, shot, key, lang, k[0] if k else kind, mac=dev == "Mac").save(os.path.join(folder, f"{i}-{key}.png"), optimize=True)
        folder = os.path.join(ROOT, "Screenshots", NAMES[lang], "Banners")
        os.makedirs(folder, exist_ok=True)
        banner("header", lang).save(os.path.join(folder, "Header-5244x2950.png"), optimize=True)
        banner("search", lang).save(os.path.join(folder, "SearchBanner-5244x2950.png"), optimize=True)
        print("done", lang)


if __name__ == "__main__":
    main()
