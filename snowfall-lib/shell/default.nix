{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.flake-utils-plus.lib) filterPackages;
  inherit (core-inputs.nixpkgs.lib) callPackageWith foldl mapAttrs;

  user-shells-root = snowfall-lib.fs.get-snowfall-file "shells";
in
{
  shell = {
    ## Create flake output dev shells.
    #@ Attrs -> Attrs
    create-shells = {
      channels,
      src ? user-shells-root,
      pkgs ? channels.nixpkgs,
      overrides ? {},
      alias ? {},
    }:
      let
        user-shells = snowfall-lib.fs.get-default-nix-files-recursive src;

        create-shell-metadata = shell:
          let
            extra-inputs = pkgs // {
              inherit channels;
              lib = snowfall-lib.internal.system-lib;
              inputs = snowfall-lib.flake.without-src user-inputs;
              namespace = snowfall-config.namespace;
            };
          in {
            name = builtins.unsafeDiscardStringContext (snowfall-lib.path.get-parent-directory shell);
            drv = callPackageWith extra-inputs shell {};
          };

        shells-metadata = builtins.map create-shell-metadata user-shells;

        shells-without-aliases = foldl (acc: meta: acc // { ${meta.name} = meta.drv; }) {} shells-metadata;
        aliased-shells = mapAttrs (_: value: shells-without-aliases.${value}) alias;
      in
      filterPackages pkgs.stdenv.hostPlatform.system (shells-without-aliases // aliased-shells // overrides);
  };
}
