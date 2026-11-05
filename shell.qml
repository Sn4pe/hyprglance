import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  id: root

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"

  property var recent: []
  property var windows: []
  property int selected: 0
  property bool open: false
  property string screenName: ""

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    DesktopEntries.applications
  }

  FileView {
    id: configFile

    path: root.configHome + "/hyprglance/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: configRetry.start()

    JsonAdapter {
      id: config

      property string scope: "output"
      property string order: "recent"
      property bool includeCurrent: true
      property int thumbnailWidth: 240
      property bool showTitles: true
      property string fontFamily: ""
      property int fontSize: 13
      property int radius: 16
      property string theme: root.configHome + "/stylix/palette.json"
    }
  }

  Timer {
    id: configRetry

    interval: 2000
    onTriggered: configFile.reload()
  }

  Scheme {
    id: theme

    path: config.theme.replace(/^~(?=\/)/, Quickshell.env("HOME"))
  }

  Connections {
    target: Hyprland

    function onActiveToplevelChanged() {
      const address = Hyprland.activeToplevel?.address
      if (address) root.recent = [address].concat(root.recent.filter(a => a !== address))
    }

    function onRawEvent(event) {
      const [name, command] = event.data.split(" ")
      if (event.name === "custom" && name === "hyprglance") root.handle(command)
    }
  }

  function handle(command) {
    if (command === "next" || command === "prev") {
      const step = command === "next" ? 1 : -1
      if (open) selected = (selected + step + windows.length) % windows.length
      else show(step)
    } else if (command === "commit") {
      commit()
    } else if (command === "cancel") {
      open = false
    }
  }

  function recency(toplevel) {
    const index = recent.indexOf(toplevel.address)
    return index >= 0 ? index : 1000 + (toplevel.lastIpcObject?.focusHistoryID ?? 999)
  }

  function activeAddress() {
    return Hyprland.activeToplevel?.address
      ?? Hyprland.toplevels.values.find(t => t.lastIpcObject?.focusHistoryID === 0)?.address
  }

  function inScope(toplevel) {
    if (config.scope === "all") return true
    if (config.scope === "workspace") return toplevel.workspace === Hyprland.focusedWorkspace
    return toplevel.monitor === Hyprland.focusedMonitor
  }

  function candidates() {
    const active = activeAddress()
    const byRecency = (a, b) => recency(a) - recency(b)
    const byWorkspace = (a, b) => a.workspace.id - b.workspace.id || byRecency(a, b)
    return Hyprland.toplevels.values
      .filter(t => (t.workspace?.id ?? -1) >= 0 && inScope(t))
      .filter(t => config.includeCurrent || t.address !== active)
      .sort(config.order === "workspace" ? byWorkspace : byRecency)
  }

  function show(step) {
    windows = candidates()
    Hyprland.refreshToplevels()
    if (windows.length === 0) return
    const active = windows.findIndex(t => t.address === activeAddress())
    selected = active >= 0
      ? (active + step + windows.length) % windows.length
      : (step > 0 ? 0 : windows.length - 1)
    screenName = Hyprland.focusedMonitor.name
    open = true
  }

  function commit() {
    if (!open) return
    const target = windows[selected]
    open = false
    if (target) Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${target.address}" })`)
  }

  PanelWindow {
    id: panel

    readonly property int padding: 14
    readonly property int spacing: 8
    readonly property int thumbnailWidth: {
      const count = Math.max(root.windows.length, 1)
      const available = (screen?.width ?? 1920) * 0.9 - padding * 2 - (spacing + 12) * count
      return Math.min(config.thumbnailWidth, Math.floor(available / count))
    }

    visible: root.open
    screen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprglance"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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

      Row {
        id: row

        x: panel.padding
        y: panel.padding
        spacing: panel.spacing

        Repeater {
          model: root.windows

          Tile {
            required property var modelData
            required property int index

            toplevel: modelData
            selected: index === root.selected
            capturing: root.open
            thumbnailWidth: panel.thumbnailWidth
            settings: config
            colors: theme
            onHovered: root.selected = index
            onActivated: {
              root.selected = index
              root.commit()
              Hyprland.dispatch(`hl.dsp.submap("reset")`)
            }
          }
        }
      }
    }
  }
}
