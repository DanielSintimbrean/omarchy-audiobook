import QtQuick
import qs.Commons
import qs.Ui
import "Library.js" as Library

BarWidget {
  id: root
  moduleName: "io.github.danielsintimbrean.audiobook"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool hasBook: service ? service.hasBook : false
  readonly property bool playing: service ? service.playing : false

  readonly property string tooltip: {
    if (!service) return "Audiobook"
    if (!service.hasBook) return "Audiobook — no book loaded"
    var parts = [service.title]
    if (service.chapterTitle) parts.push(service.chapterTitle)
    parts.push(Library.formatPercent(service.position, service.duration))
    return parts.join("  ·  ")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  // The library folder is a per-widget setting on the shell.json layout entry;
  // the service owns the scan, so hand it over whenever it changes.
  function pushLibrary() {
    if (root.service) root.service.libraryDir = String(setting("library", "~/Audiobooks"))
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); pushLibrary() }
  onServiceChanged: { injectPanel(); pushLibrary() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋋"  // nf-md-headphones
    slotSize: Style.bar.statusSlot
    dimmed: !root.playing
    opacity: root.hasBook ? 1.0 : 0.55
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
      else if (root.service) root.service.playPause()
    }

    onWheelMoved: function(delta) {
      if (!root.service || !root.service.hasBook) return
      root.service.seekBy(delta > 0 ? root.service.skipSeconds : -root.service.skipSeconds)
    }
  }
}
