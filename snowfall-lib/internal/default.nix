{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib) callPackageWith filterAttrs fix isFunction;

  # Collect library exports from inputs
  core-inputs-libs = snowfall-lib.flake.get-libs (snowfall-lib.flake.without-self core-inputs);
  user-inputs-libs = snowfall-lib.flake.get-libs (snowfall-lib.flake.without-self user-inputs);

  # Extract non-attribute values for top-level lib exposure
  snowfall-top-level-lib = filterAttrs (_: value: !builtins.isAttrs value) snowfall-lib;

  # Compose the base library from all sources
  base-lib = snowfall-lib.attrs.merge-shallow [
    core-inputs.nixpkgs.lib
    core-inputs-libs
    user-inputs-libs
    snowfall-top-level-lib
    { snowfall = snowfall-lib; }
  ];

  # Load and compose user-defined library functions
  user-lib-root = snowfall-lib.fs.get-snowfall-file "lib";
  user-lib-modules = snowfall-lib.fs.get-default-nix-files-recursive user-lib-root;

  user-lib = fix (self:
    let
      attrs = {
        inputs = snowfall-lib.flake.without-snowfall-inputs user-inputs;
        snowfall-inputs = core-inputs;
        namespace = snowfall-config.namespace;
        lib = snowfall-lib.attrs.merge-shallow [
          base-lib
          { ${snowfall-config.namespace} = self; }
        ];
      };
    in
    snowfall-lib.attrs.merge-deep (builtins.map (path:
      let imported = import path;
      in if isFunction imported then callPackageWith attrs path {} else imported
    ) user-lib-modules)
  );

  # Final system library with user extensions
  system-lib = snowfall-lib.attrs.merge-shallow [
    base-lib
    { ${snowfall-config.namespace} = user-lib; }
  ];
in
{
  internal = {
    inherit system-lib user-lib;
  };
}
