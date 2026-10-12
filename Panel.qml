import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Library.js" as Library

Panel {
  id: root
  moduleName: "io.github.danielsintimbrean.audiobook"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool openedFromHotkey: false
  property bool libraryMode: false

  // The bar identifies this panel by the widget mounted in its slot.
  readonly property var barIdentity: hostWidget || root
  readonly property bool hasBook: service ? service.hasBook : false
  readonly property bool showLibrary: libraryMode || !hasBook
  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color dimmer: Qt.darker(fg, 1.8)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var chapters: service ? service.chapters : []
  readonly property var books: service ? service.books : []

  function open() {
    openedFromHotkey = false
    root.controller.show()
    refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    libraryMode = false
    if (service) service.rescan()
  }

  function pickBook(path) {
    if (!service) return
    service.loadBook(path, true)
    libraryMode = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.service && !root.showLibrary) root.service.playPause()
      onMoveRequested: function(dx, dy) {
        if (!root.service || root.showLibrary) return
        if (dx !== 0) root.service.seekBy(dx * root.service.skipSeconds)
        if (dy !== 0) root.service.speedStep(-dy)
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)

          // ------------------------------------------------------ player
          Column {
            visible: !root.showLibrary
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.service ? root.service.title : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: root.service ? root.service.author : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: {
                  if (!root.service) return ""
                  if (!root.service.loaded) return "Loading…"
                  if (root.chapters.length === 0) return ""
                  return "Chapter " + (root.service.chapterIndex + 1) + " of " + root.chapters.length + "  ·  " + root.service.chapterTitle
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelSlider {
              id: seekSlider
              width: parent.width
              bar: root.bar
              minimum: root.service ? root.service.chapterStart : 0
              maximum: root.service && root.service.chapterEndTime > minimum ? root.service.chapterEndTime : minimum + 1
              value: root.service ? root.service.position : 0
              step: root.service ? root.service.skipSeconds : 30
              enabled: root.service && root.service.loaded
              onReleased: function(v) { if (root.service) root.service.seekTo(v) }
            }

            Item {
              width: parent.width
              height: elapsedText.implicitHeight

              Text {
                id: elapsedText
                anchors.left: parent.left
                text: Library.formatTime(root.service ? (seekSlider.dragging ? seekSlider.liveValue : root.service.position) - root.service.chapterStart : 0)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.service ? Library.formatPercent((seekSlider.dragging ? seekSlider.liveValue : root.service.position) - root.service.chapterStart, root.service.chapterEndTime - root.service.chapterStart) : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                text: Library.formatTime(root.service ? root.service.chapterEndTime - root.service.chapterStart : 0)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              Button {
                iconText: "󰒮"
                tooltipText: "Previous chapter"
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: root.service && root.service.loaded
                opacity: enabled ? 1.0 : 0.4
                onClicked: if (root.service) root.service.previousChapter()
              }

              Button {
                text: "−30s"
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: root.service && root.service.loaded
                opacity: enabled ? 1.0 : 0.4
                onClicked: if (root.service) root.service.seekBy(-root.service.skipSeconds)
              }

              Button {
                iconText: root.service && root.service.playing ? "󰏤" : "󰐊"
                tooltipText: root.service && root.service.playing ? "Pause" : "Play"
                foreground: root.fg
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.panelGap
                iconSize: Style.font.iconLarge
                enabled: root.hasBook
                opacity: enabled ? 1.0 : 0.4
                onClicked: if (root.service) root.service.playPause()
              }

              Button {
                text: "+30s"
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: root.service && root.service.loaded
                opacity: enabled ? 1.0 : 0.4
                onClicked: if (root.service) root.service.seekBy(root.service.skipSeconds)
              }

              Button {
                iconText: "󰒭"
                tooltipText: "Next chapter"
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: root.service && root.service.loaded
                opacity: enabled ? 1.0 : 0.4
                onClicked: if (root.service) root.service.nextChapter()
              }
            }

            Item {
              width: parent.width
              height: speedRow.implicitHeight

              Row {
                id: speedRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Speed"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  text: "−"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  enabled: root.service && root.service.speed > root.service.minSpeed + 0.001
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: if (root.service) root.service.speedStep(-1)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(40)
                  horizontalAlignment: Text.AlignHCenter
                  text: root.service ? Library.formatSpeed(root.service.speed) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Button {
                  text: "+"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  enabled: root.service && root.service.speed < root.service.maxSpeed - 0.001
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: if (root.service) root.service.speedStep(1)
                }
              }

              Button {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰂺"
                text: "Library"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.libraryMode = true
              }
            }

            PanelSeparator {
              visible: root.chapters.length > 0
              width: parent.width
              foreground: root.fg
            }

            PanelSectionHeader {
              visible: root.chapters.length > 0
              text: "Chapters"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Column {
              id: chapterList
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.chapters

                BorderSurface {
                  id: chapterRow
                  required property var modelData
                  required property int index

                  readonly property bool selected: root.service && root.service.chapterIndex === index
                  readonly property real chapterDuration: root.service ? root.service.chapterEnd(index) - (Number(modelData.time) || 0) : 0

                  width: chapterList.width
                  height: chapterInner.implicitHeight + Style.space(8)
                  radius: Style.spacing.labelGap
                  color: selected ? Style.selectedFillFor(root.fg, Commons.Color.accent) : (chapterMouse.containsMouse ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent")
                  borderSpec: selected ? Border.controlSpec("normal", root.fg, Commons.Color.accent) : Border.none()

                  Row {
                    id: chapterInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: chapterRow.borderLeft + Style.space(8)
                    anchors.rightMargin: chapterRow.borderRight + Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(22)
                      horizontalAlignment: Text.AlignRight
                      text: chapterRow.index + 1
                      color: chapterRow.selected ? root.fg : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(22) - Style.space(8) - durationText.width - Style.space(8)
                      text: String(chapterRow.modelData.title || ("Chapter " + (chapterRow.index + 1)))
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: chapterRow.selected
                      elide: Text.ElideRight
                    }

                    Text {
                      id: durationText
                      anchors.verticalCenter: parent.verticalCenter
                      text: Library.formatTime(chapterRow.chapterDuration)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: chapterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.jumpToChapter(chapterRow.index)
                  }
                }
              }
            }
          }

          // ----------------------------------------------------- library
          Column {
            visible: root.showLibrary
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              height: Math.max(libraryTitle.implicitHeight, libraryActions.implicitHeight)

              Column {
                id: libraryTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - libraryActions.width - Style.space(8)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: "Library"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: root.service ? root.service.libraryPath : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Row {
                id: libraryActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  iconText: "󰑐"
                  tooltipText: "Rescan"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  iconSpinning: root.service && root.service.scanning
                  onClicked: if (root.service) root.service.rescan()
                }

                Button {
                  visible: root.hasBook
                  text: "Back"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.libraryMode = false
                }
              }
            }

            Text {
              visible: root.books.length === 0
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.service && root.service.scanning
                ? "Scanning…"
                : "No audiobooks found. Drop .m4b / .mp3 files, or one folder per book, into the library folder."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              id: bookList
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.books

                BorderSurface {
                  id: bookRow
                  required property var modelData

                  readonly property bool selected: root.service && root.service.bookPath === modelData.path
                  readonly property real savedPercent: root.service ? root.service.savedPercent(modelData.path) : 0

                  width: bookList.width
                  height: bookInner.implicitHeight + Style.space(10)
                  radius: Style.spacing.labelGap
                  color: selected ? Style.selectedFillFor(root.fg, Commons.Color.accent) : (bookMouse.containsMouse ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent")
                  borderSpec: selected ? Border.controlSpec("normal", root.fg, Commons.Color.accent) : Border.none()

                  Row {
                    id: bookInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: bookRow.borderLeft + Style.space(8)
                    anchors.rightMargin: bookRow.borderRight + Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: bookRow.modelData.kind === "dir" ? "󰉋" : "󰈣"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                      width: Style.space(18)
                      horizontalAlignment: Text.AlignHCenter
                    }

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(18) - Style.space(8) - bookPercent.width - Style.space(8)
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: bookRow.modelData.name
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: bookRow.selected
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: Library.bookKindLabel(bookRow.modelData)
                        color: root.dimmer
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      id: bookPercent
                      anchors.verticalCenter: parent.verticalCenter
                      text: bookRow.savedPercent > 0 ? Math.round(bookRow.savedPercent) + "%" : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: bookMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickBook(bookRow.modelData.path)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
