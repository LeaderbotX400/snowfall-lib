{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.flake-utils-plus.lib) filterPackages;
  inherit (core-inputs.nixpkgs.lib) callPackageWith foldl mapAttrs;

  user-packages-root = snowfall-lib.fs.get-snowfall-file "packages";
in
{
  package = {
    ## Create flake output packages.
    #@ Attrs -> Attrs
    create-packages = {
      channels,
      src ? user-packages-root,
      pkgs ? channels.nixpkgs,
      overrides ? {},
      alias ? {},
      namespace ? snowfall-config.namespace,
    }:
      let
        user-packages = snowfall-lib.fs.get-default-nix-files-recursive src;

        # Build packages-without-aliases first for namespace reference
        packages-without-aliases = foldl (acc: pkg:
          let
            name = builtins.unsafeDiscardStringContext (snowfall-lib.path.get-parent-directory pkg);
            namespaced-packages = { ${namespace} = acc; };
            extra-inputs = pkgs // namespaced-packages // {
              inherit channels namespace;
              lib = snowfall-lib.internal.system-lib;
              pkgs = pkgs // namespaced-packages;
              inputs = user-inputs;
            };
            drv = callPackageWith extra-inputs pkg {};
          in
          acc // {
            ${name} = drv // {
              meta = (drv.meta or {}) // {
                snowfall.path = pkg;
              };
            };
          }
        ) {} user-packages;

        aliased-packages = mapAttrs (_: value: packages-without-aliases.${value}) alias;
      in
      filterPackages pkgs.stdenv.hostPlatform.system (packages-without-aliases // aliased-packages // overrides);
  };
}
