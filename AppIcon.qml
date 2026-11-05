import QtQuick
import Quickshell
import Quickshell.Hyprland

Image {
  required property HyprlandToplevel toplevel
  property int size: 18

  readonly property string appId: toplevel?.lastIpcObject?.class ?? toplevel?.wayland?.appId ?? ""

  width: size
  height: size
  sourceSize: Qt.size(size, size)
  source: Quickshell.iconPath(DesktopEntries.heuristicLookup(appId)?.icon ?? appId, true)
}
