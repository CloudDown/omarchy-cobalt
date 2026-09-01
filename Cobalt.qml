import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "clouddown.cobalt"
  ipcTarget: "clouddown.cobalt"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string view: "main"
  property string urlText: ""
  property string downloadMode: "auto"
  property string videoQuality: "1080"
  property string audioFormat: "mp3"
  property var config: Model.defaultConfig()

  property bool busy: false
  property string statusKind: "idle"
  property string statusText: ""
  property int progressPercent: -1
  property string lastPath: ""
  property var pickerItems: []
  property int pickerIndex: 0
  property var saveQueue: []

  property string settingsDir: ""
  property bool resolveStopping: false
  property bool resolveGotReply: false
  property bool ytdlpTried: false
  property string lastCobaltError: ""
  property real mainPageHeight: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color mutedForeground: Qt.darker(root.foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string getScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/clouddown.cobalt/bin/cobalt-get"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/cobalt.json"
  readonly property bool canSubmit: Model.looksLikeUrl(root.urlText) && !root.busy
  readonly property bool editing: (urlField && urlField.activeFocus)
    || (dirField && dirField.activeFocus)

  function python(args) {
    return ["/usr/bin/python3", "-u", root.getScript].concat(args)
  }

  function focusUrl() {
    Qt.callLater(function() {
      if (urlField && urlField.visible) urlField.forceActiveFocus()
    })
  }

  function open() {
    if (!root.busy) {
      root.view = "main"
      root.statusKind = "idle"
      root.statusText = ""
      root.progressPercent = -1
      root.pickerItems = []
      root.urlText = ""
      if (urlField) urlField.text = ""
    }
    root.controller.show()
    root.focusUrl()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  function loadConfig(raw) {
    root.config = Model.mergeConfig(raw)
    root.downloadMode = root.config.downloadMode
    root.videoQuality = root.config.videoQuality
    root.audioFormat = root.config.audioFormat
    root.settingsDir = root.config.downloadDir
  }

  function persistConfig() {
    var next = Model.mergeConfig(root.config)
    next.downloadMode = root.downloadMode
    next.videoQuality = root.videoQuality
    next.audioFormat = root.audioFormat
    next.downloadDir = root.settingsDir
    root.config = next
    configFile.setText(Model.serializeConfig(next))
  }

  function applyClipboard(raw) {
    var url = Model.extractUrl(raw)
    if (!url) {
      root.setStatus("error", "No URL in the clipboard.")
      return
    }
    root.urlText = url
    if (urlField) urlField.text = url
    if (root.statusKind === "error") root.setStatus("idle", "")
    root.focusUrl()
  }

  function pasteFromClipboard() {
    pasteProc.running = true
  }

  function downloadClicked() {
    if (root.busy) {
      root.cancelJob()
      return
    }
    if (root.statusKind === "done") {
      root.openLastFile()
      return
    }
    if (!root.canSubmit) return
    root.startDownload()
  }

  function setStatus(kind, text, percent) {
    root.statusKind = kind
    root.statusText = text || ""
    if (percent === undefined) return
    root.progressPercent = percent
  }

  function openLastFile() {
    if (!root.lastPath) return
    Quickshell.execDetached(["xdg-open", root.lastPath])
  }

  function cancelJob() {
    resolveProc.running = false
    saveProc.running = false
    ytdlpProc.running = false
    root.saveQueue = []
    root.busy = false
    root.setStatus("idle", "Cancelled")
  }

  function startDownload() {
    var url = Model.normalizeUrl(root.urlText)
    if (!url) {
      root.setStatus("error", "Paste a supported link first.")
      return
    }
    root.urlText = url
    root.pickerItems = []
    root.view = "main"
    root.busy = true
    root.resolveGotReply = false
    root.ytdlpTried = false
    root.lastCobaltError = ""
    ytdlpProc.running = false
    root.persistConfig()
    root.setStatus("progress", "Asking cobalt…", -1)
    if (resolveProc.running) {
      root.resolveStopping = true
      resolveProc.running = false
    }
    resolveProc.command = root.python([
      "--config", root.configPath,
      "resolve",
      "--url", url,
      "--mode", root.downloadMode,
      "--quality", root.videoQuality,
      "--audio-format", root.audioFormat,
      "--filename-style", String(root.config.filenameStyle || "pretty"),
      "--instance", String(root.config.instance || "")
    ])
    root.resolveStopping = false
    resolveProc.running = true
  }

  function handleResolveText(raw) {
    var payload = Model.parseJsonPayload(raw)
    if (!payload) return
    root.resolveGotReply = true
    var status = String(payload.status || "")
    if (status === "tunnel" || status === "redirect") {
      root.enqueueSave(payload.url, payload.filename || "")
      root.drainQueue()
      return
    }
    if (status === "picker") {
      root.busy = false
      root.pickerItems = Model.pickerRows(payload)
      root.pickerIndex = 0
      root.view = "picker"
      root.setStatus("idle", root.pickerItems.length + " items")
      return
    }
    root.lastCobaltError = status === "local-processing"
      ? "This instance could not prepare the file."
      : Model.errorMessage(payload)
    root.startYtdlp()
  }

  function startYtdlp() {
    if (root.ytdlpTried) {
      root.busy = false
      root.setStatus("error", root.lastCobaltError || "Download failed.")
      return
    }
    var url = Model.normalizeUrl(root.urlText)
    if (!url) {
      root.busy = false
      root.setStatus("error", root.lastCobaltError || "Paste a supported link first.")
      return
    }
    root.ytdlpTried = true
    root.saveQueue = []
    saveProc.running = false
    root.view = "main"
    root.busy = true
    root.setStatus("progress", "Trying yt-dlp…", -1)
    ytdlpProc.command = root.python([
      "ytdlp",
      "--url", url,
      "--mode", root.downloadMode,
      "--quality", root.videoQuality,
      "--audio-format", root.audioFormat,
      "--dir", String(root.config.downloadDir || "").trim()
    ])
    ytdlpProc.running = true
  }

  function enqueueSave(url, filename) {
    var href = String(url || "").trim()
    if (!Model.isHttpUrl(href)) return
    var next = root.saveQueue.slice()
    next.push({ url: href, filename: filename || "" })
    root.saveQueue = next
  }

  function drainQueue() {
    if (saveProc.running) return
    if (root.saveQueue.length === 0) {
      root.busy = false
      return
    }
    var job = root.saveQueue[0]
    root.saveQueue = root.saveQueue.slice(1)
    root.busy = true
    root.setStatus("progress", "Saving…", 0)
    saveProc.command = root.python([
      "save",
      "--url", job.url,
      "--filename", job.filename || "",
      "--dir", String(root.config.downloadDir || "").trim()
    ])
    saveProc.running = true
  }

  function handleSaveLine(line) {
    var payload = ({})
    try { payload = JSON.parse(line) } catch (e) { return }
    var event = String(payload.event || payload.status || "")
    if (event === "start") {
      var known = Number(payload.bytes)
      root.setStatus("progress", payload.filename || "Saving…", known > 0 ? 0 : -1)
      return
    }
    if (event === "progress") {
      var percent = Number(payload.percent)
      root.setStatus("progress", payload.filename || root.statusText, isFinite(percent) ? percent : -1)
      return
    }
    if (event === "done") {
      root.lastPath = String(payload.path || "")
      root.setStatus("done", Model.basename(root.lastPath) || "Saved", 100)
      return
    }
    if (event === "error" || payload.status === "error") {
      root.saveQueue = []
      if (root.ytdlpTried) {
        root.setStatus("error", Model.errorMessage(payload))
        return
      }
      root.lastCobaltError = Model.errorMessage(payload)
      root.startYtdlp()
    }
  }

  function downloadPickerIndex(index) {
    if (index < 0 || index >= root.pickerItems.length) return
    var item = root.pickerItems[index]
    root.view = "main"
    root.enqueueSave(item.url, item.label || "")
    root.drainQueue()
  }

  function downloadPickerAll() {
    for (var i = 0; i < root.pickerItems.length; i++)
      root.enqueueSave(root.pickerItems[i].url, root.pickerItems[i].label || "")
    root.view = "main"
    root.drainQueue()
  }

  function openSettings() {
    root.settingsDir = root.config.downloadDir
    root.view = "settings"
  }

  function closeSettings() {
    root.persistConfig()
    root.view = "main"
    root.focusUrl()
  }

  function handleCloseKey() {
    if (root.view === "settings") root.closeSettings()
    else if (root.view === "picker") root.view = "main"
    else if (root.busy) root.cancelJob()
    else root.close()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("{}")
    onFileChanged: reload()
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyClipboard(text)
    }
  }

  Process {
    id: resolveProc
    stdout: SplitParser {
      onRead: function(line) { root.handleResolveText(line) }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.resolveStopping) {
        root.resolveStopping = false
        return
      }
      if (root.busy && !root.resolveGotReply && !root.ytdlpTried) {
        root.lastCobaltError = "Couldn't reach cobalt."
        root.startYtdlp()
      }
    }
  }

  Process {
    id: saveProc
    stdout: SplitParser {
      onRead: function(line) { root.handleSaveLine(line) }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.statusKind === "done") {
        root.busy = false
        return
      }
      if (root.saveQueue.length > 0) {
        Qt.callLater(root.drainQueue)
        return
      }
      if (root.ytdlpTried || ytdlpProc.running)
        return
      if (exitCode !== 0 && root.statusKind !== "error") {
        root.saveQueue = []
        root.lastCobaltError = "Download failed."
        root.startYtdlp()
        return
      }
      if (root.statusKind !== "progress")
        root.busy = false
    }
  }

  Process {
    id: ytdlpProc
    stdout: SplitParser {
      onRead: function(line) { root.handleSaveLine(line) }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.statusKind === "done") {
        root.busy = false
        return
      }
      if (root.statusKind !== "error")
        root.setStatus("error", root.lastCobaltError || "yt-dlp could not download that link.")
      root.busy = false
    }
  }

  component ActionButton: Button {
    bordered: true
    foreground: root.foreground
    background: root.background
    accent: Color.accent
    fontFamily: root.fontFamily
    horizontalPadding: Style.space(14)
    verticalPadding: Style.space(8)
  }

  component SettingBlock: Column {
    id: block
    required property string title
    required property var options
    required property string settingValue
    signal changed(string value)

    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: block.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    ButtonGroup {
      width: parent.width
      spacing: Style.space(6)
      options: block.options
      value: block.settingValue
      foreground: root.foreground
      background: root.background
      accent: Color.accent
      fontFamily: root.fontFamily
      focusable: false
      onChanged: function(v) { block.changed(v) }
    }
  }

  Component {
    id: mascotIcon
    Item {
      Image {
        id: mascotSrc
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/cobalt.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        cache: false
        visible: false
        layer.enabled: true
        sourceSize.width: Math.round(width * 2)
        sourceSize.height: Math.round(height * 2)
      }

      MultiEffect {
        anchors.fill: mascotSrc
        source: mascotSrc
        colorization: 1.0
        colorizationColor: root.barForeground
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: mascotIcon
    opticalSize: Style.bar.iconCanvas
    active: root.opened
    tooltipText: root.opened ? "" : "Cobalt Download"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(heroHeader.implicitHeight + Math.max(root.mainPageHeight, mainPage.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onCloseRequested: root.handleCloseKey()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (root.view === "main" && root.canSubmit) root.startDownload()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroll.width
          spacing: 0

          Item {
            id: heroHeader
            width: parent.width
            implicitHeight: Math.max(heroLabels.implicitHeight, gearButton.implicitHeight)

            Column {
              id: heroLabels
              anchors.left: parent.left
              anchors.right: gearButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.view === "settings" ? "Settings" : (root.view === "picker" ? "Choose a file" : "Cobalt")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: "DOWNLOADER"
                color: root.mutedForeground
                opacity: root.view === "main" ? 1 : 0
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Button {
              id: gearButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.view === "settings" ? "󰁍" : "󰒓"
              iconSize: Style.font.display
              fontSize: Style.font.display
              bordered: false
              foreground: root.foreground
              background: root.background
              accent: Color.accent
              fontFamily: root.fontFamily
              tooltipText: root.view === "settings" ? "Back" : "Settings"
              onClicked: root.view === "settings" ? root.closeSettings() : root.openSettings()
            }
          }

          Column {
            id: mainPage
            width: parent.width
            spacing: Style.space(12)
            visible: root.view === "main"
            onImplicitHeightChanged: if (implicitHeight > 0) root.mainPageHeight = implicitHeight

            Item {
              width: parent.width
              height: Style.space(104)

              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -Style.space(16)
                width: Style.space(120)
                height: Style.space(120)
                fillMode: Image.PreserveAspectFit
                source: Qt.resolvedUrl("assets/smile.png")
                asynchronous: true
                smooth: true
                cache: false
              }
            }

            Item {
              width: parent.width
              implicitHeight: urlField.implicitHeight

              Text {
                id: linkGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                z: 1
                text: "󰌹"
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }

              TextField {
                id: urlField
                anchors.fill: parent
                leftPadding: Style.space(36)
                placeholderText: "paste the link here"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: if (root.urlText !== text) root.urlText = text
                onAccepted: if (root.canSubmit) root.startDownload()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                  }
                }
              }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(modeGroup.implicitHeight, downloadButton.implicitHeight)

              BorderSurface {
                id: modeGroup
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: modeRow.implicitWidth
                implicitHeight: modeRow.implicitHeight
                radius: Style.cornerRadius
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                Row {
                  id: modeRow
                  spacing: 0

                  Repeater {
                    model: Model.MODE_OPTIONS

                    delegate: Item {
                      id: modeChip
                      required property var modelData
                      required property int index
                      readonly property string modeValue: String(modelData.value)
                      readonly property bool modeSelected: modeValue === root.downloadMode
                      implicitWidth: modeInner.implicitWidth + Style.space(20)
                      implicitHeight: modeInner.implicitHeight + Style.space(16)

                      Rectangle {
                        anchors.fill: parent
                        color: modeChip.modeSelected ? Style.selectedFillFor(root.foreground, Color.accent) : (modeMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                        radius: Style.cornerRadius
                      }

                      Rectangle {
                        visible: modeChip.index > 0
                        width: 1
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        z: 1
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
                      }

                      Row {
                        id: modeInner
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        Text {
                          text: String(modelData.icon || "")
                          visible: text !== ""
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          text: String(modelData.label || modelData.value)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }

                      MouseArea {
                        id: modeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.downloadMode = modeChip.modeValue
                      }
                    }
                  }
                }
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                ActionButton {
                  text: "paste"
                  iconText: "󰆏"
                  onClicked: root.pasteFromClipboard()
                }

                ActionButton {
                  id: downloadButton
                  text: root.busy ? "cancel" : (root.statusKind === "done" ? "open" : "download")
                  iconText: root.busy ? "󰜺" : (root.statusKind === "done" ? "󰏌" : "󰇚")
                  selected: !root.busy
                  enabled: root.busy || root.statusKind === "done" || root.canSubmit
                  onClicked: root.downloadClicked()
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: root.statusText !== ""

              Rectangle {
                visible: root.statusKind === "progress"
                width: parent.width
                height: Style.space(6)
                radius: height / 2
                color: Style.normalFillFor(root.foreground, Color.accent)

                Rectangle {
                  width: root.progressPercent < 0 ? parent.width * 0.35 : parent.width * Math.max(0, Math.min(100, root.progressPercent)) / 100
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.statusText
                textFormat: Text.PlainText
                color: root.statusKind === "error" ? Color.urgent : Qt.darker(root.foreground, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }
          }

          Column {
            id: pickerPage
            width: parent.width
            spacing: Style.space(12)
            visible: root.view === "picker"

            Repeater {
              model: root.pickerItems
              delegate: ActionButton {
                required property var modelData
                required property int index
                width: body.width
                text: modelData.label
                textFormat: Text.PlainText
                leftAlign: true
                selected: index === root.pickerIndex
                onClicked: {
                  root.pickerIndex = index
                  root.downloadPickerIndex(index)
                }
              }
            }

            Row {
              spacing: Style.space(10)
              ActionButton {
                text: "Save all"
                selected: true
                onClicked: root.downloadPickerAll()
              }
              ActionButton {
                text: "Back"
                onClicked: root.view = "main"
              }
            }
          }

          Column {
            id: settingsPage
            width: parent.width
            spacing: 0
            visible: root.view === "settings"
            height: Math.max(root.mainPageHeight, qualityBlock.implicitHeight + audioBlock.implicitHeight + folderBlock.implicitHeight)

            readonly property real leftover: Math.max(0, height - qualityBlock.implicitHeight - audioBlock.implicitHeight - folderBlock.implicitHeight)
            readonly property real pad: leftover / 4

            Item { width: parent.width; height: settingsPage.pad }

            SettingBlock {
              id: qualityBlock
              title: "Quality"
              options: Model.QUALITY_OPTIONS
              settingValue: root.videoQuality
              onChanged: function(v) { root.videoQuality = v; root.persistConfig() }
            }

            Item { width: parent.width; height: settingsPage.pad }

            SettingBlock {
              id: audioBlock
              title: "Audio"
              options: Model.AUDIO_FORMAT_OPTIONS
              settingValue: root.audioFormat
              onChanged: function(v) { root.audioFormat = v; root.persistConfig() }
            }

            Item { width: parent.width; height: settingsPage.pad }

            Column {
              id: folderBlock
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "Folder"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              TextField {
                id: dirField
                width: parent.width
                text: root.settingsDir
                placeholderText: "~/Downloads"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: {
                  root.settingsDir = text
                  root.persistConfig()
                }
              }
            }

            Item { width: parent.width; height: settingsPage.pad }
          }
        }
      }
    }
  }
}
