import QtQuick
import Quickshell
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

  readonly property string appId: toplevel.lastIpcObject?.class ?? toplevel.wayland?.appId ?? ""
  readonly property string icon: Quickshell.iconPath(DesktopEntries.heuristicLookup(appId)?.icon ?? appId, true)
  readonly property int thumbnailHeight: Math.round(thumbnailWidth * 9 / 16)

  width: thumbnailWidth + 12
  height: content.height + 12
  radius: settings.radius * 0.6
  color: selected ? colors.raised : "transparent"
  border.width: selected ? 1 : 0
  border.color: colors.accent

  Column {
    id: content

    x: 6
    y: 6
    spacing: 8

    Item {
      width: tile.thumbnailWidth
      height: tile.thumbnailHeight

      Rectangle {
        anchors.fill: preview
        visible: preview.hasContent
        color: tile.colors.surface
      }

      ScreencopyView {
        id: preview

        anchors.centerIn: parent
        captureSource: tile.capturing ? tile.toplevel.wayland : null
        live: tile.capturing
        constraintSize: Qt.size(tile.thumbnailWidth, tile.thumbnailHeight)
      }

      Image {
        anchors.centerIn: parent
        visible: !preview.hasContent
        width: 48
        height: 48
        sourceSize: Qt.size(48, 48)
        source: tile.icon
      }
    }

    Row {
      visible: tile.settings.showTitles
      spacing: 6

      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        sourceSize: Qt.size(18, 18)
        source: tile.icon
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: tile.thumbnailWidth - 24
        text: tile.toplevel.title
        elide: Text.ElideRight
        color: tile.selected ? tile.colors.text : tile.colors.muted
        font.family: tile.settings.fontFamily || "sans-serif"
        font.pixelSize: tile.settings.fontSize
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: tile.hovered()
    onClicked: tile.activated()
  }
}
