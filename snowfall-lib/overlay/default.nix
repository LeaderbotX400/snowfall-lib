{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib) foldl;

  user-overlays-root = snowfall-lib.fs.get-snowfall-file "overlays";
  user-packages-root = snowfall-lib.fs.get-snowfall-file "packages";

  # Fake pkgs for testing overlay export status
  fake-pkgs = {
    callPackage = x: x;
    isFakePkgs = true;
    lib = {};
    system = "fake-system";
  };
in
{
  overlay = {
    ## Create a flake-utils-plus overlays builder.
    #@ Attrs -> Attrs -> [(a -> b -> c)]
    create-overlays-builder = {
      src ? user-overlays-root,
      namespace ? snowfall-config.namespace,
      extra-overlays ? [],
    }: channels:
      let
        user-overlays = snowfall-lib.fs.get-default-nix-files-recursive src;

        create-overlay = overlay: import overlay (user-inputs // {
          inherit channels;
          inherit (snowfall-config) namespace;
          inputs = user-inputs;
          lib = snowfall-lib.internal.system-lib;
        });

        user-packages-overlay = final: prev:
          let
            user-packages = snowfall-lib.package.create-packages {
              pkgs = final;
              inherit channels namespace;
            };
          in {
            ${namespace} = (prev.${namespace} or {}) // user-packages;
          };
      in
      [user-packages-overlay] ++ extra-overlays ++ (builtins.map create-overlay user-overlays);

    ## Create exported overlays from the user flake.
    ## Adapted from flake-utils-plus.
    #@ Attrs -> Attrs
    create-overlays = {
      src ? user-overlays-root,
      packages-src ? user-packages-root,
      namespace ? snowfall-config.namespace,
      extra-overlays ? {},
    }:
      let
        user-overlays = snowfall-lib.fs.get-default-nix-files-recursive src;
        channel-systems = user-inputs.self.pkgs;

        # Overlay that adds user packages under namespace
        user-packages-overlay = final: prev:
          let
            user-packages = snowfall-lib.package.create-packages {
              pkgs = final;
              channels = channel-systems.${prev.system};
              inherit namespace;
            };
          in
          if namespace == null then user-packages
          else { ${namespace} = (prev.${namespace} or {}) // user-packages; };

        # Create an exported overlay from a file
        create-overlay = overlays: file:
          let
            name = builtins.unsafeDiscardStringContext (snowfall-lib.path.get-parent-directory file);

            overlay = final: prev:
              let
                channels = channel-systems.${prev.system};
                user-overlay = import file (user-inputs // {
                  inherit channels namespace;
                  inputs = user-inputs;
                  lib = snowfall-lib.internal.system-lib;
                });

                packages = user-packages-overlay final prev;
                prev-with-packages =
                  if namespace == null then prev // packages
                  else prev // { ${namespace} = (prev.${namespace} or {}) // packages.${namespace}; };

                result = user-overlay final prev-with-packages;
              in
              if result.__dontExport or false then result // { __dontExport = true; }
              else result;

            fake-result = overlay fake-pkgs fake-pkgs;
          in
          if fake-result.__dontExport or false then overlays
          else overlays // { ${name} = overlay; };

        overlays = foldl create-overlay {} user-overlays;

        # Create per-package overlays
        user-packages = snowfall-lib.fs.get-default-nix-files-recursive packages-src;

        create-package-overlay = acc: file:
          let
            name = builtins.unsafeDiscardStringContext (snowfall-lib.path.get-parent-directory file);
            overlay = final: prev:
              let
                packages = snowfall-lib.package.create-packages {
                  inherit namespace;
                  channels = channel-systems.${prev.system};
                };
              in
              if namespace == null then { ${name} = packages.${name}; }
              else { ${namespace} = (prev.${namespace} or {}) // { ${name} = packages.${name}; }; };
          in
          acc // { "package/${name}" = overlay; };

        package-overlays = foldl create-package-overlay {} user-packages;

        # Default overlay combines all overlays
        default-overlay = final: prev:
          let
            overlays-results = builtins.map (o: o final prev) (builtins.attrValues overlays);
            package-results = builtins.map (o: o final prev) (builtins.attrValues package-overlays);
          in
          snowfall-lib.attrs.merge-shallow-packages (package-results ++ overlays-results);
      in
      package-overlays // overlays // { default = default-overlay; } // extra-overlays;
  };
}