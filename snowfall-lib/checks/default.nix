{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.flake-utils-plus.lib) filterPackages;
  inherit (core-inputs.nixpkgs.lib) callPackageWith foldl mapAttrs;

  user-checks-root = snowfall-lib.fs.get-snowfall-file "checks";
in
{
  check = {
    ## Create flake output checks.
    #@ Attrs -> Attrs
    create-checks = {
      channels,
      src ? user-checks-root,
      pkgs ? channels.nixpkgs,
      overrides ? {},
      alias ? {},
    }:
      let
        user-checks = snowfall-lib.fs.get-default-nix-files-recursive src;

        create-check-metadata = check:
          let
            extra-inputs = pkgs // {
              inherit channels;
              lib = snowfall-lib.internal.system-lib;
              inputs = snowfall-lib.flake.without-src user-inputs;
              namespace = snowfall-config.namespace;
            };
          in {
            name = builtins.unsafeDiscardStringContext (snowfall-lib.path.get-parent-directory check);
            drv = callPackageWith extra-inputs check {};
          };

        checks-metadata = builtins.map create-check-metadata user-checks;

        checks-without-aliases = foldl (acc: meta: acc // { ${meta.name} = meta.drv; }) {} checks-metadata;
        aliased-checks = mapAttrs (_: value: checks-without-aliases.${value}) alias;
      in
      filterPackages pkgs.stdenv.hostPlatform.system (checks-without-aliases // aliased-checks // overrides);
  };
}
