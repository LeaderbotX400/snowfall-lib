{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib) foldl hasPrefix isFunction mapAttrs;

  user-modules-root = snowfall-lib.fs.get-snowfall-file "modules";
in
{
  module = {
    ## Create flake output modules.
    #@ Attrs -> Attrs
    create-modules = {
      src ? "${user-modules-root}/nixos",
      overrides ? {},
      alias ? {},
    }:
      let
        user-modules = snowfall-lib.fs.get-default-nix-files-recursive src;

        # Extract module name from path
        get-module-name = module:
          let
            path-name = builtins.replaceStrings [(builtins.toString src) "/default.nix"] ["" ""]
              (builtins.unsafeDiscardStringContext module);
          in
          if hasPrefix "/" path-name
          then builtins.substring 1 ((builtins.stringLength path-name) - 1) path-name
          else path-name;

        modules-without-aliases = foldl (acc: module:
          let
            name = get-module-name module;
          in
          acc // {
            ${name} = args@{ pkgs, ... }:
              let
                system = args.system or args.pkgs.stdenv.hostPlatform.system;
                target = args.target or system;

                format =
                  let virtual-type = snowfall-lib.system.get-virtual-system-type target;
                  in if virtual-type != "" then virtual-type
                     else if snowfall-lib.system.is-darwin target then "darwin"
                     else "linux";

                modified-args = args // {
                  inherit system target format;
                  virtual = args.virtual or (snowfall-lib.system.get-virtual-system-type target != "");
                  systems = args.systems or {};
                  lib = snowfall-lib.internal.system-lib;
                  pkgs = user-inputs.self.pkgs.${system}.nixpkgs;
                  inputs = snowfall-lib.flake.without-src user-inputs;
                  namespace = snowfall-config.namespace;
                };

                imported = import module;
                result = if isFunction imported then imported modified-args else imported;
              in
              result // { _file = module; };
          }
        ) {} user-modules;

        aliased-modules = mapAttrs (_: value: modules-without-aliases.${value}) alias;
      in
      modules-without-aliases // aliased-modules // overrides;
  };
}
