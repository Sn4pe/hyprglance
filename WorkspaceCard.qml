import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland

Column {
  id: card

  required property HyprlandWorkspace workspace
  required property HyprlandMonitor monitor
  required property real screenWidth
  required property real screenHeight
  required property var closing
  required property bool selected
  required property int cardWidth
  required property var settings
  required property Scheme colors
  required property var dropRect

  signal hovered
  signal activated

  readonly property int dropId: workspace.id
  readonly property bool current: workspace.id === monitor?.activeWorkspace?.id
  readonly property real ratio: cardWidth / screenWidth

  spacing: 6

  Rectangle {
    width: card.cardWidth
    height: Math.round(card.screenHeight * card.ratio)
    radius: card.settings.radius * 0.4
    color: card.selected ? card.colors.raised : Qt.alpha(card.colors.surface, 0.7)
    border.width: card.selected ? 2 : card.current ? 1 : 0
    border.color: card.colors.accent
    clip: true

    Repeater {
      model: Hyprland.toplevels.values.filter(t => t.workspace?.id === card.workspace.id)

      Item {
        required property HyprlandToplevel modelData

        readonly property var position: modelData.lastIpcObject?.at
        readonly property var size: modelData.lastIpcObject?.size

        visible: position !== undefined && size !== undefined
        x: ((position?.[0] ?? 0) - (card.monitor?.x ?? 0)) * card.ratio
        y: ((position?.[1] ?? 0) - (card.monitor?.y ?? 0)) * card.ratio
        width: (size?.[0] ?? 0) * card.ratio
        height: (size?.[1] ?? 0) * card.ratio

        onWidthChanged: settling.restart()
        onHeightChanged: settling.restart()

        Timer {
          id: settling

          interval: 600
          running: true
        }

        ScreencopyView {
          id: thumbnail

          anchors.fill: parent
          captureSource: card.closing.includes(parent.modelData.address) ? null : parent.modelData.wayland
          constraintSize: Qt.size(parent.width, parent.height)
          live: settling.running || !hasContent
        }

        AppIcon {
          anchors.centerIn: parent
          visible: !thumbnail.hasContent
          toplevel: parent.modelData
          size: 20
        }
      }
    }

    Rectangle {
      visible: card.dropRect !== null
      x: (card.dropRect?.x ?? 0) * card.ratio
      y: (card.dropRect?.y ?? 0) * card.ratio
      width: (card.dropRect?.width ?? 0) * card.ratio
      height: (card.dropRect?.height ?? 0) * card.ratio
      radius: 2
      color: Qt.alpha(card.colors.accent, 0.5)
      border.width: 1
      border.color: card.colors.accent
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onPositionChanged: card.hovered()
      onClicked: card.activated()
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: card.workspace.name
    color: card.current ? card.colors.accent : card.colors.text
    font.family: card.settings.fontFamily || "sans-serif"
    font.pixelSize: card.settings.fontSize
    font.weight: card.current ? Font.DemiBold : Font.Normal
  }
}
