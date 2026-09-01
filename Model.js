.pragma library

var DEFAULT_INSTANCE = "https://cobaltapi.cjs.nz"

var DEFAULTS = {
  instance: DEFAULT_INSTANCE,
  apiKey: "",
  downloadDir: "",
  videoQuality: "1080",
  audioFormat: "mp3",
  downloadMode: "auto",
  filenameStyle: "pretty",
  alwaysProxy: true,
  webFallback: true
}

var MODE_OPTIONS = [
  { value: "auto", label: "auto", icon: "󰓏" },
  { value: "audio", label: "audio", icon: "󰝚" },
  { value: "mute", label: "mute", icon: "󰝟" }
]

var QUALITY_OPTIONS = [
  { value: "max", label: "Max" },
  { value: "1080", label: "1080p" },
  { value: "720", label: "720p" }
]

var AUDIO_FORMAT_OPTIONS = [
  { value: "best", label: "Best" },
  { value: "mp3", label: "MP3" },
  { value: "opus", label: "Opus" },
  { value: "wav", label: "WAV" }
]

var INSTANCE_UNUSABLE = "This instance is not usable. Try another instance in settings."
var YOUTUBE_BLOCKED = "YouTube blocked this instance. Try another in settings."
var FETCH_FAILED = "Could not fetch that link."
var DOWNLOAD_FAILED = "Download failed."

var ERROR_MESSAGES = {
  "error.api.auth.jwt.missing": "This instance is not usable without a browser login. Try another instance in settings.",
  "error.api.auth.api-key.missing": INSTANCE_UNUSABLE,
  "error.api.auth.api-key.invalid": INSTANCE_UNUSABLE,
  "error.api.youtube.login": "This instance cannot reach YouTube. Try another instance in settings.",
  "error.api.youtube.token.invalid": YOUTUBE_BLOCKED,
  "error.api.youtube.cipher": YOUTUBE_BLOCKED,
  "error.api.fetch.empty": "Nothing downloadable was found at that link.",
  "error.api.fetch.fail": FETCH_FAILED,
  "error.api.fetch.critical": FETCH_FAILED,
  "error.plugin": DOWNLOAD_FAILED,
  "error.api.service.unsupported": "That site is not supported by this instance.",
  "error.api.link.invalid": "That does not look like a supported link.",
  "error.api.link.unsupported": "That site is not supported.",
  "error.api.rate_exceeded": "Rate limited. Wait a moment and try again.",
  "error.api.content.video.unavailable": "That video is unavailable.",
  "error.api.content.video.live": "Live streams cannot be saved.",
  "error.api.content.post.unavailable": "That post is unavailable.",
  "error.http": "The instance returned an unexpected error."
}

var STRING_KEYS = ["instance", "apiKey", "downloadDir", "videoQuality", "audioFormat", "downloadMode", "filenameStyle"]
var MODES = ["auto", "audio", "mute"]
var QUALITIES = ["max", "4320", "2160", "1440", "1080", "720", "480", "360", "240", "144"]
var AUDIO_FORMATS = ["best", "mp3", "ogg", "wav", "opus"]

function defaultConfig() {
  var out = {}
  for (var key in DEFAULTS)
    out[key] = DEFAULTS[key]
  return out
}

function mergeConfig(raw) {
  var out = defaultConfig()
  var parsed = raw
  if (typeof raw === "string") {
    try { parsed = JSON.parse(raw) } catch (e) { parsed = ({}) }
  }
  if (!parsed || typeof parsed !== "object")
    return out
  for (var i = 0; i < STRING_KEYS.length; i++) {
    var key = STRING_KEYS[i]
    if (parsed[key] !== undefined && parsed[key] !== null)
      out[key] = String(parsed[key])
  }
  if (parsed.alwaysProxy !== undefined) out.alwaysProxy = !!parsed.alwaysProxy
  if (parsed.webFallback !== undefined) out.webFallback = !!parsed.webFallback
  out.instance = normalizeInstance(out.instance)
  if (MODES.indexOf(out.downloadMode) === -1) out.downloadMode = "auto"
  if (QUALITIES.indexOf(out.videoQuality) === -1) out.videoQuality = "1080"
  if (AUDIO_FORMATS.indexOf(out.audioFormat) === -1) out.audioFormat = "mp3"
  return out
}

