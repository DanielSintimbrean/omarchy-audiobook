.pragma library

// Pure helpers shared by Service, BarWidget and Panel. No QML state here.

var AUDIO_EXT = ["m4b", "m4a", "mp3", "opus", "ogg", "oga", "flac", "aac", "wav", "wma"]

function expandHome(path, home) {
  var p = String(path || "").trim()
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.substring(1)
  return p
}

function baseName(path) {
  var p = String(path || "")
  while (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
  var i = p.lastIndexOf("/")
  return i === -1 ? p : p.substring(i + 1)
}

function stripExt(name) {
  var n = String(name || "")
  var i = n.lastIndexOf(".")
  return i > 0 ? n.substring(0, i) : n
}

function extOf(name) {
  var n = String(name || "")
  var i = n.lastIndexOf(".")
  return i > 0 ? n.substring(i + 1).toLowerCase() : ""
}

// Chapter title derived from a file name: drop the extension and a leading
// track number ("01 - Intro.mp3" -> "Intro").
function chapterTitleFromFile(path) {
  var n = stripExt(baseName(path))
  return n.replace(/^\s*\d+\s*[-._)\]:]*\s*/, "") || n
}

// Natural ("01" < "2" < "10") case-insensitive compare, no Intl dependency.
function naturalCompare(a, b) {
  var ax = String(a).toLowerCase().match(/(\d+|\D+)/g) || []
  var bx = String(b).toLowerCase().match(/(\d+|\D+)/g) || []
  var n = Math.min(ax.length, bx.length)
  for (var i = 0; i < n; i++) {
    var x = ax[i], y = bx[i]
    var xn = /^\d/.test(x), yn = /^\d/.test(y)
    if (xn && yn) {
      var d = parseInt(x, 10) - parseInt(y, 10)
      if (d !== 0) return d
    } else if (x !== y) {
      return x < y ? -1 : 1
    }
  }
  return ax.length - bx.length
}

// Output of the scan script: one book per line.
//   file<TAB>/path/book.m4b
//   dir<TAB>/path/Book<TAB>/path/Book/01.mp3<US>/path/Book/02.mp3<US>
function parseScan(text) {
  var books = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var parts = line.split("\t")
    if (parts[0] === "file" && parts[1]) {
      books.push({ path: parts[1], kind: "file", name: stripExt(baseName(parts[1])), files: [parts[1]] })
    } else if (parts[0] === "dir" && parts[1]) {
      var files = (parts[2] || "").split("\x1f").filter(function(f) { return f.length > 0 })
      files.sort(naturalCompare)
      if (files.length) books.push({ path: parts[1], kind: "dir", name: baseName(parts[1]), files: files })
    }
  }
  books.sort(function(a, b) { return naturalCompare(a.name, b.name) })
  return books
}

// mpv EDL: "%<bytes>%<text>" quoting avoids every escaping problem with
// commas, semicolons and spaces in paths. Lengths are UTF-8 byte counts.
function utf8Length(s) {
  return encodeURIComponent(String(s)).replace(/%[0-9A-Fa-f]{2}/g, "x").length
}

function edlQuote(s) {
  return "%" + utf8Length(s) + "%" + s
}

// A folder book becomes one virtual file: mpv exposes the whole thing with a
// single duration/percent-pos and one chapter per segment, titled by us.
function bookUrl(book) {
  if (!book) return ""
  if (book.kind !== "dir") return book.path
  var segs = []
  for (var i = 0; i < book.files.length; i++) {
    segs.push(edlQuote(book.files[i]) + ",title=" + edlQuote(chapterTitleFromFile(book.files[i])))
  }
  return "edl://" + segs.join(";")
}

function formatTime(sec) {
  var s = Math.max(0, Math.round(Number(sec) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var mm = (h > 0 && m < 10 ? "0" : "") + m
  var rr = (r < 10 ? "0" : "") + r
  return h > 0 ? h + ":" + mm + ":" + rr : mm + ":" + rr
}

function formatPercent(pos, duration) {
  var d = Number(duration) || 0
  if (d <= 0) return "0%"
  return Math.max(0, Math.min(100, Math.round((Number(pos) || 0) / d * 100))) + "%"
}

function formatSpeed(speed) {
  var v = Number(speed) || 1
  var s = (Math.round(v * 100) / 100).toString()
  return s + "×"
}

function bookKindLabel(book) {
  if (!book) return ""
  if (book.kind === "dir") return book.files.length + (book.files.length === 1 ? " file" : " files")
  return extOf(book.path)
}
