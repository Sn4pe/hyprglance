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

  property int thumbnailHeight: Math.round(thumbnailWidth * 9 / 16)
  property bool exactFrame: false
  property real chromeOpacity: 1
  property bool showWorkspace: false

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
    onPositionChanged: tile.hovered()
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: mouse => mouse.button === Qt.MiddleButton ? tile.closeRequested() : tile.activated()
  }
}