function serializeConfig(cfg) {
  var merged = mergeConfig(cfg)
  return JSON.stringify({
    instance: merged.instance,
    apiKey: merged.apiKey,
    downloadDir: merged.downloadDir,
    videoQuality: merged.videoQuality,
    audioFormat: merged.audioFormat,
    downloadMode: merged.downloadMode,
    filenameStyle: merged.filenameStyle,
    alwaysProxy: merged.alwaysProxy,
    webFallback: merged.webFallback
  }, null, 2) + "\n"
}

function normalizeInstance(value) {
  var s = String(value || "").trim()
  if (!s) return DEFAULT_INSTANCE
  if (s.indexOf("://") === -1) s = "https://" + s
  return s.replace(/\/+$/, "")
}

function isHttpUrl(value) {
  return /^https?:\/\//i.test(String(value || "").trim())
}

function looksLikeUrl(value) {
  return isHttpUrl(extractUrl(value))
}

function extractUrl(value) {
  var text = String(value || "").trim()
  if (!text) return ""
  var match = text.match(/https?:\/\/[^\s<>"']+/i)
      || text.match(/\bwww\.[^\s<>"']+/i)
      || text.match(/\b(?:youtu\.be|youtube\.com|tiktok\.com|instagram\.com|x\.com|twitter\.com|soundcloud\.com|vimeo\.com|reddit\.com|bsky\.app)\/[^\s<>"']+/i)
  if (!match) return ""
  var url = match[0]
  if (url.indexOf("://") === -1) url = "https://" + url
  return trimUrlJunk(url)
}

function trimUrlJunk(value) {
  return String(value || "").replace(/[.,;:!?)\\]]+$/, "")
}

function normalizeUrl(value) {
  var extracted = extractUrl(value)
  if (isHttpUrl(extracted)) return extracted
  return ""
}

function errorCode(payload) {
  if (!payload || typeof payload === "string") return ""
  if (payload.error && payload.error.code) return String(payload.error.code)
  if (payload.code) return String(payload.code)
  return ""
}

function errorContext(payload) {
  if (!payload || typeof payload === "string") return null
  if (payload.error && payload.error.context) return payload.error.context
  if (payload.context) return payload.context
  return null
}

function errorMessage(payload) {
  if (!payload) return DOWNLOAD_FAILED
  if (typeof payload === "string") return payload
  var code = errorCode(payload)
  var context = errorContext(payload)
  var service = context && context.service ? String(context.service) : ""
  if (code === "error.api.fetch.fail" && service)
    return "This instance cannot reach " + service + " right now. Try again in a few minutes."
  if (ERROR_MESSAGES[code]) return ERROR_MESSAGES[code]
  if (payload.message) return String(payload.message)
  if (payload.error && payload.error.message) return String(payload.error.message)
  if (code) return code.replace(/^error\.api\./, "").replace(/\./g, " ")
  return DOWNLOAD_FAILED
}

function parseJsonPayload(raw) {
  var text = String(raw || "").trim()
  if (!text) return null
  var lines = text.split(/\r?\n/)
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i].trim()
    if (!line) continue
    try { return JSON.parse(line) } catch (e) {}
  }
  try { return JSON.parse(text) } catch (e) { return null }
}

function pickerRows(payload) {
  var items = payload && payload.picker ? payload.picker : []
  var rows = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i] || {}
    rows.push({
      itemType: String(item.type || "photo"),
      url: String(item.url || ""),
      thumb: String(item.thumb || ""),
      label: (item.type || "item") + " " + (i + 1)
    })
  }
  if (payload && payload.audio) {
    rows.push({
      itemType: "audio",
      url: String(payload.audio),
      thumb: "",
      label: payload.audioFilename || "audio"
    })
  }
  return rows
}

function basename(path) {
  var s = String(path || "")
  var i = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"))
  return i >= 0 ? s.slice(i + 1) : s
}
