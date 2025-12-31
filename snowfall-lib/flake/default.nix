{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib)
    const
    filterAttrs
    ;
in
{
  flake = rec {
    ## Remove the `self` attribute from an attribute set.
    #@ Attrs -> Attrs
    without-self = attrs: builtins.removeAttrs attrs ["self"];

    ## Remove the `src` attribute from an attribute set.
    #@ Attrs -> Attrs
    without-src = attrs: builtins.removeAttrs attrs ["src"];

    ## Remove the `src` and `self` attributes from an attribute set.
    #@ Attrs -> Attrs
    without-snowfall-inputs = snowfall-lib.fp.compose without-self without-src;

    ## Snowfall-specific options to remove before passing to flake-utils-plus.
    snowfall-option-names = [
      "systems"
      "modules"
      "overlays"
      "packages"
      "outputs-builder"
      "outputsBuilder"
      "packagesPrefix"
      "hosts"
      "homes"
      "channels-config"
      "templates"
      "checks"
      "alias"
      "snowfall"
    ];

    ## Remove Snowfall-specific attributes so the rest can be safely passed to flake-utils-plus.
    #@ Attrs -> Attrs
    without-snowfall-options = attrs: builtins.removeAttrs attrs snowfall-option-names;

    ## Extract `lib` attributes from inputs, filtering out entries without `lib`.
    #@ Attrs -> Attrs
    get-libs = attrs:
      let
        attrs-with-libs = filterAttrs (_: value: builtins.isAttrs (value.lib or null)) attrs;
      in
      builtins.mapAttrs (_: input: input.lib) attrs-with-libs;
  };

  mkFlake = full-flake-options:
    let
      namespace = snowfall-config.namespace or "internal";
      custom-flake-options = snowfall-lib.flake.without-snowfall-options full-flake-options;
      alias = full-flake-options.alias or {};

      # Build system and home configurations
      homes = snowfall-lib.home.create-homes (full-flake-options.homes or {});
      systems = snowfall-lib.system.create-systems {
        systems = full-flake-options.systems or {};
        homes = full-flake-options.homes or {};
      };
      hosts = snowfall-lib.attrs.merge-shallow [
        (full-flake-options.systems.hosts or {})
        systems
        homes
      ];

      # Build module exports
      templates = snowfall-lib.template.create-templates {
        overrides = full-flake-options.templates or {};
        alias = alias.templates or {};
      };
      nixos-modules = snowfall-lib.module.create-modules {
        src = snowfall-lib.fs.get-snowfall-file "modules/nixos";
        overrides = full-flake-options.modules.nixos or {};
        alias = alias.modules.nixos or {};
      };
      darwin-modules = snowfall-lib.module.create-modules {
        src = snowfall-lib.fs.get-snowfall-file "modules/darwin";
        overrides = full-flake-options.modules.darwin or {};
        alias = alias.modules.darwin or {};
      };
      home-modules = snowfall-lib.module.create-modules {
        src = snowfall-lib.fs.get-snowfall-file "modules/home";
        overrides = full-flake-options.modules.home or {};
        alias = alias.modules.home or {};
      };
      overlays = snowfall-lib.overlay.create-overlays {
        inherit namespace;
        extra-overlays = full-flake-options.extra-exported-overlays or {};
      };

      # Build per-system outputs
      outputs-builder = channels:
        let
          user-outputs-builder =
            full-flake-options.outputs-builder or full-flake-options.outputsBuilder or (const {});
          user-outputs = user-outputs-builder channels;

          packages = snowfall-lib.package.create-packages {
            inherit channels namespace;
            overrides = (full-flake-options.packages or {}) // (user-outputs.packages or {});
            alias = alias.packages or {};
          };
          shells = snowfall-lib.shell.create-shells {
            inherit channels;
            overrides = (full-flake-options.shells or {}) // (user-outputs.devShells or {});
            alias = alias.shells or {};
          };
          checks = snowfall-lib.check.create-checks {
            inherit channels;
            overrides = (full-flake-options.checks or {}) // (user-outputs.checks or {});
            alias = alias.checks or {};
          };
        in
        snowfall-lib.attrs.merge-deep [
          user-outputs
          { inherit packages checks; devShells = shells; }
        ];

      # Compose final flake options for flake-utils-plus
      flake-options = custom-flake-options // {
        inherit hosts templates;
        inherit (user-inputs) self;

        lib = snowfall-lib.internal.user-lib;
        inputs = snowfall-lib.flake.without-src user-inputs;

        nixosModules = nixos-modules;
        darwinModules = darwin-modules;
        homeModules = home-modules;

        channelsConfig = full-flake-options.channels-config or {};

        channels.nixpkgs.overlaysBuilder = snowfall-lib.overlay.create-overlays-builder {
          inherit namespace;
          extra-overlays = full-flake-options.overlays or [];
        };

        outputsBuilder = outputs-builder;

        snowfall = {
          config = snowfall-config;
          raw-config = full-flake-options.snowfall or {};
          user-lib = snowfall-lib.internal.user-lib;
        };
      };

      flake-utils-plus-outputs = core-inputs.flake-utils-plus.lib.mkFlake flake-options;
      flake-outputs = flake-utils-plus-outputs // { inherit overlays; };
    in
    flake-outputs // {
      # Extend packages with per-system attributes
      packages = flake-outputs.packages // (builtins.listToAttrs (
        builtins.map (system: {
          name = system;
          value = flake-outputs.packages.${system} // {};
        }) (builtins.attrNames flake-outputs.pkgs)
      ));
    };
}
