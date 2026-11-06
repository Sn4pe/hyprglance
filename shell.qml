import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  id: root

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"

  readonly property var defaults: ({
    scope: "output",
    appScope: "all",
    order: "recent",
    includeCurrent: true,
    thumbnailWidth: 240,
    minThumbnailWidth: 140,
    showTitles: true,
    fontFamily: "",
    fontSize: 13,
    radius: 16,
    showDelay: 50,
    theme: root.configHome + "/stylix/palette.json",
    overview: {
      scope: "workspace",
      layout: "real",
      monitors: "all",
      workspaces: true,
      showEmpty: "drag",
      backdrop: 0.55,
      undim: true,
      drag: true,
      dropPreview: true,
      maxThumbnail: 640,
      workspaceWidth: 160,
      workspaceKeys: { "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "0": 10 },
      margin: 48,
      gap: 24,
      animation: 200
    }
  })
  property var userConfig: ({})
  readonly property var config: Object.assign({}, defaults, userConfig, {
    overview: Object.assign({}, defaults.overview, userConfig.overview)
  })

  property var closing: []
  property var recent: []
  property var windows: []
  property int selected: 0
  property bool open: false
  property bool shown: false
  property string screenName: ""
  property bool overviewOpen: false
  property string overviewScreen: ""
  property bool overviewShown: false
  property bool overviewExpanded: false
  property bool overviewFading: false
  property string overviewPending: ""
  property int overviewRevision: 0
  property var dragWindow: null
  property point dragPoint
  property string keyboardScreen: ""
  property string layoutName: ""
  readonly property var layoutEvents: ["openwindow", "movewindowv2", "changefloatingmode", "fullscreen"]

  Component.onCompleted: {
    DesktopEntries.applications
    setUndim(false)
  }

  FileView {
    path: root.configHome + "/hyprglance/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.userConfig = JSON.parse(text())
      } catch (error) {
        console.warn("hyprglance: invalid config.json:", error)
      }
    }
    onLoadFailed: root.userConfig = {}
  }

  Timer {
    id: closeDispatch

    interval: 60
    onTriggered: root.closing.forEach(address => Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${address}" })`))
  }

  Timer {
    id: closeResume

    interval: 1500
    onTriggered: root.closing = []
  }

  Timer {
    id: overviewReady

    interval: 20
    onTriggered: {
      root.overviewShown = true
      root.overviewRevision++
      overviewExpand.restart()
    }
  }

  Timer {
    id: overviewExpand

    interval: 40
    onTriggered: root.overviewExpanded = root.overviewOpen
  }

  Timer {
    id: overviewClose

    onTriggered: root.finishOverviewClose()
  }

  Timer {
    id: keyboardHold

    interval: 150
    onTriggered: if (!root.dragWindow) root.keyboardScreen = Hyprland.focusedMonitor?.name ?? ""
  }

  Timer {
    id: layoutRefresh

    interval: 250
    onTriggered: Hyprland.refreshToplevels()
  }

  Timer {
    id: showTimer

    interval: config.showDelay
    onTriggered: root.shown = true
  }

  Scheme {
    id: theme

    path: config.theme.replace(/^~(?=\/)/, Quickshell.env("HOME"))
  }

  Connections {
    target: Hyprland

    function onFocusedMonitorChanged() {
      if (keyboardHold.running || root.dragWindow) return
      root.keyboardScreen = Hyprland.focusedMonitor?.name ?? ""
      keyboardHold.restart()
    }

    function onActiveToplevelChanged() {
      const address = Hyprland.activeToplevel?.address
      if (address) root.recent = [address].concat(root.recent.filter(a => a !== address))
    }

    function onRawEvent(event) {
      if (event.name === "custom") {
        const [name, command] = event.data.split(" ")
        if (name === "hyprglance") root.handle(command)
      } else if (event.name === "closewindow") {
        root.recent = root.recent.filter(a => a !== event.data)
      }
      if (root.overviewOpen && event.name === "closewindow") layoutRefresh.restart()
      if (root.overviewOpen && root.layoutEvents.includes(event.name)) {
        Hyprland.refreshToplevels()
        layoutRefresh.restart()
        root.overviewRevision++
      }
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      if (root.overviewOpen) root.overviewRevision++
      if (!root.open) return
      root.windows = root.windows.filter(t => t && Hyprland.toplevels.values.includes(t))
      root.selected = Math.max(0, Math.min(root.selected, root.windows.length - 1))
      if (root.windows.length === 0) root.open = false
    }
  }

  function handle(command) {
    if (command.startsWith("layout-")) {
      layoutName = command.slice(7)
    } else if (["next", "prev", "app-next", "app-prev"].includes(command)) {
      const step = command.endsWith("next") ? 1 : -1
      if (open) selected = (selected + step + windows.length) % windows.length
      else if (!command.startsWith("app-")) show(step)
      else if (activeWindow()) show(step, activeWindow().wayland.appId)
      else leaveSubmap()
    } else if (command === "commit") {
      commit()
    } else if (command === "close") {
      if (open) closeWindow(windows[selected])
    } else if (command === "cancel") {
      open = false
      closeOverview("")
    } else if (command === "overview") {
      open = false
      if (overviewOpen) closeOverview("")
      else openOverview()
    }
  }

  function recency(toplevel) {
    const index = recent.indexOf(toplevel.address)
    return index >= 0 ? index : 1000 + (toplevel.lastIpcObject?.focusHistoryID ?? 999)
  }

  function activeWindow() {
    return Hyprland.toplevels.values.find(t => t.wayland?.activated)
  }

  function activeAddress() {
    return activeWindow()?.address
  }

  function inScope(toplevel) {
    if (config.scope === "all") return true
    if (config.scope === "workspace") return toplevel.workspace === Hyprland.focusedWorkspace
    return toplevel.monitor === Hyprland.focusedMonitor
  }

  function candidates(appId) {
    const active = activeAddress()
    const byRecency = (a, b) => recency(a) - recency(b)
    const byWorkspace = (a, b) => a.workspace.id - b.workspace.id || byRecency(a, b)
    return Hyprland.toplevels.values
      .filter(t => (t.workspace?.id ?? -1) >= 0)
      .filter(t => appId && config.appScope === "all" || inScope(t))
      .filter(t => !appId || t.wayland?.appId === appId)
      .filter(t => appId || config.includeCurrent || t.address !== active)
      .sort(config.order === "workspace" ? byWorkspace : byRecency)
  }

  function overviewWindows(monitor) {
    const byPosition = (a, b) => {
      const [ax, ay] = a.lastIpcObject?.at ?? [0, 0]
      const [bx, by] = b.lastIpcObject?.at ?? [0, 0]
      return a.workspace.id - b.workspace.id || ay - by || ax - bx
    }
    return Hyprland.toplevels.values
      .filter(t => t.monitor?.name === monitor?.name && (t.workspace?.id ?? -1) >= 0)
      .filter(t => config.overview.scope === "output" || t.workspace === monitor?.activeWorkspace)
      .sort(byPosition)
  }

  function closeWindow(toplevel) {
    if (!toplevel || closing.includes(toplevel.address)) return
    closing = closing.concat(toplevel.address)
    closeDispatch.restart()
    closeResume.restart()
  }

  function dropWindow() {
    const toplevel = dragWindow
    const target = overviews.instances.find(o => o.dropWorkspace > 0)
    const workspaceId = target?.dropWorkspace
    dragWindow = null
    keyboardHold.restart()
    if (!toplevel || !target || workspaceId === toplevel.workspace?.id) return
    const created = !Hyprland.workspaces.values.some(w => w.id === workspaceId)
    const place = created ? `hl.dispatch(hl.dsp.workspace.move({ workspace = ${workspaceId}, monitor = "${target.monitor.name}" }))` : ""
    Hyprland.dispatch(`function() hl.dispatch(hl.dsp.window.move({ workspace = ${workspaceId}, follow = false, window = "address:0x${toplevel.address}" })) ${place} end`)
  }

  function focusWindowRequest(toplevel) {
    return `hl.dsp.focus({ window = "address:0x${toplevel.address}" })`
  }

  function setUndim(undim) {
    if (config.overview.undim || !undim) Hyprland.dispatch(`function() HYPRGLANCE_UNDIM(${undim}) end`)
  }

  function openOverview() {
    setUndim(true)
    overviewOpen = true
    overviewScreen = Hyprland.focusedMonitor.name
    keyboardScreen = overviewScreen
    overviewPending = ""
    if (overviewShown) {
      overviewClose.stop()
      overviewFading = false
      overviewExpanded = true
      return
    }
    Hyprland.dispatch(`function() hl.dispatch(hl.dsp.event("hyprglance layout-" .. hl.get_config("general.layout"))) end`)
    Hyprland.refreshMonitors()
    Hyprland.refreshToplevels()
    overviewReady.restart()
  }

  function closeOverview(request, fade = false) {
    if (!overviewOpen) return
    overviewOpen = false
    overviewReady.stop()
    overviewExpand.stop()
    overviewPending = request
    const duration = fade ? Math.min(100, config.overview.animation) : config.overview.animation
    if (!overviewShown || duration <= 0) return finishOverviewClose()
    if (fade) overviewFading = true
    else overviewExpanded = false
    overviewClose.interval = fade ? duration : duration * 0.7
    overviewClose.restart()
  }

  function finishOverviewClose() {
    setUndim(false)
    overviewClose.stop()
    overviewShown = false
    overviewExpanded = false
    overviewFading = false
    overviewRevision++
    const request = overviewPending
    overviewPending = ""
    if (request) Qt.callLater(() => Hyprland.dispatch(request))
  }

  function focusWorkspaceRequest(workspaceId) {
    return `hl.dsp.focus({ workspace = ${workspaceId} })`
  }

  function leaveSubmap() {
    Hyprland.dispatch(`hl.dsp.submap("reset")`)
  }

  function show(step, appId = "") {
    const found = candidates(appId)
    Hyprland.refreshToplevels()
    if (found.length < (appId ? 2 : 1)) return leaveSubmap()
    closeOverview("")
    finishOverviewClose()
    windows = found
    const active = windows.findIndex(t => t.address === activeAddress())
    selected = active >= 0
      ? (active + step + windows.length) % windows.length
      : (step > 0 ? 0 : windows.length - 1)
    screenName = Hyprland.focusedMonitor.name
    shown = config.showDelay <= 0
    if (!shown) showTimer.restart()
    open = true
  }

  function commit() {
    if (!open) return
    const target = windows[selected]
    open = false
    if (target) Hyprland.dispatch(focusWindowRequest(target))
  }

  Variants {
    id: overviews

    model: Quickshell.screens

    Overview {
      required property ShellScreen modelData

      screen: modelData
      visible: root.overviewShown && (config.overview.monitors === "all" || modelData.name === root.overviewScreen)
      monitor: Hyprland.monitorFor(modelData)
      closing: root.closing
      expanded: root.overviewExpanded
      fading: root.overviewFading
      keyboard: visible && (config.overview.monitors !== "all" || modelData.name === root.keyboardScreen)
      settings: config
      colors: theme
      dragWindow: root.dragWindow
      dragPoint: root.dragPoint
      layoutName: root.layoutName
      onDismissed: root.closeOverview("")
      onWindowCloseRequested: toplevel => root.closeWindow(toplevel)
      onWindowDragged: (toplevel, x, y) => {
        root.dragPoint = Qt.point(x, y)
        root.dragWindow = toplevel
      }
      onWindowDropped: root.dropWindow()
      onDragCancelled: {
        root.dragWindow = null
        keyboardHold.restart()
      }
      onWindowChosen: toplevel => {
        const visibleNow = toplevel.workspace === toplevel.monitor?.activeWorkspace
        root.closeOverview(root.focusWindowRequest(toplevel), !visibleNow)
      }
      onWorkspaceChosen: workspaceId => {
        const current = workspaceId === monitor?.activeWorkspace?.id
        root.closeOverview(root.focusWorkspaceRequest(workspaceId), !current)
      }
      onWorkspaceSwitched: workspaceId => root.closeOverview(root.focusWorkspaceRequest(workspaceId), true)

      Connections {
        target: root

        function onOverviewRevisionChanged() {
          windows = root.overviewShown ? root.overviewWindows(monitor) : []
        }
      }
    }
  }

  PanelWindow {
    id: panel

    readonly property int padding: 14
    readonly property int spacing: 8
    readonly property int available: (screen?.width ?? 1920) * 0.9 - padding * 2
    readonly property int columns: {
      const fitting = Math.floor((available + spacing) / (config.minThumbnailWidth + 12 + spacing))
      return Math.max(1, Math.min(root.windows.length, fitting))
    }
    readonly property int thumbnailWidth: {
      const cell = (available - spacing * (columns - 1)) / columns
      return Math.min(config.thumbnailWidth, Math.floor(cell) - 12)
    }

    visible: root.open && root.shown
    screen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprglance"
    implicitWidth: strip.width
    implicitHeight: strip.height

    Rectangle {
      id: strip

      width: row.width + panel.padding * 2
      height: row.height + panel.padding * 2
      radius: config.radius
      color: theme.surface
      border.width: 1
      border.color: theme.outline

      Grid {
        id: row

        x: panel.padding
        y: panel.padding
        columns: panel.columns
        spacing: panel.spacing

        Repeater {
          model: root.windows

          Tile {
            required property var modelData
            required property int index

            toplevel: modelData
            selected: index === root.selected
            capturing: root.open && !root.closing.includes(modelData.address)
            thumbnailWidth: panel.thumbnailWidth
            showWorkspace: root.windows.some(t => t.workspace !== root.windows[0].workspace)
            settings: config
            colors: theme
            onHovered: root.selected = index
            onCloseRequested: root.closeWindow(modelData)
            onActivated: {
              root.selected = index
              root.commit()
              root.leaveSubmap()
            }
          }
        }
      }
    }
  }
}
