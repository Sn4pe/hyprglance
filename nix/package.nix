{
  lib,
  stdenvNoCC,
  makeWrapper,
  quickshell,
}:

stdenvNoCC.mkDerivation {
  pname = "hyprglance";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../shell.qml
      ../Tile.qml
      ../Scheme.qml
      ../hyprglance.lua
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm644 -t $out/share/hyprglance *.qml hyprglance.lua
    makeWrapper ${lib.getExe quickshell} $out/bin/hyprglance \
      --add-flags "-p $out/share/hyprglance"
  '';

  meta = {
    description = "Mac-style window switcher for Hyprland, built on Quickshell";
    homepage = "https://github.com/Sn4pe/hyprglance";
    license = lib.licenses.gpl3Plus;
    mainProgram = "hyprglance";
    platforms = lib.platforms.linux;
  };
}
