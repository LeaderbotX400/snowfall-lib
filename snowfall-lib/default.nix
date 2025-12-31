# Snowfall Lib Bootstrap
#
# This file initializes the Snowfall library by:
# 1. Merging configuration from core and user inputs
# 2. Loading all library sub-modules from snowfall-lib directories
# 3. Building the extended library with user-defined functions
#
# Note: Some code is duplicated with internal/default.nix to handle
# the bootstrapping phase before the full library is available.
core-inputs: user-options:
let
  # Extract and normalize snowfall configuration
  raw-snowfall-config = user-options.snowfall or {};
  snowfall-config = raw-snowfall-config // {
    src = user-options.src;
    root = raw-snowfall-config.root or user-options.src;
    namespace = raw-snowfall-config.namespace or "internal";
    meta = {
      name = raw-snowfall-config.meta.name or null;
      title = raw-snowfall-config.meta.title or null;
    };
  };

  # Merge user inputs with source path
  user-inputs = user-options.inputs // { src = user-options.src; };

  inherit (core-inputs.nixpkgs.lib)
    assertMsg
    callPackageWith
    filterAttrs
    fix
    foldr
    isFunction
    mergeAttrs
    recursiveUpdate
    ;

  # Recursively merge a list of attribute sets (right-to-left precedence)
  # Type: [Attrs] -> Attrs
  merge-deep = foldr recursiveUpdate {};

  # Merge the root of a list of attribute sets (right-to-left precedence)
  # Type: [Attrs] -> Attrs
  merge-shallow = foldr mergeAttrs {};

  # Extract `lib` attributes from inputs, filtering out entries without `lib`
  # Type: Attrs -> Attrs
  get-libs = attrs:
    let
      attrs-with-libs = filterAttrs (_: value: builtins.isAttrs (value.lib or null)) attrs;
    in
    builtins.mapAttrs (_: input: input.lib) attrs-with-libs;

  # Remove the `self` attribute from an attribute set
  # Type: Attrs -> Attrs
  without-self = attrs: builtins.removeAttrs attrs ["self"];

  # Collect library exports from inputs
  core-inputs-libs = get-libs (without-self core-inputs);
  user-inputs-libs = get-libs (without-self user-inputs);

  # Build the snowfall library from all sub-modules
  snowfall-lib-root = "${core-inputs.src}/snowfall-lib";
  snowfall-lib-dirs =
    let
      files = builtins.readDir snowfall-lib-root;
      dirs = filterAttrs (_: kind: kind == "directory") files;
    in
    builtins.attrNames dirs;

  snowfall-lib = fix (self:
    let
      attrs = {
        snowfall-lib = self;
        inherit snowfall-config core-inputs user-inputs;
      };
    in
    merge-deep (builtins.map (dir: import "${snowfall-lib-root}/${dir}" attrs) snowfall-lib-dirs)
  );

  # Extract non-attribute values for top-level lib exposure
  snowfall-top-level-lib = filterAttrs (_: value: !builtins.isAttrs value) snowfall-lib;

  # Compose the base library from all sources
  base-lib = merge-shallow [
    core-inputs.nixpkgs.lib
    core-inputs-libs
    user-inputs-libs
    snowfall-top-level-lib
    { snowfall = snowfall-lib; }
  ];

  # Load and compose user-defined library functions
  user-lib-root = "${user-inputs.src}/lib";
  user-lib-modules = snowfall-lib.fs.get-default-nix-files-recursive user-lib-root;

  user-lib = fix (self:
    let
      attrs = {
        inherit (user-options) inputs;
        snowfall-inputs = core-inputs;
        namespace = snowfall-config.namespace;
        lib = merge-shallow [base-lib { ${snowfall-config.namespace} = self; }];
      };
    in
    merge-deep (builtins.map (path:
      let
        imported = import path;
      in
      if isFunction imported
      then callPackageWith attrs path {}
      else imported
    ) user-lib-modules)
  );

  # Final library composition
  lib = merge-deep [base-lib user-lib];

  # Validation
  user-inputs-has-self = builtins.elem "self" (builtins.attrNames user-inputs);
  user-inputs-has-src = builtins.elem "src" (builtins.attrNames user-inputs);
in
assert assertMsg user-inputs-has-self "Missing attribute `self` for mkLib.";
assert assertMsg user-inputs-has-src "Missing attribute `src` for mkLib.";
lib
