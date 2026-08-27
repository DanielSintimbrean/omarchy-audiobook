import QtQuick
import Quickshell
import Quickshell.Io
import "Library.js" as Library

// Headless singleton: owns the mpv process, its JSON IPC socket, the library
// scan and the persisted state. Bar widgets (one per monitor) and the panel
// only read from and call into this object.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
  readonly property string socketPath: runtimeDir + "/omarchy-audiobook.sock"
  readonly property string stateDir: home + "/.local/share/omarchy-audiobook"
  readonly property string statePath: stateDir + "/state.json"

  // ------------------------------------------------------------- library
  property string libraryDir: "~/Audiobooks"
  readonly property string libraryPath: Library.expandHome(libraryDir, home)
  property var books: []
  property bool scanning: false
  property bool scanned: false
  property bool rescanPending: false

  // ----------------------------------------------------------- persisted
  property var positions: ({})      // book path -> { pos, duration, updated }
  property string lastBookPath: ""
  property real speed: 1.0
  property bool stateLoaded: false
  property bool restored: false

  // -------------------------------------------------------------- player
  property var book: null
  readonly property bool hasBook: book !== null
  readonly property string bookPath: book ? book.path : ""
  readonly property string title: book ? book.name : ""
  property string author: ""
  property bool connected: false
  property bool loaded: false
  property bool paused: true
  readonly property bool playing: hasBook && loaded && !paused
  property real position: 0
  property real duration: 0
  readonly property real percent: duration > 0 ? Math.max(0, Math.min(100, position / duration * 100)) : 0
  property int chapterIndex: -1
  property var chapters: []
  property bool eofReached: false
  readonly property var currentChapter: chapterIndex >= 0 && chapterIndex < chapters.length ? chapters[chapterIndex] : null
  readonly property string chapterTitle: currentChapter ? String(currentChapter.title || ("Chapter " + (chapterIndex + 1))) : ""
  // Bounds of the current chapter in absolute book seconds; the whole book
  // when the file has no chapters. The seek bar and time labels span these.
  readonly property real chapterStart: currentChapter ? (Number(currentChapter.time) || 0) : 0
  readonly property real chapterEndTime: currentChapter ? chapterEnd(chapterIndex) : duration

  property real pendingSeek: -1
  property bool pendingPlay: false
  property int requestSerial: 0
  property bool quitting: false
  property int mpvRestarts: 0

  readonly property real minSpeed: 0.75
  readonly property real maxSpeed: 2.0
  readonly property real speedStepSize: 0.25
  readonly property real skipSeconds: 30

  // ----------------------------------------------------------------- mpv
  function send(cmd) {
    if (!ipc.connected) return
    requestSerial++
    ipc.write(JSON.stringify({ command: cmd, request_id: requestSerial }) + "\n")
    ipc.flush()
  }

  function setProp(name, value) {
    send(["set_property", name, value])
  }

  readonly property var observedProps: ["pause", "time-pos", "duration", "chapter", "chapter-list", "speed", "eof-reached", "metadata"]

  function observeAll() {
    for (var i = 0; i < observedProps.length; i++) send(["observe_property", i + 1, observedProps[i]])
  }

  function handleLine(line) {
    var text = String(line || "").trim()
    if (!text) return
    var msg
    try { msg = JSON.parse(text) } catch (e) { return }
    if (!msg || typeof msg !== "object") return
    if (msg.event === "property-change") onProp(String(msg.name), msg.data)
    else if (msg.event === "file-loaded") onFileLoaded()
    else if (msg.event === "end-file" && msg.reason === "error") {
      console.warn("audiobook: mpv failed to load", bookPath, msg.file_error || "")
      loaded = false
    } else if (msg.error && msg.error !== "success") {
      console.warn("audiobook: mpv command failed:", msg.error)
    }
  }

  function onProp(name, data) {
    if (name === "pause") {
      var p = data !== false
      if (paused !== p) {
        paused = p
        if (p && loaded) saveNow()
      }
    } else if (name === "time-pos") {
      if (loaded && typeof data === "number" && isFinite(data)) position = data
    } else if (name === "duration") {
      if (typeof data === "number" && isFinite(data) && data > 0) duration = data
    } else if (name === "chapter") {
      chapterIndex = typeof data === "number" ? data : -1
    } else if (name === "chapter-list") {
      chapters = Array.isArray(data) ? data : []
    } else if (name === "speed") {
      // mpv reports 1.0 before any file is loaded; the persisted value wins
      // until we have pushed it in onFileLoaded.
      if (loaded && typeof data === "number" && isFinite(data)) speed = data
    } else if (name === "eof-reached") {
      var eof = data === true
      if (eof !== eofReached) {
        eofReached = eof
        if (eof) saveNow()
      }
    } else if (name === "metadata") {
      author = pickAuthor(data)
    }
  }

  function pickAuthor(meta) {
    if (!meta || typeof meta !== "object") return ""
    var keys = ["artist", "album_artist", "author", "composer", "ARTIST", "ALBUM_ARTIST"]
    for (var i = 0; i < keys.length; i++) {
      var v = meta[keys[i]]
      if (v && String(v).trim()) return String(v).trim()
    }
    return ""
  }

  function onFileLoaded() {
    loaded = true
    eofReached = false
    setProp("speed", speed)
    if (pendingSeek > 0) {
      setProp("time-pos", pendingSeek)
      position = pendingSeek
    }
    pendingSeek = -1
    if (pendingPlay) setProp("pause", false)
    pendingPlay = false
  }

  // ------------------------------------------------------------ controls
  function findBook(path) {
    for (var i = 0; i < books.length; i++) if (books[i].path === path) return books[i]
    return null
  }

  function loadBook(path, play) {
    var b = findBook(String(path))
    if (!b) return false
    if (book && loaded) savePosition()

    var saved = positions[b.path]
    book = b
    loaded = false
    author = ""
    chapters = []
    chapterIndex = -1
    eofReached = false
    position = saved && saved.pos > 0 ? saved.pos : 0
    duration = saved && saved.duration > 0 ? saved.duration : 0
    pendingSeek = saved && saved.pos > 0 ? saved.pos : -1
    pendingPlay = !!play
    lastBookPath = b.path

    setProp("pause", true)
    send(["loadfile", Library.bookUrl(b), "replace"])
    saveState()
    return true
  }

  function playPause() {
    if (!hasBook) return false
    if (!loaded) { pendingPlay = !pendingPlay; return true }
    if (paused) play()
    else pause()
    return true
  }

  function play() {
    if (!hasBook) return false
    if (!loaded) { pendingPlay = true; return true }
    // A finished book restarts from the beginning.
    if (eofReached || (duration > 0 && position >= duration - 0.5)) setProp("time-pos", 0)
    setProp("pause", false)
    return true
  }

  function pause() {
    if (!hasBook) return false
    if (!loaded) { pendingPlay = false; return true }
    setProp("pause", true)
    return true
  }

  function seekTo(seconds) {
    if (!hasBook) return false
    var target = Math.max(0, Number(seconds) || 0)
    if (duration > 0) target = Math.min(target, Math.max(0, duration - 0.25))
    if (!loaded) { pendingSeek = target; position = target; return true }
    setProp("time-pos", target)
    position = target
    saveDebounce.restart()
    return true
  }

  function seekBy(delta) {
    return seekTo(position + (Number(delta) || 0))
  }

  function jumpToChapter(index) {
    if (index < 0 || index >= chapters.length) return false
    // Land a hair inside the chapter: an exact seek to the boundary decodes
    // to a pts a few ms early and mpv then reports the previous chapter
    // (observed as chapter 0 -> 1 -> 0 while paused).
    return seekTo((Number(chapters[index].time) || 0) + 0.1)
  }

  function nextChapter() {
    if (chapters.length === 0) return seekBy(skipSeconds)
    return jumpToChapter(chapterIndex + 1)
  }

  function previousChapter() {
    if (chapters.length === 0) return seekBy(-skipSeconds)
    var cur = currentChapter
    if (!cur) return seekTo(0)
    // Deep into a chapter: restart it. Right at its start: go one back.
    if (position - Number(cur.time) > 3 || chapterIndex === 0) return jumpToChapter(chapterIndex)
    return jumpToChapter(chapterIndex - 1)
  }

  function setSpeed(value) {
    var v = Number(value)
    if (!isFinite(v)) return false
    v = Math.max(minSpeed, Math.min(maxSpeed, Math.round(v * 100) / 100))
    speed = v
    if (loaded) setProp("speed", v)
    saveState()
    return true
  }

  function speedStep(direction) {
    return setSpeed(speed + (direction > 0 ? speedStepSize : -speedStepSize))
  }

  function chapterEnd(index) {
    if (index < 0 || index >= chapters.length) return duration
    return index + 1 < chapters.length ? Number(chapters[index + 1].time) : duration
  }

  function savedPercent(path) {
    var s = positions[path]
    if (!s || !(s.duration > 0)) return 0
    return Math.max(0, Math.min(100, (Number(s.pos) || 0) / s.duration * 100))
  }

  function statusJson() {
    return JSON.stringify({
      book: bookPath,
      title: title,
      author: author,
      playing: playing,
      position: Math.round(position),
      duration: Math.round(duration),
      percent: Math.round(percent),
      chapter: chapterIndex,
      chapters: chapters.length,
      chapterTitle: chapterTitle,
      speed: speed
    })
  }

  // --------------------------------------------------------------- state
  function stateJson() {
    return JSON.stringify({ version: 1, current: lastBookPath, speed: speed, positions: positions }, null, 2) + "\n"
  }

  function savePosition() {
    if (!book || !loaded) return
    var next = {}
    for (var k in positions) next[k] = positions[k]
    next[book.path] = { pos: Math.round(position * 10) / 10, duration: Math.round(duration * 10) / 10, updated: Date.now() }
    positions = next
  }

  function saveState() {
    if (!stateLoaded) return
    stateFile.setText(stateJson())
  }

  function saveNow() {
    savePosition()
    saveState()
  }

  function loadState(text) {
    var obj = null
    try { obj = JSON.parse(String(text || "")) } catch (e) { obj = null }
    if (obj && typeof obj === "object") {
      positions = obj.positions && typeof obj.positions === "object" ? obj.positions : {}
      lastBookPath = String(obj.current || "")
      var s = Number(obj.speed)
      speed = isFinite(s) && s > 0 ? Math.max(minSpeed, Math.min(maxSpeed, s)) : 1.0
    }
    stateLoaded = true
    maybeRestore()
  }

  function maybeRestore() {
    if (restored || !stateLoaded || !scanned || !ipc.connected) return
    restored = true
    if (lastBookPath && findBook(lastBookPath)) loadBook(lastBookPath, false)
  }

  // ---------------------------------------------------------------- scan
  readonly property string scanScript: [
    'lib="$1"',
    '[[ -d $lib ]] || exit 0',
    'shopt -s nullglob nocasematch',
    'is_audio() { [[ $1 =~ \\.(m4b|m4a|mp3|opus|ogg|oga|flac|aac|wav|wma)$ ]]; }',
    'for entry in "$lib"/*; do',
    '  if [[ -f $entry ]]; then',
    '    is_audio "$entry" && printf "file\\t%s\\n" "$entry"',
    '  elif [[ -d $entry ]]; then',
    '    files=""',
    '    for f in "$entry"/*; do [[ -f $f ]] && is_audio "$f" && files+="$f"$\'\\x1f\'; done',
    '    [[ -n $files ]] && printf "dir\\t%s\\t%s\\n" "$entry" "$files"',
    '  fi',
    'done',
    'exit 0'
  ].join("\n")

  function rescan() {
    if (scanProc.running) { rescanPending = true; return }
    scanning = true
    scanProc.command = ["bash", "-c", scanScript, "omarchy-audiobook-scan", libraryPath]
    scanProc.running = true
  }

  onLibraryPathChanged: rescan()

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.books = Library.parseScan(text)
        root.scanned = true
        root.scanning = false
        // The loaded book keeps its identity across rescans so the library
        // list can highlight it even if the folder was renamed away.
        if (root.book) {
          var fresh = root.findBook(root.book.path)
          if (fresh) root.book = fresh
        }
        root.maybeRestore()
        if (root.rescanPending) { root.rescanPending = false; root.rescan() }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("audiobook: library scan exited with", exitCode)
    }
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    blockWrites: true
    atomicWrites: true
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Process {
    id: mpv
    command: [
      "mpv",
      "--no-config",
      "--load-scripts=no",
      "--no-video",
      "--audio-display=no",
      "--no-terminal",
      "--really-quiet",
      "--idle=yes",
      "--keep-open=yes",
      "--pause",
      "--hr-seek=yes",
      "--input-ipc-server=" + root.socketPath
    ]
    onStarted: connectRetry.start()
    onExited: function(exitCode) {
      ipc.connected = false
      root.connected = false
      root.loaded = false
      if (root.quitting) return
      if (root.mpvRestarts < 5) {
        root.mpvRestarts++
        console.warn("audiobook: mpv exited (" + exitCode + "), restarting")
        restartTimer.start()
      } else {
        console.warn("audiobook: mpv keeps exiting, giving up")
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: if (!root.quitting) mpv.running = true
  }

  Socket {
    id: ipc
    path: root.socketPath
    connected: false
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(data) { root.handleLine(data) }
    }
    onConnectedChanged: {
      root.connected = connected
      if (connected) {
        connectRetry.stop()
        root.mpvRestarts = 0
        root.observeAll()
        // A reconnect after an mpv restart has no file loaded any more.
        if (root.book && !root.loaded) {
          root.pendingSeek = root.position
          root.pendingPlay = false
          root.setProp("pause", true)
          root.send(["loadfile", Library.bookUrl(root.book), "replace"])
        }
        root.maybeRestore()
      } else if (mpv.running && !root.quitting) {
        root.loaded = false
        connectRetry.start()
      }
    }
  }

  Timer {
    id: connectRetry
    interval: 250
    repeat: true
    onTriggered: {
      if (!mpv.running || root.quitting) { stop(); return }
      if (ipc.connected) { stop(); return }
      ipc.connected = false
      ipc.connected = true
    }
  }

  Timer {
    id: periodicSave
    interval: 10000
    repeat: true
    running: root.playing
    onTriggered: root.saveNow()
  }

  Timer {
    id: saveDebounce
    interval: 600
    onTriggered: root.saveNow()
  }

  IpcHandler {
    target: "audiobook"

    function status(): string { return root.statusJson() }
    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function play(): string { return root.play() ? "ok" : "unhandled" }
    function pause(): string { return root.pause() ? "ok" : "unhandled" }
    function next(): string { return root.nextChapter() ? "ok" : "unhandled" }
    function previous(): string { return root.previousChapter() ? "ok" : "unhandled" }
    function seek(seconds: string): string {
      var n = Number(seconds)
      if (!isFinite(n)) return "invalid"
      return root.seekBy(n) ? "ok" : "unhandled"
    }
    function speed(value: string): string { return root.setSpeed(value) ? "ok" : "invalid" }
    function load(path: string): string { return root.loadBook(path, true) ? "ok" : "unknown" }
    function rescan(): string { root.rescan(); return "ok" }
  }

  Component.onCompleted: {
    mkdirProc.running = true
    stateFile.reload()
    rescan()
    mpv.running = true
  }

  Component.onDestruction: {
    quitting = true
    saveNow()
    send(["quit"])
    if (mpv.running) mpv.signal(15)
  }
}
