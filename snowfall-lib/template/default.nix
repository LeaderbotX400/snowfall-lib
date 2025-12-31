{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (builtins) baseNameOf;
  inherit (core-inputs.nixpkgs.lib) foldl mapAttrs;

  user-templates-root = snowfall-lib.fs.get-snowfall-file "templates";
in
{
  template = {
    ## Create flake templates.
    #@ Attrs -> Attrs
    create-templates = {
      src ? user-templates-root,
      overrides ? {},
      alias ? {},
    }:
      let
        user-templates = snowfall-lib.fs.get-directories src;

        templates-without-aliases = foldl (acc: template:
          let
            name = builtins.unsafeDiscardStringContext (baseNameOf template);
            description = (import (template + "/flake.nix")).description;
          in
          acc // {
            ${name} = (overrides.${name} or {}) // {
              path = template;
              inherit description;
            };
          }
        ) {} user-templates;

        aliased-templates = mapAttrs (_: value: templates-without-aliases.${value}) alias;

        # Include overrides that aren't from discovered templates
        unused-overrides = builtins.removeAttrs overrides (
          builtins.map (t: builtins.unsafeDiscardStringContext (baseNameOf t)) user-templates
        );
      in
      templates-without-aliases // aliased-templates // unused-overrides;
  };
}