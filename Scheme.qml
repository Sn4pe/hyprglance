import QtQuick
import Quickshell.Io

FileView {
  readonly property color surface: "#" + scheme.base00
  readonly property color raised: "#" + scheme.base01
  readonly property color outline: "#" + scheme.base02
  readonly property color muted: "#" + scheme.base04
  readonly property color text: "#" + scheme.base05
  readonly property color accent: "#" + scheme.base0D

  watchChanges: true
  printErrors: false
  onFileChanged: reload()

  JsonAdapter {
    id: scheme

    property string base00: "1e1e2e"
    property string base01: "313244"
    property string base02: "45475a"
    property string base04: "a6adc8"
    property string base05: "cdd6f4"
    property string base0D: "89b4fa"
  }
}
