import QtQuick
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Rectangle {
  id: tile

  required property HyprlandToplevel toplevel
  required property bool selected
  required property bool capturing
  required property int thumbnailWidth
  required property var settings
  required property Scheme colors

  signal hovered
  signal activated
  signal closeRequested
  signal dragMoved(real x, real y)
  signal dragFinished
  signal dragCancelled

  property int thumbnailHeight: Math.round(thumbnailWidth * 9 / 16)
  property bool exactFrame: false
  property real chromeOpacity: 1
  property bool showWorkspace: false
  property bool draggable: false
  property bool dragging: false
  property bool dragged: false
  property point pressPoint
  readonly property bool settled: preview.hasContent
    && Math.abs(preview.implicitWidth / preview.implicitHeight - thumbnailWidth / thumbnailHeight) < 0.05

  Component.onDestruction: if (dragging) dragCancelled()

  width: frame.width + 12
  height: content.height + 12
  radius: settings.radius * 0.6
  color: selected && chromeOpacity === 1 ? colors.raised : "transparent"
  border.width: selected && chromeOpacity === 1 ? 1 : 0
  border.color: colors.accent

  Timer {
    id: iconDelay

    interval: 150
    running: true
  }

  Column {
    id: content

    x: 6
    y: 6
    spacing: 8

    Item {
      id: frame

      width: !tile.exactFrame && preview.hasContent ? preview.implicitWidth : tile.thumbnailWidth
      height: tile.thumbnailHeight

      ClippingRectangle {
        anchors.centerIn: parent
        width: preview.implicitWidth
        height: preview.implicitHeight
        radius: tile.settings.radius * 0.5
        color: tile.colors.surface

        ScreencopyView {
          id: preview

          captureSource: tile.capturing ? tile.toplevel?.wayland ?? null : null
          live: tile.capturing
          constraintSize: Qt.size(tile.thumbnailWidth, tile.thumbnailHeight)
        }
      }

      AppIcon {
        anchors.centerIn: parent
        visible: !preview.hasContent && !iconDelay.running
        toplevel: tile.toplevel
        size: 48
      }
    }

    Row {
      visible: tile.settings.showTitles
      opacity: tile.chromeOpacity
      spacing: 6

      AppIcon {
        anchors.verticalCenter: parent.verticalCenter
        toplevel: tile.toplevel
      }

      Text {
        id: workspaceLabel

        anchors.verticalCenter: parent.verticalCenter
        visible: tile.showWorkspace
        text: tile.toplevel?.workspace?.name ?? ""
        color: tile.colors.muted
        font.family: tile.settings.fontFamily || "sans-serif"
        font.pixelSize: tile.settings.fontSize
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: frame.width - 24 - (workspaceLabel.visible ? workspaceLabel.width + 6 : 0)
        text: tile.toplevel?.title ?? ""
        elide: Text.ElideRight
        color: tile.colors.text
        font.family: tile.settings.fontFamily || "sans-serif"
        font.pixelSize: tile.settings.fontSize
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: tile.draggable
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onPressed: mouse => {
      tile.pressPoint = Qt.point(mouse.x, mouse.y)
      tile.dragged = false
    }
    onPositionChanged: mouse => {
      const distance = Math.hypot(mouse.x - tile.pressPoint.x, mouse.y - tile.pressPoint.y)
      if (tile.draggable && (mouse.buttons & Qt.LeftButton) && (tile.dragging || distance >= Qt.styleHints.startDragDistance)) {
        tile.dragging = true
        tile.dragged = true
        const point = mapToItem(null, mouse.x, mouse.y)
        tile.dragMoved(point.x, point.y)
      } else {
        tile.hovered()
      }
    }
    onReleased: {
      if (!tile.dragging) return
      tile.dragging = false
      tile.dragFinished()
    }
    onCanceled: {
      if (!tile.dragging) return
      tile.dragging = false
      tile.dragCancelled()
    }
    onClicked: mouse => {
      if (tile.dragged) return
      if (mouse.button === Qt.MiddleButton) tile.closeRequested()
      else tile.activated()
    }
  }
}
