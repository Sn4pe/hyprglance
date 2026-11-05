import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
  id: overview

  component Slide: NumberAnimation {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
  }

  required property HyprlandMonitor monitor
  required property bool keyboard
  required property var closing
  required property bool expanded
  required property bool fading
  required property var settings
  required property Scheme colors

  signal windowChosen(HyprlandToplevel toplevel)
  signal windowCloseRequested(HyprlandToplevel toplevel)
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
    else if (event.key === Qt.Key_Q) windowCloseRequested(windows[selectedWindow] ?? null)
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
  readonly property real screenWidth: screen?.width ?? 1920
  readonly property real screenHeight: screen?.height ?? 1080
  readonly property int stripHeight: options.workspaces
    ? Math.round(options.workspaceWidth * screenHeight / screenWidth) + 6 + Math.ceil(settings.fontSize * 1.5)
    : 0
  readonly property var area: {
    const top = options.margin + (options.workspaces ? stripHeight + options.gap : 0)
    return {
      x: options.margin,
      y: top,
      width: screenWidth - options.margin * 2,
      height: screenHeight - top - options.margin
    }
  }
  readonly property var slots: computeSlots()

  function realRect(toplevel) {
    const position = toplevel?.lastIpcObject?.at
    const size = toplevel?.lastIpcObject?.size
    if (!position || !size) return null
    return {
      x: position[0] - (monitor?.x ?? 0),
      y: position[1] - (monitor?.y ?? 0),
      width: size[0],
      height: size[1]
    }
  }

  function fitInCell(cell, rect) {
    const aspect = rect ? rect.width / rect.height : 16 / 9
    const available = {
      width: Math.max(1, cell.width - options.gap - 12),
      height: Math.max(1, cell.height - options.gap - 12 - titleHeight)
    }
    const width = Math.floor(Math.min(available.width, available.height * aspect, options.maxThumbnail))
    const height = Math.floor(width / aspect)
    return {
      x: cell.x + (cell.width - width - 12) / 2,
      y: cell.y + (cell.height - height - 12 - titleHeight) / 2,
      previewWidth: width,
      previewHeight: height
    }
  }

  function placedCells(rects) {
    if (options.layout !== "real" || options.scope !== "workspace" || rects.length === 0 || rects.some(r => !r)) return null
    const overlaps = (a, b) => a.x < b.x + b.width - 1 && b.x < a.x + a.width - 1
      && a.y < b.y + b.height - 1 && b.y < a.y + a.height - 1
    if (rects.some((a, i) => rects.some((b, j) => i < j && overlaps(a, b)))) return null
    const left = Math.min(...rects.map(r => r.x))
    const top = Math.min(...rects.map(r => r.y))
    const width = Math.max(...rects.map(r => r.x + r.width)) - left
    const height = Math.max(...rects.map(r => r.y + r.height)) - top
    const widest = Math.max(...rects.map(r => r.width))
    const scale = Math.min(area.width / width, area.height / height,
      (options.maxThumbnail + options.gap + 12) / widest)
    const originX = area.x + (area.width - width * scale) / 2
    const originY = area.y + (area.height - height * scale) / 2
    return rects.map(r => ({
      x: originX + (r.x - left) * scale,
      y: originY + (r.y - top) * scale,
      width: r.width * scale,
      height: r.height * scale
    }))
  }

  function gridCells(count) {
    const columns = Math.max(1, Math.ceil(Math.sqrt(count)))
    const rows = Math.max(1, Math.ceil(count / columns))
    const width = Math.min(area.width / columns, options.maxThumbnail + options.gap + 12)
    const height = Math.min(area.height / rows, Math.round(options.maxThumbnail * 0.75) + options.gap + 12 + titleHeight)
    const originX = area.x + (area.width - width * columns) / 2
    const originY = area.y + (area.height - height * rows) / 2
    return Array.from({ length: count }, (_, i) => ({
      x: originX + (i % columns) * width,
      y: originY + Math.floor(i / columns) * height,
      width: width,
      height: height
    }))
  }

  function computeSlots() {
    const rects = windows.map(realRect)
    const cells = placedCells(rects) ?? gridCells(windows.length)
    return cells.map((cell, i) => {
      const slot = fitInCell(cell, rects[i])
      const rect = rects[i]
      const flies = rect !== null && windows[i]?.workspace === monitor?.activeWorkspace
      const startScale = flies ? rect.width / slot.previewWidth : 0.96
      return Object.assign(slot, {
        flies: flies,
        startScale: startScale,
        startX: flies ? rect.x - 6 * startScale : slot.x,
        startY: flies ? rect.y - 6 * startScale : slot.y
      })
    })
  }

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "hyprglance-overview"
  WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onWindowsChanged: selectedWindow = Math.min(selectedWindow, windows.length - 1)

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
    focus: true
    Keys.onPressed: event => overview.handleKey(event)
    onClicked: overview.dismissed()
  }

  Item {
    anchors.fill: parent
    opacity: overview.fading ? 0 : 1

    Behavior on opacity {
      enabled: overview.fading

      NumberAnimation {
        duration: Math.min(100, overview.options.animation)
      }
    }

    Rectangle {
      anchors.fill: parent
      color: overview.colors.surface
      opacity: overview.expanded ? overview.options.backdrop : 0

      Behavior on opacity { Slide { duration: overview.options.animation } }
    }

    Item {
      id: stage

      anchors.fill: parent

      Repeater {
        model: overview.windows

        Tile {
          id: tile

          required property var modelData
          required property int index

          readonly property var slot: overview.slots[index] ?? null

          toplevel: modelData
          selected: index === overview.selectedWindow
          capturing: overview.visible && !overview.closing.includes(modelData.address)
          exactFrame: true
          thumbnailWidth: slot?.previewWidth ?? 1
          thumbnailHeight: slot?.previewHeight ?? 1
          showWorkspace: overview.options.scope !== "workspace"
          settings: overview.settings
          colors: overview.colors
          transformOrigin: Item.TopLeft
          x: overview.expanded ? (slot?.x ?? 0) : (slot?.startX ?? 0)
          y: overview.expanded ? (slot?.y ?? 0) : (slot?.startY ?? 0)
          scale: overview.expanded ? 1 : (slot?.startScale ?? 1)
          opacity: overview.expanded || slot?.flies ? 1 : 0
          chromeOpacity: overview.expanded ? 1 : 0
          onHovered: overview.selectedWindow = index
          onActivated: overview.windowChosen(modelData)
          onCloseRequested: overview.windowCloseRequested(modelData)

          Behavior on x { Slide { duration: overview.options.animation } }

          Behavior on y { Slide { duration: overview.options.animation } }

          Behavior on scale { Slide { duration: overview.options.animation } }

          Behavior on opacity { NumberAnimation { duration: overview.options.animation } }

          Behavior on chromeOpacity { NumberAnimation { duration: overview.options.animation } }
        }
      }
    }

    Row {
      id: strip

      anchors.horizontalCenter: parent.horizontalCenter
      y: overview.options.margin
      visible: overview.options.workspaces
      opacity: overview.expanded ? 1 : 0
      spacing: 12

      Behavior on opacity { NumberAnimation { duration: overview.options.animation } }

      Repeater {
        model: overview.visible ? overview.workspaces : []

        WorkspaceCard {
          required property HyprlandWorkspace modelData
          required property int index

          workspace: modelData
          monitor: overview.monitor
          screenWidth: overview.screenWidth
          screenHeight: overview.screenHeight
          closing: overview.closing
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
  }
}
