{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib)
    assertMsg
    concatMap
    foldl
    hasInfix
    head
    mapAttrsToList
    mkAliasAndWrapDefinitions
    mkDefault
    mkIf
    ;

  user-homes-root = snowfall-lib.fs.get-snowfall-file "homes";
  user-modules-root = snowfall-lib.fs.get-snowfall-file "modules";
in
{
  home = rec {
    ## Extended lib for home-manager with `hm` available at top level.
    home-lib =
      if user-inputs ? home-manager then
        snowfall-lib.internal.system-lib.extend (final: prev:
          snowfall-lib.internal.system-lib // prev // {
            hm = snowfall-lib.internal.system-lib.home-manager.hm;
          }
        )
      else {};

    ## Parse user@host format into components.
    #@ String -> Attrs
    split-user-and-host = target:
      let
        parts = builtins.filter builtins.isString (builtins.split "@" target);
        user = builtins.elemAt parts 0;
        host = if builtins.length parts > 1 then builtins.elemAt parts 1 else "";
      in { inherit user host; };

    ## Create a home configuration.
    #@ Attrs -> Attrs
    create-home = {
      path,
      name ? builtins.unsafeDiscardStringContext (snowfall-lib.system.get-inferred-system-name path),
      modules ? [],
      specialArgs ? {},
      channelName ? "nixpkgs",
      system ? "x86_64-linux",
    }:
      let
        user-metadata = split-user-and-host name;
        unique-name = if user-metadata.host == "" then "${user-metadata.user}@${system}" else name;

        pkgs = user-inputs.self.pkgs.${system}.${channelName} // { lib = home-lib; };
        lib = home-lib;
      in
      assert assertMsg (user-inputs ? home-manager)
        "In order to create home-manager configurations, you must include `home-manager` as a flake input.";
      assert assertMsg ((user-metadata.host != "") || !(hasInfix "@" name))
        "Snowfall Lib homes must be named with the format: user@system";
      {
        inherit channelName system;
        output = "homeConfigurations";

        modules = [
          path
          ../../modules/home/user/default.nix
        ] ++ modules;

        specialArgs = {
          inherit system;
          name = unique-name;
          inherit (user-metadata) user host;
          format = "home";
          inputs = snowfall-lib.flake.without-src user-inputs;
          namespace = snowfall-config.namespace;
          inherit pkgs lib;
        };

        builder = args:
          user-inputs.home-manager.lib.homeManagerConfiguration (
            (builtins.removeAttrs args ["system" "specialArgs"]) // {
              inherit pkgs lib;
              modules = args.modules ++ [
                (module-args: import ./nix-registry-module.nix (module-args // {
                  inherit user-inputs core-inputs;
                }))
                {
                  snowfallorg.user = {
                    name = mkDefault user-metadata.user;
                    enable = mkDefault true;
                  };
                }
              ];
              extraSpecialArgs = specialArgs // args.specialArgs;
            }
          );
      };

    ## Get structured data about all homes for a given target.
    #@ String -> [Attrs]
    get-target-homes-metadata = target:
      let
        homes = snowfall-lib.fs.get-directories target;
        existing = builtins.filter (h: builtins.pathExists "${h}/default.nix") homes;
      in
      builtins.map (path:
        let
          basename = builtins.unsafeDiscardStringContext (builtins.baseNameOf path);
          system = builtins.unsafeDiscardStringContext (builtins.baseNameOf target);
          name = if !(hasInfix "@" basename) then "${basename}@${system}" else basename;
        in {
          path = "${path}/default.nix";
          inherit name system;
        }
      ) existing;

    ## Create all available homes.
    #@ Attrs -> Attrs
    create-homes = homes:
      let
        targets = snowfall-lib.fs.get-directories user-homes-root;
        target-homes-metadata = concatMap get-target-homes-metadata targets;

        user-home-modules = snowfall-lib.module.create-modules {
          src = "${user-modules-root}/home";
        };

        user-home-modules-list = mapAttrsToList (module-path: module:
          args@{ pkgs, ... }: (module args) // {
            _file = "${user-homes-root}/${module-path}/default.nix";
          }
        ) user-home-modules;

        # Find base home configuration for inheritance
        find-base-home = home-metadata:
          let
            user-metadata = split-user-and-host home-metadata.name;
            has-hostname = user-metadata.host != "";
            base-name = "${user-metadata.user}@${home-metadata.system}";
            base-home = builtins.filter (h: h.name == base-name) target-homes-metadata;
          in
          if has-hostname && (builtins.length base-home) > 0
          then builtins.head base-home
          else null;

        create-home' = home-metadata:
          let
            inherit (home-metadata) name;
            overrides = homes.users.${name} or {};
            base-home = find-base-home home-metadata;

            # Import base first if it exists for proper inheritance
            path-with-base =
              if base-home != null then { imports = [base-home.path home-metadata.path]; }
              else home-metadata.path;
          in {
            ${name} = create-home (overrides // home-metadata // {
              path = path-with-base;
              modules = user-home-modules-list
                ++ (homes.users.${name}.modules or [])
                ++ (homes.modules or []);
            });
          };
      in
      foldl (acc: meta: acc // (create-home' meta)) {} target-homes-metadata;

    ## Create system modules for home-manager integration.
    #@ Attrs -> [Module]
    create-home-system-modules = users:
      let
        created-users = create-homes users;
        user-home-modules = snowfall-lib.module.create-modules {
          src = "${user-modules-root}/home";
        };

        shared-modules = builtins.map (module: {
          config.home-manager.sharedModules = [module];
        }) (users.modules or []);

        shared-user-modules = mapAttrsToList (module-path: module: {
          _file = "${user-modules-root}/home/${module-path}/default.nix";
          config.home-manager.sharedModules = [module];
        }) user-home-modules;

        snowfall-user-home-module = {
          _file = "virtual:snowfallorg/modules/home/user/default.nix";
          config.home-manager.sharedModules = [../../modules/home/user/default.nix];
        };

        extra-special-args-module = args@{
          config,
          pkgs,
          system ? pkgs.stdenv.hostPlatform.system,
          target ? system,
          format ? "home",
          host ? "",
          virtual ? (snowfall-lib.system.is-virtual target),
          systems ? {},
          ...
        }: {
          _file = "virtual:snowfallorg/home/extra-special-args";
          config.home-manager.extraSpecialArgs = {
            inherit system target format virtual systems host;
            inherit (snowfall-config) namespace;
            lib = home-lib;
            inputs = snowfall-lib.flake.without-src user-inputs;
          };
        };

        # Create per-user system modules
        system-modules = builtins.map (name:
          let
            created-user = created-users.${name};
            user-module = head created-user.modules;
            other-modules = users.users.${name}.modules or [];
            user-name = created-user.specialArgs.user;
            user-has-hostname = created-user.specialArgs.host != "";
          in
          args@{ config, options, pkgs, host ? "", system ? pkgs.stdenv.hostPlatform.system, ... }:
          let
            host-matches =
              (name == "${user-name}@${host}")
              || (config.snowfallorg.useGlobalUsers && name == "${user-name}@${system}");

            wrap-user-options = user-option:
              if (user-option ? "_type") && user-option._type == "merge" then
                user-option // {
                  contents = builtins.map (entry: entry.${user-name}.home.config or {}) user-option.contents;
                }
              else
                (builtins.trace ''
                  Snowfall Lib: Option value for `snowfallorg.users.${user-name}` was not detected to be merged.
                  Please report: https://github.com/snowfallorg/lib/issues/new
                '') user-option;

            home-config = mkAliasAndWrapDefinitions wrap-user-options options.snowfallorg.users;
          in {
            _file = "virtual:snowfallorg/home/user/${name}";
            config = mkIf host-matches {
              snowfallorg.users.${user-name} = {
                create = mkDefault user-has-hostname;
                home.config = {
                  snowfallorg.user = {
                    enable = mkDefault true;
                    name = mkDefault user-name;
                  };
                  _module.args = builtins.removeAttrs (
                    (users.users.${name}.specialArgs or {}) // { namespace = snowfall-config.namespace; }
                  ) ["options" "config" "lib" "pkgs" "specialArgs" "host"];
                };
              };

              home-manager = {
                users.${user-name} = mkIf config.snowfallorg.users.${user-name}.home.enable (
                  { pkgs, ... }: {
                    imports = (home-config.imports or []) ++ other-modules ++ [user-module];
                    config = builtins.removeAttrs home-config ["imports"];
                  }
                );
                useGlobalPkgs = mkDefault true;
              };
            };
          }
        ) (builtins.attrNames created-users);
      in
      [extra-special-args-module snowfall-user-home-module]
      ++ shared-modules
      ++ shared-user-modules
      ++ system-modules;
  };
}
