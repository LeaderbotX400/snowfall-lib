args@{
  pkgs,
  lib,
  options,
  config,
  ...
}:
let
  inherit (lib) mkDefault mkIf mkOption types;

  cfg = config.snowfallorg;

  # Get osConfig safely (may not exist in standalone home-manager)
  os-user-home = args.osConfig.users.users.${cfg.user.name}.home or null;
  has-user-name = (cfg.user.name or null) != null;

  default-home-directory =
    if os-user-home != null then os-user-home
    else if pkgs.stdenv.isDarwin then "/Users/${cfg.user.name}"
    else "/home/${cfg.user.name}";
in
{
  options.snowfallorg.user = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to configure the user.";
    };

    name = mkOption {
      type = types.str;
      description = "The user's name.";
    };

    home.directory = mkOption {
      type = types.str;
      description = "The user's home directory.";
      default = default-home-directory;
    };
  };

  config = mkIf cfg.user.enable {
    home = {
      username = mkIf has-user-name (mkDefault cfg.user.name);
      homeDirectory = mkIf has-user-name (mkDefault cfg.user.home.directory);
    };
  };
}
