#!/usr/bin/env python3
"""Writes the App Store Connect text in each language to AppStore/Localised/<Language>.md and checks Apple's limits.
Run: python3 Tools/make-localised-text.py
"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AppStore", "Localised")
LIMITS = {"subtitle": 30, "promo": 170, "keywords": 100, "description": 4000, "iap_name": 30, "iap_desc": 45}

# Section order of the description.
ORDER = ["intro", "import", "search", "backing", "practise", "write", "together", "share", "teaching", "iphone", "privacy", "made"]

L = {}

L["en-GB"] = dict(
    name="English (U.K.)", app="Maestro Pro",
    subtitle="Sheet music that plays along",
    promo="Read it, hear it, play it. Notes light as they sound, lyrics move in time, and the page turns itself. Slow down, loop a bar, change key.",
    keywords="sheet music,musicxml,score,piano,practice,karaoke,lyrics,backing track,metronome,tuner,scales,midi",
    whatsnew="Welcome to Maestro Pro.",
    iap=[("Performer", "Everything except the score editor."), ("Professional", "Everything, including the editor."), ("Professional for Life", "Everything, once and for all.")],
    intro="Maestro Pro is sheet music that plays along with you.\n\nOpen a score and press play. Every note lights as it sounds, a soft wash marks the bar, and the page scrolls or curls over exactly when you need it. Slow a hard passage right down without changing the pitch, loop a few bars, count yourself in, switch on a metronome, or transpose the whole piece for your clarinet, trumpet or saxophone. The score is typeset again in the new key, not just relabelled.",
    **{"import": ("BRING YOUR OWN MUSIC", "Import PDF, MusicXML (.musicxml, .xml, .mxl), MIDI and karaoke (.mid, .kar) files, lyrics (.lrc, .txt) and CD+Graphics karaoke (.cdg). Import a whole folder at once. Keep your library on your device or in your own iCloud Drive so it is on all your devices.")},
    search=("SEARCH FOR SCORES", "Search Scores finds free scores from a built-in classical and jazz catalogue and from the wider web, so you can start playing in a minute."),
    backing=("BACKING TRACKS AND LYRICS", "Add a backing track, or play along with a song from your Apple Music subscription. Match its key and tempo, stack several tracks, and see the words scroll in time. Duets and group songs give each singer a colour, and the lyrics show a pause during a long break."),
    practise=("PRACTISE PROPERLY", ["Wait for Me: the score waits until you play the right note.", "A tuner and a steady-note trainer.", "Record yourself against the score and see every wrong note, late entry and bar to work on.", "Scales and arpeggios made on demand, in any key.", "Mark up the page with Apple Pencil. Your ink is included when you export a PDF."]),
    write=("WRITE AND EDIT", "Fix a wrong note, add a harmony or write something new. Touch a note and slide it up or down, scribble over it to rub it out, tap a length to change it. The editor keeps beams, ties and bar lengths tidy for you. Every save is a version you can return to: try an idea on a branch, merge it back bar by bar, and push the whole history to your own GitHub repository."),
    together=("PLAY TOGETHER", "Connect up to eight devices so everyone plays in perfect time, each from their own part, in their own key and on their own instrument."),
    share=("SHARE AND PRINT", "Export MusicXML or PDF, print, make a video of the music following along, or send a Maestro Pro file to another player."),
    teaching=("MADE FOR TEACHING", "A patient practice partner for students, and a quicker way for tutors to prepare parts and run an ensemble."),
    iphone=("ON IPHONE", "On iPhone, Maestro Pro is a viewer for the scores you add on your iPad or Mac, with a tuner and hands-free autoscroll. The full app runs on iPad, Mac and an opened iPhone Duo. Free lets you view the sheet music of up to 3 scores."),
    privacy=("PRIVACY", "No accounts and no adverts. Your scores and recordings stay on your device and in your own iCloud. Anonymous, privacy-friendly usage counts help improve the app, and the app uses the internet otherwise only when you ask it to."),
    made="Maestro Pro was made by Toby Jones in England.",
)

L["fr-FR"] = dict(
    name="Français (France)", app="Maestro Pro",
    subtitle="La partition qui vous suit",
    promo="Lisez, écoutez, jouez. Les notes s'allument en sonnant, les paroles défilent en rythme et la page se tourne seule. Ralentissez, bouclez une mesure, changez de ton.",
    keywords="partition,musicxml,piano,entraînement,karaoké,paroles,accompagnement,métronome,accordeur,gammes,midi",
    whatsnew="Bienvenue dans Maestro Pro.",
    iap=[("Performer", "Tout, sauf l'éditeur de partitions."), ("Professional", "Tout, éditeur compris."), ("Professional à vie", "Tout, une fois pour toutes.")],
    intro="Maestro Pro, c'est la partition qui joue avec vous.\n\nOuvrez une partition et appuyez sur lecture. Chaque note s'allume en sonnant, un halo doux marque la mesure et la page défile ou se tourne exactement quand il le faut. Ralentissez un passage difficile sans changer la hauteur, bouclez quelques mesures, lancez un décompte, activez le métronome ou transposez toute l'œuvre pour votre clarinette, trompette ou saxophone. La partition est regravée dans la nouvelle tonalité, pas simplement rebaptisée.",
    **{"import": ("APPORTEZ VOTRE MUSIQUE", "Importez des fichiers PDF, MusicXML (.musicxml, .xml, .mxl), MIDI et karaoké (.mid, .kar), des paroles (.lrc, .txt) et du karaoké CD+Graphics (.cdg). Importez un dossier entier d'un coup. Gardez votre bibliothèque sur votre appareil ou dans votre propre iCloud Drive pour la retrouver partout.")},
    search=("TROUVEZ DES PARTITIONS", "Rechercher des partitions trouve des partitions gratuites dans un catalogue intégré de classique et de jazz ainsi que sur le web, pour jouer en une minute."),
    backing=("ACCOMPAGNEMENTS ET PAROLES", "Ajoutez un accompagnement ou jouez avec un morceau de votre abonnement Apple Music. Réglez tonalité et tempo, superposez plusieurs pistes et voyez les paroles défiler en rythme. Les duos et chansons de groupe donnent une couleur à chaque chanteur, et les paroles marquent une pause pendant une longue interruption."),
    practise=("TRAVAILLEZ COMME IL FAUT", ["Attends-moi : la partition attend que vous jouiez la bonne note.", "Un accordeur et un entraîneur de notes tenues.", "Enregistrez-vous sur la partition et repérez chaque fausse note, entrée tardive et mesure à retravailler.", "Gammes et arpèges à la demande, dans toutes les tonalités.", "Annotez la page à l'Apple Pencil. Votre encre est incluse à l'export PDF."]),
    write=("ÉCRIVEZ ET MODIFIEZ", "Corrigez une fausse note, ajoutez une harmonie ou écrivez du neuf. Touchez une note et faites-la glisser vers le haut ou le bas, griffonnez dessus pour l'effacer, touchez une durée pour la changer. L'éditeur garde barres, liaisons et durées de mesure en ordre. Chaque enregistrement est une version à laquelle revenir : testez une idée sur une branche, fusionnez-la mesure par mesure et poussez tout l'historique vers votre propre dépôt GitHub."),
    together=("JOUEZ ENSEMBLE", "Connectez jusqu'à huit appareils pour que tout le monde joue parfaitement en rythme, chacun sa partie, dans sa tonalité et avec son instrument."),
    share=("PARTAGEZ ET IMPRIMEZ", "Exportez en MusicXML ou PDF, imprimez, créez une vidéo de la musique qui défile, ou envoyez un fichier Maestro Pro à un autre musicien."),
    teaching=("CONÇU POUR ENSEIGNER", "Un partenaire d'entraînement patient pour les élèves, et un moyen plus rapide pour les professeurs de préparer les parties et de diriger un ensemble."),
    iphone=("SUR IPHONE", "Sur iPhone, Maestro Pro sert à consulter les partitions ajoutées sur votre iPad ou Mac, avec un accordeur et un défilement automatique mains libres. L'app complète fonctionne sur iPad, Mac et iPhone Duo déplié. L'offre gratuite permet de consulter jusqu'à 3 partitions."),
    privacy=("CONFIDENTIALITÉ", "Aucun compte, aucune publicité. Vos partitions et enregistrements restent sur votre appareil et dans votre propre iCloud. Des statistiques d'usage anonymes, respectueuses de la vie privée, aident à améliorer l'app ; sinon, elle n'utilise Internet que si vous le demandez."),
    made="Maestro Pro a été créé par Toby Jones, en Angleterre.",
)

L["de-DE"] = dict(
    name="Deutsch", app="Maestro Pro",
    subtitle="Noten, die mitspielen",
    promo="Lesen, hören, spielen. Noten leuchten beim Klang, Texte laufen im Takt und die Seite blättert von selbst. Langsamer spielen, Takte wiederholen, Tonart wechseln.",
    keywords="Noten,Partitur,MusicXML,Klavier,Üben,Karaoke,Songtext,Playback,Metronom,Stimmgerät,Tonleitern,MIDI",
    whatsnew="Willkommen bei Maestro Pro.",
    iap=[("Performer", "Alles außer dem Partitureditor."), ("Professional", "Alles, inklusive Editor."), ("Professional für immer", "Alles, ein für alle Mal.")],
    intro="Maestro Pro sind Noten, die mit dir mitspielen.\n\nÖffne eine Partitur und drücke auf Play. Jede Note leuchtet, wenn sie erklingt, ein sanfter Schimmer markiert den Takt, und die Seite scrollt oder blättert genau dann, wenn du es brauchst. Spiele eine schwierige Passage ohne Tonhöhenänderung langsamer, wiederhole ein paar Takte, zähle dich ein, schalte das Metronom ein oder transponiere das ganze Stück für Klarinette, Trompete oder Saxofon. Die Partitur wird in der neuen Tonart neu gesetzt, nicht nur umbenannt.",
    **{"import": ("DEINE EIGENE MUSIK", "Importiere PDF-, MusicXML- (.musicxml, .xml, .mxl), MIDI- und Karaoke-Dateien (.mid, .kar), Texte (.lrc, .txt) und CD+Graphics-Karaoke (.cdg). Importiere einen ganzen Ordner auf einmal. Lege deine Bibliothek auf deinem Gerät oder in deinem eigenen iCloud Drive ab, damit sie auf all deinen Geräten verfügbar ist.")},
    search=("NOTEN SUCHEN", "Die Notensuche findet kostenlose Noten in einem integrierten Klassik- und Jazz-Katalog und im Web, damit du in einer Minute loslegen kannst."),
    backing=("PLAYBACKS UND SONGTEXTE", "Füge ein Playback hinzu oder spiele zu einem Song aus deinem Apple-Music-Abo. Passe Tonart und Tempo an, schichte mehrere Spuren und sieh den Text im Takt mitlaufen. Bei Duetten und Gruppensongs bekommt jeder Sänger eine Farbe, und bei längeren Pausen zeigt der Text eine Pause an."),
    practise=("RICHTIG ÜBEN", ["Warte auf mich: Die Partitur wartet, bis du den richtigen Ton spielst.", "Ein Stimmgerät und ein Trainer für gehaltene Töne.", "Nimm dich zur Partitur auf und sieh jeden falschen Ton, jeden späten Einsatz und jeden Takt, an dem du arbeiten solltest.", "Tonleitern und Arpeggien auf Abruf, in jeder Tonart.", "Markiere die Seite mit dem Apple Pencil. Deine Notizen sind beim PDF-Export dabei."]),
    write=("SCHREIBEN UND BEARBEITEN", "Korrigiere einen falschen Ton, füge eine Harmonie hinzu oder schreibe etwas Neues. Berühre eine Note und schiebe sie nach oben oder unten, kritzele darüber, um sie zu löschen, tippe auf eine Länge, um sie zu ändern. Der Editor hält Balken, Bindebögen und Taktlängen für dich in Ordnung. Jede Sicherung ist eine Version, zu der du zurückkehren kannst: Probiere eine Idee in einem Zweig aus, führe sie Takt für Takt wieder zusammen und übertrage den gesamten Verlauf in dein eigenes GitHub-Repository."),
    together=("GEMEINSAM SPIELEN", "Verbinde bis zu acht Geräte, damit alle im perfekten Takt spielen, jeder seine eigene Stimme, in seiner eigenen Tonart und auf seinem eigenen Instrument."),
    share=("TEILEN UND DRUCKEN", "Exportiere MusicXML oder PDF, drucke, erstelle ein Video der mitlaufenden Musik oder sende eine Maestro-Pro-Datei an andere Musiker."),
    teaching=("FÜR DEN UNTERRICHT GEMACHT", "Ein geduldiger Übungspartner für Schüler und ein schnellerer Weg für Lehrer, Stimmen vorzubereiten und ein Ensemble zu leiten."),
    iphone=("AUF DEM IPHONE", "Auf dem iPhone ist Maestro Pro ein Viewer für die Noten, die du auf iPad oder Mac hinzufügst, mit Stimmgerät und freihändigem Autoscroll. Die volle App läuft auf iPad, Mac und aufgeklapptem iPhone Duo. Kostenlos kannst du die Noten von bis zu 3 Partituren ansehen."),
    privacy=("DATENSCHUTZ", "Keine Konten, keine Werbung. Deine Partituren und Aufnahmen bleiben auf deinem Gerät und in deiner eigenen iCloud. Anonyme, datenschutzfreundliche Nutzungszahlen helfen, die App zu verbessern; ansonsten nutzt die App das Internet nur, wenn du es willst."),
    made="Maestro Pro wurde von Toby Jones in England entwickelt.",
)

L["es-ES"] = dict(
    name="Español (España)", app="Maestro Pro",
    subtitle="Partituras que tocan contigo",
    promo="Léela, escúchala, tócala. Las notas se iluminan al sonar, la letra avanza a tiempo y la página pasa sola. Ve más lento, repite un compás, cambia de tono.",
    keywords="partituras,musicxml,piano,práctica,karaoke,letras,pista,metrónomo,afinador,escalas,midi,pdf",
    whatsnew="Te damos la bienvenida a Maestro Pro.",
    iap=[("Performer", "Todo menos el editor de partituras."), ("Professional", "Todo, incluido el editor."), ("Professional de por vida", "Todo, de una vez para siempre.")],
    intro="Maestro Pro es una partitura que toca contigo.\n\nAbre una partitura y pulsa reproducir. Cada nota se ilumina al sonar, un suave resplandor marca el compás y la página se desplaza o pasa justo cuando la necesitas. Ralentiza un pasaje difícil sin cambiar el tono, repite unos compases, empieza con cuenta atrás, activa el metrónomo o transporta toda la pieza para tu clarinete, trompeta o saxofón. La partitura se vuelve a grabar en la nueva tonalidad, no solo se renombra.",
    **{"import": ("TRAE TU PROPIA MÚSICA", "Importa archivos PDF, MusicXML (.musicxml, .xml, .mxl), MIDI y karaoke (.mid, .kar), letras (.lrc, .txt) y karaoke CD+Graphics (.cdg). Importa una carpeta entera de una vez. Guarda tu biblioteca en tu dispositivo o en tu propio iCloud Drive para tenerla en todos tus dispositivos.")},
    search=("BUSCA PARTITURAS", "Buscar partituras encuentra partituras gratuitas en un catálogo integrado de música clásica y jazz y en toda la web, para que empieces a tocar en un minuto."),
    backing=("PISTAS Y LETRAS", "Añade una pista de acompañamiento o toca con una canción de tu suscripción a Apple Music. Ajusta tono y tempo, superpón varias pistas y mira cómo la letra avanza a tiempo. En dúos y canciones de grupo cada cantante tiene su color, y la letra muestra una pausa durante un largo silencio."),
    practise=("PRACTICA DE VERDAD", ["Espérame: la partitura espera hasta que toques la nota correcta.", "Un afinador y un entrenador de notas sostenidas.", "Grábate sobre la partitura y ve cada nota errónea, entrada tardía y compás en el que trabajar.", "Escalas y arpegios al instante, en cualquier tonalidad.", "Marca la página con el Apple Pencil. Tu tinta se incluye al exportar un PDF."]),
    write=("ESCRIBE Y EDITA", "Corrige una nota equivocada, añade una armonía o escribe algo nuevo. Toca una nota y deslízala arriba o abajo, tacha encima para borrarla, toca una duración para cambiarla. El editor mantiene ordenados los ligaduras, barras y la longitud de los compases. Cada guardado es una versión a la que puedes volver: prueba una idea en una rama, fusiónala compás a compás y envía todo el historial a tu propio repositorio de GitHub."),
    together=("TOCAD JUNTOS", "Conecta hasta ocho dispositivos para que todos toquen perfectamente a tiempo, cada uno con su parte, en su tonalidad y con su instrumento."),
    share=("COMPARTE E IMPRIME", "Exporta a MusicXML o PDF, imprime, crea un vídeo de la música siguiendo la partitura o envía un archivo de Maestro Pro a otro músico."),
    teaching=("PENSADA PARA ENSEÑAR", "Un compañero de práctica paciente para los alumnos y una forma más rápida para los profesores de preparar partes y dirigir un conjunto."),
    iphone=("EN IPHONE", "En iPhone, Maestro Pro es un visor de las partituras que añades en tu iPad o Mac, con afinador y desplazamiento automático con las manos libres. La app completa funciona en iPad, Mac y iPhone Duo desplegado. Con el plan gratuito puedes ver las partituras de hasta 3 obras."),
    privacy=("PRIVACIDAD", "Sin cuentas y sin anuncios. Tus partituras y grabaciones permanecen en tu dispositivo y en tu propio iCloud. Recuentos de uso anónimos y respetuosos con la privacidad ayudan a mejorar la app; por lo demás, la app solo usa internet cuando se lo pides."),
    made="Maestro Pro fue creada por Toby Jones en Inglaterra.",
)

L["zh-Hans"] = dict(
    name="简体中文", app="Maestro Pro",
    subtitle="会跟着你演奏的乐谱",
    promo="看谱、听音、演奏。音符随声音亮起，歌词随节拍滚动，页面自动翻动。放慢速度、循环小节、随时变调。",
    keywords="乐谱,五线谱,musicxml,钢琴,练习,卡拉OK,歌词,伴奏,节拍器,调音器,音阶,midi,pdf",
    whatsnew="欢迎使用 Maestro Pro。",
    iap=[("Performer", "除乐谱编辑器外的全部功能。"), ("Professional", "全部功能，含编辑器。"), ("Professional 终身版", "一次购买，永久拥有。")],
    intro="Maestro Pro 是会跟着你一起演奏的乐谱。\n\n打开乐谱，点击播放。每个音符随声音亮起，柔和的光带标出当前小节，页面会在你需要的时刻恰好滚动或翻页。把难的乐段放慢而不改变音高，循环几个小节，先数拍再开始，打开节拍器，或把整首曲子移调给单簧管、小号或萨克斯。乐谱会按新调重新排版，而不只是改个标签。",
    **{"import": ("导入你自己的音乐", "导入 PDF、MusicXML（.musicxml、.xml、.mxl）、MIDI 和卡拉 OK（.mid、.kar）文件、歌词（.lrc、.txt）以及 CD+Graphics 卡拉 OK（.cdg）。可一次导入整个文件夹。把乐谱库保存在设备上，或存入你自己的 iCloud 云盘，所有设备都能使用。")},
    search=("搜索乐谱", "“搜索乐谱”可从内置的古典与爵士曲库以及更广泛的网络中找到免费乐谱，让你一分钟内开始演奏。"),
    backing=("伴奏与歌词", "添加伴奏音轨，或跟着 Apple Music 订阅中的歌曲演奏。匹配调性与速度，叠加多条音轨，并看着歌词随节拍滚动。二重唱和合唱歌曲会为每位歌手分配一种颜色，长时间间奏时歌词会显示停顿。"),
    practise=("认真练习", ["等我：乐谱会等你弹对音符再继续。", "调音器和长音练习器。", "对着乐谱录音，查看每个错音、迟到的进入和需要加强的小节。", "随时生成任意调的音阶和琶音。", "用 Apple Pencil 在页面上做标记，导出 PDF 时笔迹也会包含在内。"]),
    write=("写谱与编辑", "改正错音、添加和声或写下新作品。触摸音符上下滑动，在上面涂抹即可擦除，轻点时值即可更改。编辑器会替你保持符杆、连音线和小节长度整齐。每次存储都是一个可以返回的版本：在分支上尝试想法，逐小节合并回来，并把完整历史推送到你自己的 GitHub 仓库。"),
    together=("一起演奏", "最多连接八台设备，让每个人都严丝合缝地同步演奏，各自使用自己的声部、调性和乐器。"),
    share=("分享与打印", "导出 MusicXML 或 PDF、打印、制作音乐跟随播放的视频，或把 Maestro Pro 文件发给其他演奏者。"),
    teaching=("为教学而生", "学生有耐心的练习伙伴，教师也能更快准备分谱、带领合奏。"),
    iphone=("在 iPhone 上", "在 iPhone 上，Maestro Pro 是查看你在 iPad 或 Mac 上添加的乐谱的阅读器，带调音器和免手动自动滚动。完整应用可在 iPad、Mac 和展开的 iPhone Duo 上使用。免费版可查看最多 3 份乐谱。"),
    privacy=("隐私", "无需账户，没有广告。你的乐谱和录音只保存在你的设备和你自己的 iCloud 中。匿名、保护隐私的使用统计帮助我们改进应用，除此之外，应用只会在你要求时联网。"),
    made="Maestro Pro 由英格兰的 Toby Jones 制作。",
)

L["ja"] = dict(
    name="日本語", app="Maestro Pro",
    subtitle="一緒に演奏してくれる楽譜",
    promo="読んで、聴いて、弾く。音に合わせて音符が光り、歌詞は拍に合わせて流れ、ページは自動でめくれます。テンポを落とし、小節をループし、キーも変更。",
    keywords="楽譜,スコア,musicxml,ピアノ,練習,カラオケ,歌詞,伴奏,メトロノーム,チューナー,スケール,midi,pdf",
    whatsnew="Maestro Pro へようこそ。",
    iap=[("Performer", "楽譜エディタ以外のすべて。"), ("Professional", "エディタを含むすべて。"), ("Professional 買い切り", "一度の購入ですべてを。")],
    intro="Maestro Pro は、あなたと一緒に演奏してくれる楽譜です。\n\n楽譜を開いて再生を押すだけ。音が鳴るたびに音符が光り、やわらかな光が小節を示し、ページは必要なタイミングでスクロールまたはめくれます。難しい箇所は音程を変えずにゆっくりに、数小節をループ、カウントイン、メトロノーム、クラリネットやトランペット、サックス向けに曲全体を移調。楽譜は新しいキーで組み直されます。",
    **{"import": ("自分の音楽を持ち込む", "PDF、MusicXML（.musicxml、.xml、.mxl）、MIDI・カラオケ（.mid、.kar）ファイル、歌詞（.lrc、.txt）、CD+G カラオケ（.cdg）を読み込めます。フォルダごとまとめて読み込みも可能。ライブラリはデバイス内、またはご自身の iCloud Drive に保存して、すべてのデバイスで使えます。")},
    search=("楽譜を探す", "「楽譜を検索」では、内蔵のクラシックとジャズのカタログやウェブ全体から無料の楽譜を探せるので、すぐに演奏を始められます。"),
    backing=("伴奏と歌詞", "伴奏トラックを追加したり、Apple Music の曲に合わせて演奏したり。キーとテンポを合わせ、複数のトラックを重ね、歌詞が拍に合わせて流れるのを見られます。デュエットやグループの曲では歌い手ごとに色分けされ、長い間奏では歌詞が一時停止を示します。"),
    practise=("しっかり練習", ["待っていてね：正しい音を弾くまで楽譜が待ちます。", "チューナーと音の安定トレーナー。", "楽譜に合わせて録音し、間違った音、遅れた入り、練習すべき小節を確認。", "どのキーでも、スケールとアルペジオをその場で作成。", "Apple Pencil でページに書き込み。PDF の書き出し時にも反映されます。"]),
    write=("書いて、編集する", "間違った音を直し、ハーモニーを足し、新しい曲を書けます。音符に触れて上下にスライド、なぞって消去、音価をタップして変更。連桁、タイ、小節の長さはエディタが整えます。保存のたびに戻れるバージョンが残り、ブランチでアイデアを試し、小節ごとに統合し、履歴全体をご自身の GitHub リポジトリへプッシュできます。"),
    together=("一緒に演奏", "最大 8 台のデバイスをつないで、全員がぴったり同じタイミングで演奏。それぞれのパート、キー、楽器で参加できます。"),
    share=("共有と印刷", "MusicXML や PDF の書き出し、印刷、音楽に合わせて動く動画の作成、Maestro Pro ファイルを他の演奏者に送ることができます。"),
    teaching=("レッスンにも", "生徒には辛抱強い練習パートナー、先生にはパート準備やアンサンブル運営の近道に。"),
    iphone=("iPhone では", "iPhone の Maestro Pro は、iPad や Mac で追加した楽譜を表示するビューアで、チューナーとハンズフリーの自動スクロールが使えます。フル機能のアプリは iPad、Mac、開いた iPhone Duo で動作します。無料プランでは最大 3 曲の楽譜を表示できます。"),
    privacy=("プライバシー", "アカウント不要、広告なし。楽譜と録音はデバイス内とご自身の iCloud にのみ保存されます。アプリ改善のため、匿名でプライバシーに配慮した利用回数を集計しますが、それ以外でインターネットを使うのはご自身が操作したときだけです。"),
    made="Maestro Pro はイギリスの Toby Jones が作りました。",
)

L["sv"] = dict(
    name="Svenska", app="Maestro Pro",
    subtitle="Noter som spelar med dig",
    promo="Läs den, hör den, spela den. Toner lyser när de klingar, texten rullar i takt och sidan bläddrar sig själv. Sänk tempot, loopa ett taktslag, byt tonart.",
    keywords="noter,partitur,musicxml,piano,övning,karaoke,sångtext,kompspår,metronom,stämapparat,skalor,midi,pdf",
    whatsnew="Välkommen till Maestro Pro.",
    iap=[("Performer", "Allt utom partitureditorn."), ("Professional", "Allt, inklusive editorn."), ("Professional för alltid", "Allt, en gång för alla.")],
    intro="Maestro Pro är noter som spelar med dig.\n\nÖppna en partitur och tryck på play. Varje ton lyser upp när den klingar, ett mjukt sken markerar takten, och sidan rullar eller bläddras precis när du behöver det. Sänk tempot på ett svårt parti utan att ändra tonhöjden, loopa några takter, räkna in dig, slå på metronomen eller transponera hela stycket för din klarinett, trumpet eller saxofon. Noterna sätts om i den nya tonarten, de döps inte bara om.",
    **{"import": ("TA MED DIN EGEN MUSIK", "Importera PDF-, MusicXML- (.musicxml, .xml, .mxl), MIDI- och karaokefiler (.mid, .kar), sångtexter (.lrc, .txt) och CD+Graphics-karaoke (.cdg). Importera en hel mapp på en gång. Behåll ditt bibliotek på enheten eller i din egen iCloud Drive så finns det på alla dina enheter.")},
    search=("SÖK EFTER NOTER", "Sök noter hittar gratis noter i en inbyggd katalog med klassiskt och jazz och på webben, så att du kan börja spela inom en minut."),
    backing=("KOMPSPÅR OCH SÅNGTEXTER", "Lägg till ett kompspår eller spela med en låt från din Apple Music-prenumeration. Anpassa tonart och tempo, lägg flera spår på varandra och se texten rulla i takt. I duetter och gruppsånger får varje sångare en färg, och texten visar en paus under ett långt avbrott."),
    practise=("ÖVA PÅ RIKTIGT", ["Vänta på mig: noterna väntar tills du spelar rätt ton.", "En stämapparat och en tränare för stadiga toner.", "Spela in dig mot noterna och se varje fel ton, sen ingång och takt att jobba på.", "Skalor och arpeggion på begäran, i vilken tonart som helst.", "Markera sidan med Apple Pencil. Ditt bläck följer med när du exporterar en PDF."]),
    write=("SKRIV OCH REDIGERA", "Rätta en fel ton, lägg till en harmoni eller skriv något nytt. Rör vid en not och dra den upp eller ned, klottra över den för att radera, tryck på en längd för att ändra den. Editorn håller balkar, bindebågar och taktlängder i ordning åt dig. Varje sparning är en version du kan gå tillbaka till: testa en idé på en gren, slå ihop den takt för takt och skicka hela historiken till ditt eget GitHub-arkiv."),
    together=("SPELA TILLSAMMANS", "Anslut upp till åtta enheter så att alla spelar exakt i takt, var och en från sin egen stämma, i sin egen tonart och på sitt eget instrument."),
    share=("DELA OCH SKRIV UT", "Exportera MusicXML eller PDF, skriv ut, gör en video där musiken följer med eller skicka en Maestro Pro-fil till en annan spelare."),
    teaching=("GJORD FÖR UNDERVISNING", "En tålmodig övningspartner för elever och ett snabbare sätt för lärare att förbereda stämmor och leda en ensemble."),
    iphone=("PÅ IPHONE", "På iPhone är Maestro Pro en läsare för noterna du lägger till på din iPad eller Mac, med stämapparat och handsfree-autoscroll. Hela appen körs på iPad, Mac och en uppfälld iPhone Duo. Gratis låter dig se noterna för upp till 3 partitur."),
    privacy=("INTEGRITET", "Inga konton och inga annonser. Dina noter och inspelningar stannar på din enhet och i din egen iCloud. Anonyma, integritetsvänliga användningsmätningar hjälper oss förbättra appen, och i övrigt använder appen bara internet när du ber den om det."),
    made="Maestro Pro skapades av Toby Jones i England.",
)

L["pt-PT"] = dict(
    name="Português (Portugal)", app="Maestro Pro",
    subtitle="Partituras que tocam consigo",
    promo="Leia, oiça, toque. As notas acendem ao soar, a letra avança a tempo e a página vira sozinha. Abrande, repita um compasso, mude de tom.",
    keywords="partituras,musicxml,piano,prática,karaoke,letras,acompanhamento,metrónomo,afinador,escalas,midi,pdf",
    whatsnew="Bem-vindo ao Maestro Pro.",
    iap=[("Performer", "Tudo, exceto o editor de partituras."), ("Professional", "Tudo, incluindo o editor."), ("Professional vitalício", "Tudo, de uma vez por todas.")],
    intro="O Maestro Pro é a partitura que toca consigo.\n\nAbra uma partitura e carregue em reproduzir. Cada nota acende ao soar, um brilho suave marca o compasso e a página desloca-se ou vira exatamente quando precisa. Abrande uma passagem difícil sem alterar o tom, repita alguns compassos, comece com contagem, ative o metrónomo ou transponha a peça toda para o seu clarinete, trompete ou saxofone. A partitura é composta de novo no novo tom, não apenas renomeada.",
    **{"import": ("TRAGA A SUA MÚSICA", "Importe ficheiros PDF, MusicXML (.musicxml, .xml, .mxl), MIDI e karaoke (.mid, .kar), letras (.lrc, .txt) e karaoke CD+Graphics (.cdg). Importe uma pasta inteira de uma vez. Mantenha a biblioteca no dispositivo ou no seu próprio iCloud Drive para a ter em todos os dispositivos.")},
    search=("PROCURE PARTITURAS", "A pesquisa de partituras encontra partituras gratuitas num catálogo integrado de música clássica e jazz e na web, para começar a tocar num minuto."),
    backing=("ACOMPANHAMENTOS E LETRAS", "Adicione um acompanhamento ou toque com uma canção da sua subscrição do Apple Music. Ajuste o tom e o andamento, sobreponha várias faixas e veja a letra avançar a tempo. Em duetos e canções de grupo cada cantor tem uma cor, e a letra mostra uma pausa durante um intervalo longo."),
    practise=("PRATIQUE A SÉRIO", ["Espera por mim: a partitura espera até tocar a nota certa.", "Um afinador e um treinador de notas sustentadas.", "Grave-se sobre a partitura e veja cada nota errada, entrada tardia e compasso a trabalhar.", "Escalas e arpejos a pedido, em qualquer tom.", "Anote a página com o Apple Pencil. A sua tinta é incluída ao exportar um PDF."]),
    write=("ESCREVA E EDITE", "Corrija uma nota errada, acrescente uma harmonia ou escreva algo novo. Toque numa nota e deslize-a para cima ou para baixo, risque por cima para apagar, toque numa duração para a mudar. O editor mantém as barras, ligaduras e durações dos compassos em ordem. Cada gravação é uma versão a que pode voltar: experimente uma ideia num ramo, junte-a compasso a compasso e envie todo o histórico para o seu próprio repositório do GitHub."),
    together=("TOQUEM JUNTOS", "Ligue até oito dispositivos para que todos toquem em perfeito tempo, cada um com a sua parte, no seu tom e com o seu instrumento."),
    share=("PARTILHE E IMPRIMA", "Exporte para MusicXML ou PDF, imprima, crie um vídeo da música a acompanhar ou envie um ficheiro do Maestro Pro a outro músico."),
    teaching=("FEITO PARA ENSINAR", "Um parceiro de prática paciente para os alunos e uma forma mais rápida de os professores prepararem partes e dirigirem um conjunto."),
    iphone=("NO IPHONE", "No iPhone, o Maestro Pro é um leitor das partituras que adiciona no iPad ou Mac, com afinador e deslocação automática de mãos livres. A app completa funciona no iPad, no Mac e num iPhone Duo aberto. O plano gratuito permite ver as partituras de até 3 obras."),
    privacy=("PRIVACIDADE", "Sem contas e sem anúncios. As suas partituras e gravações ficam no seu dispositivo e no seu próprio iCloud. Contagens de utilização anónimas e respeitadoras da privacidade ajudam a melhorar a app; de resto, a app só usa a internet quando lho pede."),
    made="O Maestro Pro foi criado por Toby Jones em Inglaterra.",
)

L["it"] = dict(
    name="Italiano", app="Maestro Pro",
    subtitle="Spartiti che suonano con te",
    promo="Leggilo, ascoltalo, suonalo. Le note si accendono mentre suonano, i testi scorrono a tempo e la pagina si gira da sola. Rallenta, ripeti una battuta, cambia tonalità.",
    keywords="spartiti,musicxml,pianoforte,esercizio,karaoke,testi,base,metronomo,accordatore,scale,midi,pdf",
    whatsnew="Benvenuto in Maestro Pro.",
    iap=[("Performer", "Tutto tranne l'editor di spartiti."), ("Professional", "Tutto, editor incluso."), ("Professional a vita", "Tutto, una volta per sempre.")],
    intro="Maestro Pro è lo spartito che suona con te.\n\nApri uno spartito e premi play. Ogni nota si accende mentre suona, un morbido bagliore segna la battuta e la pagina scorre o si gira esattamente quando serve. Rallenta un passaggio difficile senza cambiare l'intonazione, ripeti qualche battuta, parti con il conteggio, attiva il metronomo o trasporta l'intero brano per il tuo clarinetto, tromba o sassofono. Lo spartito viene reimpaginato nella nuova tonalità, non solo rinominato.",
    **{"import": ("PORTA LA TUA MUSICA", "Importa file PDF, MusicXML (.musicxml, .xml, .mxl), MIDI e karaoke (.mid, .kar), testi (.lrc, .txt) e karaoke CD+Graphics (.cdg). Importa un'intera cartella in un colpo solo. Tieni la libreria sul dispositivo o nel tuo iCloud Drive per averla su tutti i tuoi dispositivi.")},
    search=("CERCA SPARTITI", "Cerca spartiti trova spartiti gratuiti in un catalogo integrato di musica classica e jazz e sul web, così puoi iniziare a suonare in un minuto."),
    backing=("BASI E TESTI", "Aggiungi una base o suona con un brano del tuo abbonamento Apple Music. Adatta tonalità e tempo, sovrapponi più tracce e guarda i testi scorrere a tempo. Nei duetti e nei brani di gruppo ogni cantante ha un colore, e i testi mostrano una pausa durante un lungo intermezzo."),
    practise=("ESERCITATI DAVVERO", ["Aspettami: lo spartito attende finché non suoni la nota giusta.", "Un accordatore e un allenatore di note tenute.", "Registrati sullo spartito e vedi ogni nota sbagliata, ingresso in ritardo e battuta su cui lavorare.", "Scale e arpeggi su richiesta, in qualsiasi tonalità.", "Annota la pagina con Apple Pencil. Il tuo inchiostro è incluso quando esporti un PDF."]),
    write=("SCRIVI E MODIFICA", "Correggi una nota sbagliata, aggiungi un'armonia o scrivi qualcosa di nuovo. Tocca una nota e trascinala su o giù, scarabocchia sopra per cancellarla, tocca una durata per cambiarla. L'editor tiene in ordine travi, legature e lunghezze delle battute. Ogni salvataggio è una versione a cui tornare: prova un'idea su un ramo, uniscila battuta per battuta e invia l'intera cronologia al tuo repository GitHub."),
    together=("SUONATE INSIEME", "Collega fino a otto dispositivi in modo che tutti suonino perfettamente a tempo, ciascuno con la propria parte, nella propria tonalità e con il proprio strumento."),
    share=("CONDIVIDI E STAMPA", "Esporta in MusicXML o PDF, stampa, crea un video della musica che scorre o invia un file di Maestro Pro a un altro musicista."),
    teaching=("PENSATO PER INSEGNARE", "Un paziente compagno di studio per gli studenti e un modo più rapido per gli insegnanti di preparare le parti e guidare un ensemble."),
    iphone=("SU IPHONE", "Su iPhone, Maestro Pro è un visualizzatore degli spartiti che aggiungi su iPad o Mac, con accordatore e scorrimento automatico a mani libere. L'app completa funziona su iPad, Mac e iPhone Duo aperto. Con il piano gratuito puoi vedere gli spartiti di un massimo di 3 brani."),
    privacy=("PRIVACY", "Nessun account e nessuna pubblicità. I tuoi spartiti e le tue registrazioni restano sul tuo dispositivo e nel tuo iCloud. Conteggi d'uso anonimi e rispettosi della privacy aiutano a migliorare l'app; per il resto, l'app usa internet solo quando glielo chiedi."),
    made="Maestro Pro è stato creato da Toby Jones in Inghilterra.",
)


def build(code, d):
    bullets = "\n".join("- " + b for b in d["practise"][1])
    parts = [d["intro"]]
    for k in ORDER[1:-1]:
        h, b = d[k]
        parts.append(f"{h}\n" + (bullets if k == "practise" else b))
    parts.append(d["made"])
    description = "\n\n".join(parts)
    checks = {"subtitle": d["subtitle"], "promo": d["promo"], "keywords": d["keywords"], "description": description}
    for k, v in checks.items():
        assert len(v) <= LIMITS[k], f"{code} {k}: {len(v)} > {LIMITS[k]}"
    for n, desc in d["iap"]:
        assert len(n) <= LIMITS["iap_name"] and len(desc) <= LIMITS["iap_desc"], f"{code} iap {n}"
    iap = "\n".join(f"- **{n}**: {desc}" for n, desc in d["iap"])
    return f"""# Maestro Pro: {d['name']} ({code})

Paste each block into the matching field for this localisation in App Store Connect.

## Name (30)

{d['app']}

## Subtitle (30)

{d['subtitle']}

## Promotional text (170)

{d['promo']}

## Description (4000)

{description}

## Keywords (100)

{d['keywords']}

## What's New

{d['whatsnew']}

## In-app purchase display names and descriptions (name 30, description 45)

{iap}
"""


FILES = {"en-GB": "English", "fr-FR": "French", "de-DE": "German", "es-ES": "Spanish", "zh-Hans": "Chinese (Simplified)", "ja": "Japanese", "sv": "Swedish", "pt-PT": "Portuguese", "it": "Italian"}


def main():
    os.makedirs(ROOT, exist_ok=True)
    for code, d in L.items():
        open(os.path.join(ROOT, FILES[code] + ".md"), "w").write(build(code, d))
        print(code, "ok")


if __name__ == "__main__":
    main()
