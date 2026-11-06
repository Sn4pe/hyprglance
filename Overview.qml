import QtQuick
import Quickshell
import Quickshell.Widgets
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
  required property var dragWindow
  required property point dragPoint
  required property string layoutName

  signal windowChosen(HyprlandToplevel toplevel)
  signal windowCloseRequested(HyprlandToplevel toplevel)
  signal windowDragged(HyprlandToplevel toplevel, real x, real y)
  signal windowDropped
  signal dragCancelled
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
  readonly property var monitorWorkspaces: Hyprland.workspaces.values
    .filter(w => w.id > 0 && w.monitor?.name === monitor?.name)
    .sort((a, b) => a.id - b.id)
  readonly property var emptyWorkspaces: monitorWorkspaces
    .filter(w => w !== monitor?.activeWorkspace && !Hyprland.toplevels.values.some(t => t.workspace === w))
  readonly property bool showEmpty: options.showEmpty === "always" || (options.showEmpty === "drag" && dragWindow !== null)
  readonly property var workspaces: showEmpty ? monitorWorkspaces : monitorWorkspaces.filter(w => !emptyWorkspaces.includes(w))
  readonly property int titleHeight: settings.showTitles ? 26 : 0
  readonly property real screenWidth: screen?.width ?? 1920
  readonly property real screenHeight: screen?.height ?? 1080
  readonly property int stripHeight: options.workspaces
    ? cardHeight + 6 + Math.ceil(settings.fontSize * 1.5)
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
  readonly property real cardHeight: Math.round(options.workspaceWidth * screenHeight / screenWidth)
  readonly property int emptyWorkspace: {
    if (emptyWorkspaces.length > 0) return emptyWorkspaces[0].id
    let id = 1
    while (Hyprland.workspaces.values.some(w => w.id === id)) id++
    return id
  }
  readonly property point dragLocal: Qt.point(dragPoint.x - (monitor?.x ?? 0), dragPoint.y - (monitor?.y ?? 0))
  readonly property bool dragHere: visible && dragWindow !== null
    && dragLocal.x >= 0 && dragLocal.y >= 0 && dragLocal.x < screenWidth && dragLocal.y < screenHeight
  readonly property int dropWorkspace: {
    if (!dragHere) return 0
    if (options.workspaces) {
      const point = strip.mapFromItem(null, dragLocal.x, dragLocal.y)
      const card = strip.childAt(point.x, point.y)
      if (card?.dropId) return card.dropId
    }
    return dragWindow.monitor?.name !== monitor?.name ? monitor?.activeWorkspace?.id ?? 0 : 0
  }
  readonly property var dropRect: predictDrop()
  readonly property var stageDropRect: {
    if (!dropRect || dropWorkspace !== monitor?.activeWorkspace?.id) return null
    if (!dropRect.owner) {
      const scale = Math.min(area.width / screenWidth, area.height / screenHeight)
      return {
        x: area.x + (area.width - screenWidth * scale) / 2 + dropRect.x * scale,
        y: area.y + (area.height - screenHeight * scale) / 2 + dropRect.y * scale,
        width: dropRect.width * scale,
        height: dropRect.height * scale
      }
    }
    const slot = slots[windows.indexOf(dropRect.owner.toplevel)]
    if (!slot) return null
    const scaleX = slot.previewWidth / dropRect.owner.width
    const scaleY = slot.previewHeight / dropRect.owner.height
    return {
      x: slot.x + 6 + (dropRect.x - dropRect.owner.x) * scaleX,
      y: slot.y + 6 + (dropRect.y - dropRect.owner.y) * scaleY,
      width: dropRect.width * scaleX,
      height: dropRect.height * scaleY
    }
  }

  function predictDrop() {
    if (!options.dropPreview || layoutName !== "dwindle" || dropWorkspace <= 0 || dropWorkspace === dragWindow?.workspace?.id) return null
    const rects = Hyprland.toplevels.values
      .filter(t => t.workspace?.id === dropWorkspace && !t.lastIpcObject?.floating)
      .map(t => ({ toplevel: t, rect: realRect(t) }))
      .filter(r => r.rect)
      .map(r => Object.assign(r.rect, { toplevel: r.toplevel }))
    if (rects.length === 0) {
      const reserved = monitor?.lastIpcObject?.reserved ?? [0, 0, 0, 0]
      return {
        x: reserved[0] + 8,
        y: reserved[1] + 8,
        width: screenWidth - reserved[0] - reserved[2] - 16,
        height: screenHeight - reserved[1] - reserved[3] - 16
      }
    }
    const inside = r => dragLocal.x >= r.x && dragLocal.x < r.x + r.width && dragLocal.y >= r.y && dragLocal.y < r.y + r.height
    const distance = r => Math.hypot(r.x + r.width / 2 - dragLocal.x, r.y + r.height / 2 - dragLocal.y)
    const focused = rects.find(r => r.toplevel.wayland?.activated)
    const owner = focused ?? rects.find(inside) ?? rects.sort((a, b) => distance(a) - distance(b))[0]
    const horizontal = owner.width > owner.height
    const first = (!focused || inside(focused)) && (horizontal
      ? dragLocal.x < owner.x + owner.width / 2
      : dragLocal.y < owner.y + owner.height / 2)
    const width = horizontal ? (owner.width - 10) / 2 : owner.width
    const height = horizontal ? owner.height : (owner.height - 10) / 2
    return {
      x: horizontal && !first ? owner.x + owner.width - width : owner.x,
      y: !horizontal && !first ? owner.y + owner.height - height : owner.y,
      width: width,
      height: height,
      owner: owner
    }
  }

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
        model: ScriptModel {
          values: overview.windows
        }

        Tile {
          id: tile

          required property var modelData
          required property int index

          readonly property var slot: overview.slots[index] ?? null
          property real entrance: overview.expanded ? 0 : 1

          Component.onCompleted: {
            // Drop the binding: only tiles created while the overview is open fade in
            entrance = entrance
            if (entrance === 0) entranceWait.start()
          }

          Timer {
            id: entranceWait

            property int elapsed: 0

            interval: 40
            repeat: true
            onTriggered: {
              elapsed += interval
              if ((elapsed >= 120 && tile.settled) || elapsed >= 400) {
                stop()
                fadeIn.start()
              }
            }
          }

          NumberAnimation {
            id: fadeIn

            target: tile
            property: "entrance"
            to: 1
            duration: overview.options.animation
          }

          toplevel: modelData
          selected: index === overview.selectedWindow
          capturing: overview.visible && !overview.closing.includes(modelData.address)
          exactFrame: true
          thumbnailWidth: slot?.previewWidth ?? 1
          thumbnailHeight: slot?.previewHeight ?? 1
          showWorkspace: overview.options.scope !== "workspace"
          settings: overview.settings
          colors: overview.colors
          draggable: overview.options.drag
          transformOrigin: Item.TopLeft
          x: overview.expanded ? (slot?.x ?? 0) : (slot?.startX ?? 0)
          y: overview.expanded ? (slot?.y ?? 0) : (slot?.startY ?? 0)
          scale: overview.expanded ? 1 : (slot?.startScale ?? 1)
          opacity: entrance * (overview.dragWindow === modelData ? 0.35 : overview.expanded || slot?.flies ? 1 : 0)
          chromeOpacity: overview.expanded ? 1 : 0
          onHovered: overview.selectedWindow = index
          onActivated: overview.windowChosen(modelData)
          onCloseRequested: overview.windowCloseRequested(modelData)
          onDragMoved: (x, y) => overview.windowDragged(modelData, x + (overview.monitor?.x ?? 0), y + (overview.monitor?.y ?? 0))
          onDragFinished: overview.windowDropped()
          onDragCancelled: overview.dragCancelled()

          Behavior on x { Slide { duration: overview.options.animation } }

          Behavior on y { Slide { duration: overview.options.animation } }

          Behavior on scale { Slide { duration: overview.options.animation } }

          Behavior on opacity {
            enabled: tile.entrance === 1

            NumberAnimation { duration: overview.options.animation }
          }

          Behavior on chromeOpacity { NumberAnimation { duration: overview.options.animation } }
        }
      }

      Rectangle {
        visible: overview.stageDropRect !== null
        x: overview.stageDropRect?.x ?? 0
        y: overview.stageDropRect?.y ?? 0
        width: overview.stageDropRect?.width ?? 0
        height: overview.stageDropRect?.height ?? 0
        radius: overview.settings.radius * 0.5
        color: Qt.alpha(overview.colors.accent, 0.3)
        border.width: 2
        border.color: overview.colors.accent
      }
    }

    Row {
      id: strip

      x: (parent.width - width) / 2
      y: overview.options.margin
      visible: overview.options.workspaces
      opacity: overview.expanded ? 1 : 0
      spacing: 12

      Behavior on x {
        enabled: overview.expanded

        Slide { duration: overview.options.animation }
      }

      Behavior on opacity { NumberAnimation { duration: overview.options.animation } }

      add: Transition {
        enabled: overview.expanded

        NumberAnimation {
          property: "opacity"
          from: 0
          to: 1
          duration: overview.options.animation
        }
      }

      move: Transition {
        enabled: overview.expanded

        Slide {
          property: "x"
          duration: overview.options.animation
        }
      }

      Repeater {
        model: ScriptModel {
          values: overview.visible ? overview.workspaces : []
        }

        WorkspaceCard {
          required property HyprlandWorkspace modelData
          required property int index

          workspace: modelData
          monitor: overview.monitor
          screenWidth: overview.screenWidth
          screenHeight: overview.screenHeight
          closing: overview.closing
          selected: overview.dragWindow ? overview.dropWorkspace === modelData.id : overview.keyboard && index === overview.cursor
          dropRect: overview.dropWorkspace === modelData.id ? overview.dropRect : null
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

      Rectangle {
        readonly property int dropId: overview.emptyWorkspace
        readonly property bool selected: overview.dropWorkspace === dropId

        visible: overview.dragWindow !== null && !overview.workspaces.some(w => overview.emptyWorkspaces.includes(w))
        width: overview.options.workspaceWidth
        height: overview.cardHeight
        radius: overview.settings.radius * 0.4
        color: selected ? overview.colors.raised : Qt.alpha(overview.colors.surface, 0.7)
        border.width: selected ? 2 : 0
        border.color: overview.colors.accent

        Text {
          anchors.centerIn: parent
          text: "+"
          color: overview.colors.text
          font.family: overview.settings.fontFamily || "sans-serif"
          font.pixelSize: overview.settings.fontSize * 2
        }
      }
    }

    ClippingRectangle {
      visible: overview.dragHere
      x: overview.dragLocal.x + 12
      y: overview.dragLocal.y + 12
      width: ghost.implicitWidth
      height: ghost.implicitHeight
      radius: overview.settings.radius * 0.5
      color: overview.colors.surface

      ScreencopyView {
        id: ghost

        readonly property bool capturing: overview.dragHere && !overview.closing.includes(overview.dragWindow.address)

        captureSource: capturing ? overview.dragWindow.wayland : null
        live: capturing
        constraintSize: Qt.size(overview.options.workspaceWidth, overview.options.workspaceWidth)
      }
    }
  }
}
