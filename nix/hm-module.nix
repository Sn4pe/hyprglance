self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.hyprglance;
  json = pkgs.formats.json { };
in
{
  options.programs.hyprglance = {
    enable = lib.mkEnableOption "hyprglance, a window switcher for Hyprland";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The hyprglance package to use.";
    };

    settings = lib.mkOption {
      type = json.type;
      default = { };
      example = {
        scope = "all";
        thumbnailWidth = 200;
      };
      description = "Written to {file}`$XDG_CONFIG_HOME/hyprglance/config.json`.";
    };

    luaModule = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${cfg.package}/share/hyprglance/hyprglance.lua";
      description = ''
        Path to the Hyprland Lua module, for use in your Hyprland config:
        `dofile("''${config.programs.hyprglance.luaModule}").setup()`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."hyprglance/config.json" = lib.mkIf (cfg.settings != { }) {
      source = json.generate "hyprglance-config.json" cfg.settings;
    };

    systemd.user.services.hyprglance = {
      Unit = {
        Description = "hyprglance window switcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
