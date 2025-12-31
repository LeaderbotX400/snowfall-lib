{
  pkgs,
  lib,
  config,
  inputs ? {},
  ...
}:
let
  inherit (lib)
    foldl
    mkDefault
    mkOption
    mkRenamedOptionModule
    optionalAttrs
    types
    ;

  cfg = config.snowfallorg;
  user-names = builtins.attrNames cfg.users;

  create-system-users = system-users: name:
    let user = cfg.users.${name};
    in system-users // (optionalAttrs user.create {
      ${name} = {
        home = mkDefault user.home.path;
        isHidden = mkDefault false;
      };
    });
in
{
  imports = [
    (mkRenamedOptionModule ["snowfallorg" "user"] ["snowfallorg" "users"])
  ];

  options.snowfallorg = {
    useGlobalUsers = mkOption {
      description = "Whether to create system users for all defined users.";
      type = types.bool;
      default = false;
    };

    users = mkOption {
      description = "User configuration.";
      default = {};
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          create = mkOption {
            description = "Whether to create the user automatically.";
            type = types.bool;
            default = true;
          };

          admin = mkOption {
            description = "Whether the user should be added to the admin group.";
            type = types.bool;
            default = false;
          };

          home = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };

            path = mkOption {
              type = types.str;
              default = "/Users/${name}";
            };

            config = mkOption {
              type = types.submoduleWith {
                specialArgs = {
                  osConfig = config;
                  modulesPath = "${inputs.home-manager or "/"}/modules";
                } // (config.home-manager.extraSpecialArgs or {});
                modules = [
                  ({ lib, modulesPath, ... }:
                    if inputs ? home-manager then {
                      imports = import "${modulesPath}/modules.nix" {
                        inherit pkgs lib;
                        useNixpkgsModule = !(config.home-manager.useGlobalPkgs or false);
                      };
                      config = {
                        submoduleSupport.enable = true;
                        submoduleSupport.externalPackageInstall = config.home-manager.useUserPackages or false;
                        home.username = config.users.users.${name}.name;
                        home.homeDirectory = config.users.users.${name}.home;
                        nix.package = config.nix.package;
                      };
                    } else {}
                  )
                ] ++ (config.home-manager.sharedModules or []);
              };
            };
          };
        };
      }));
    };
  };

  config = {
    users.users = foldl create-system-users {} user-names;
  };
}
