import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
  id: overview

  required property HyprlandMonitor monitor
  required property bool keyboard
  required property var settings
  required property Scheme colors

  signal windowChosen(HyprlandToplevel toplevel)
  signal workspaceChosen(int workspaceId)
  signal workspaceSwitched(int workspaceId)
  signal dismissed

  property var windows: []
  property int selectedWindow: -1
  property int cursor: 0

  function moveCursor(step) {
    selectedWindow = -1
    if (workspaces.length > 0) cursor = (cursor + step + workspaces.length) % workspaces.length
  }

  function moveWindowSelection(step) {
    if (windows.length === 0) return
    selectedWindow = selectedWindow < 0
      ? (step > 0 ? 0 : windows.length - 1)
      : (selectedWindow + step + windows.length) % windows.length
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) dismissed()
    else if (event.key === Qt.Key_Left) moveCursor(-1)
    else if (event.key === Qt.Key_Right) moveCursor(1)
    else if (event.key === Qt.Key_Tab) moveWindowSelection(1)
    else if (event.key === Qt.Key_Backtab) moveWindowSelection(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (windows[selectedWindow]) windowChosen(windows[selectedWindow])
      else if (workspaces[cursor]) workspaceChosen(workspaces[cursor].id)
    } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
      const target = options.workspaceKeys[event.key - Qt.Key_0]
      if (target) workspaceChosen(target)
    }
  }

  readonly property var options: settings.overview
  readonly property var workspaces: Hyprland.workspaces.values
    .filter(w => w.id > 0 && w.monitor?.name === monitor?.name)
    .filter(w => w === monitor?.activeWorkspace || Hyprland.toplevels.values.some(t => t.workspace === w))
    .sort((a, b) => a.id - b.id)
  readonly property int titleHeight: settings.showTitles ? 26 : 0
  readonly property int columns: Math.max(1, Math.ceil(Math.sqrt(windows.length)))
  readonly property int rows: Math.max(1, Math.ceil(windows.length / columns))
  readonly property int cellWidth: Math.min(options.maxThumbnail,
    Math.floor((area.width - options.gap * (columns - 1)) / columns) - 12)
  readonly property int cellHeight: Math.min(Math.round(options.maxThumbnail * 0.75),
    Math.floor((area.height - options.gap * (rows - 1)) / rows) - 12 - titleHeight)

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: Qt.alpha(colors.surface, options.backdrop)
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "hyprglance-overview"
  WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onVisibleChanged: {
    selectedWindow = -1
    cursor = Math.max(0, workspaces.findIndex(w => w.id === monitor?.activeWorkspace?.id))
  }

  Connections {
    target: overview.monitor

    function onActiveWorkspaceChanged() {
      if (overview.monitor?.activeWorkspace) overview.workspaceSwitched(overview.monitor.activeWorkspace.id)
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: overview.dismissed()
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onPressed: event => overview.handleKey(event)
  }

  Column {
    anchors.fill: parent
    anchors.margins: overview.options.margin
    spacing: overview.options.gap

    Row {
      id: strip

      anchors.horizontalCenter: parent.horizontalCenter
      visible: overview.options.workspaces
      spacing: 12

      Repeater {
        model: overview.visible ? overview.workspaces : []

        WorkspaceCard {
          required property HyprlandWorkspace modelData
          required property int index

          workspace: modelData
          monitor: overview.monitor
          screenWidth: overview.width
          screenHeight: overview.height
          selected: overview.keyboard && index === overview.cursor
          cardWidth: overview.options.workspaceWidth
          settings: overview.settings
          colors: overview.colors
          onHovered: {
            overview.cursor = index
            overview.selectedWindow = -1
          }
          onActivated: overview.workspaceChosen(modelData.id)
        }
      }
    }

    Item {
      id: area

      width: parent.width
      height: parent.height - (strip.visible ? strip.height + parent.spacing : 0)

      Grid {
        anchors.centerIn: parent
        columns: overview.columns
        spacing: overview.options.gap

        Repeater {
          model: overview.windows

          Tile {
            required property var modelData
            required property int index

            toplevel: modelData
            selected: index === overview.selectedWindow
            capturing: overview.visible
            thumbnailWidth: overview.cellWidth
            thumbnailHeight: overview.cellHeight
            fitHeight: true
            showWorkspace: overview.options.scope !== "workspace"
            settings: overview.settings
            colors: overview.colors
            onHovered: overview.selectedWindow = index
            onActivated: overview.windowChosen(modelData)
          }
        }
      }
    }
  }
}
