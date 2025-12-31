{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (builtins) baseNameOf;
  inherit (core-inputs.nixpkgs.lib) assertMsg concatMap fix foldl hasInfix optionals;

  virtual-systems = import ./virtual-systems.nix;

  user-systems-root = snowfall-lib.fs.get-snowfall-file "systems";
  user-modules-root = snowfall-lib.fs.get-snowfall-file "modules";
in
{
  system = rec {
    ## Get the name of a system based on its file path.
    #@ Path -> String
    get-inferred-system-name = path:
      if snowfall-lib.path.has-file-extension "nix" path
      then snowfall-lib.path.get-parent-directory path
      else baseNameOf path;

    ## Check whether a named system is macOS.
    #@ String -> Bool
    is-darwin = hasInfix "darwin";

    ## Check whether a named system is Linux.
    #@ String -> Bool
    is-linux = hasInfix "linux";

    ## Check whether a named system is virtual.
    #@ String -> Bool
    is-virtual = target: (get-virtual-system-type target) != "";

    ## Get the virtual system type of a system target.
    #@ String -> String
    get-virtual-system-type = target:
      foldl (result: vs: if result == "" && hasInfix vs target then vs else result) "" virtual-systems;

    ## Get structured data about all systems for a given target.
    #@ String -> [Attrs]
    get-target-systems-metadata = target:
      let
        systems = snowfall-lib.fs.get-directories target;
        existing = builtins.filter (s: builtins.pathExists "${s}/default.nix") systems;
      in
      builtins.map (path: {
        path = "${path}/default.nix";
        name = builtins.unsafeDiscardStringContext (baseNameOf path);
        target = builtins.unsafeDiscardStringContext (baseNameOf target);
      }) existing;

    ## Get the system builder for a given target.
    #@ String -> Function
    get-system-builder = target:
      let
        virtual-type = get-virtual-system-type target;

        virtual-builder = args:
          assert assertMsg (user-inputs ? nixos-generators)
            "In order to create virtual systems, you must include `nixos-generators` as a flake input.";
          user-inputs.nixos-generators.nixosGenerate (args // {
            format = virtual-type;
            specialArgs = args.specialArgs // { format = virtual-type; };
            modules = args.modules ++ [../../modules/nixos/user/default.nix];
          });

        darwin-builder = args:
          assert assertMsg (user-inputs ? darwin)
            "In order to create Darwin systems, you must include `darwin` as a flake input.";
          user-inputs.darwin.lib.darwinSystem ((builtins.removeAttrs args ["system" "modules"]) // {
            specialArgs = args.specialArgs // { format = "darwin"; };
            modules = args.modules ++ [../../modules/darwin/user/default.nix];
          });

        linux-builder = args:
          core-inputs.nixpkgs.lib.nixosSystem (args // {
            specialArgs = args.specialArgs // { format = "linux"; };
            modules = args.modules ++ [../../modules/nixos/user/default.nix];
          });
      in
      if virtual-type != "" then virtual-builder
      else if is-darwin target then darwin-builder
      else linux-builder;

    ## Get the flake output attribute for a system target.
    #@ String -> String
    get-system-output = target:
      let virtual-type = get-virtual-system-type target;
      in if virtual-type != "" then "${virtual-type}Configurations"
         else if is-darwin target then "darwinConfigurations"
         else "nixosConfigurations";

    ## Get the resolved (non-virtual) system target.
    #@ String -> String
    get-resolved-system-target = target:
      let virtual-type = get-virtual-system-type target;
      in if virtual-type != "" then builtins.replaceStrings [virtual-type] ["linux"] target
         else target;

    ## Create a system.
    #@ Attrs -> Attrs
    create-system = {
      target ? "x86_64-linux",
      system ? get-resolved-system-target target,
      path,
      name ? builtins.unsafeDiscardStringContext (get-inferred-system-name path),
      modules ? [],
      specialArgs ? {},
      channelName ? "nixpkgs",
      builder ? get-system-builder target,
      output ? get-system-output target,
      systems ? {},
      homes ? {},
    }:
      let
        lib = snowfall-lib.internal.system-lib;
        home-system-modules = snowfall-lib.home.create-home-system-modules homes;
        home-manager-module =
          if is-darwin system
          then user-inputs.home-manager.darwinModules.home-manager
          else user-inputs.home-manager.nixosModules.home-manager;
        home-manager-modules = [home-manager-module] ++ home-system-modules;
      in {
        inherit channelName system builder output;
        modules = [path] ++ modules ++ (optionals (user-inputs ? home-manager) home-manager-modules);
        specialArgs = specialArgs // {
          inherit target system systems lib;
          host = name;
          virtual = (get-virtual-system-type target) != "";
          inputs = snowfall-lib.flake.without-src user-inputs;
          namespace = snowfall-config.namespace;
        };
      };

    ## Create all available systems.
    #@ Attrs -> Attrs
    create-systems = { systems ? {}, homes ? {} }:
      let
        targets = snowfall-lib.fs.get-directories user-systems-root;
        target-systems-metadata = concatMap get-target-systems-metadata targets;

        user-nixos-modules = snowfall-lib.module.create-modules { src = "${user-modules-root}/nixos"; };
        user-darwin-modules = snowfall-lib.module.create-modules { src = "${user-modules-root}/darwin"; };

        nixos-modules = systems.modules.nixos or [];
        darwin-modules = systems.modules.darwin or [];

        create-system' = created: meta:
          let
            overrides = systems.hosts.${meta.name} or {};
            user-modules = if is-darwin meta.target then user-darwin-modules else user-nixos-modules;
            system-modules = if is-darwin meta.target then darwin-modules else nixos-modules;
          in {
            ${meta.name} = create-system (overrides // meta // {
              systems = created;
              modules = (builtins.attrValues user-modules) ++ (overrides.modules or []) ++ system-modules;
              inherit homes;
            });
          };

        created-systems = fix (created:
          foldl (acc: meta: acc // (create-system' created meta)) {} target-systems-metadata
        );
      in
      created-systems;
  };
}
