{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (builtins) pathExists readDir;
  inherit (core-inputs.nixpkgs.lib) filterAttrs mapAttrsToList;
in
{
  fs = rec {
    ## Matchers for file kinds used with `readDir`.
    #@ String -> Bool
    is-file-kind = kind: kind == "regular";
    is-symlink-kind = kind: kind == "symlink";
    is-directory-kind = kind: kind == "directory";
    is-unknown-kind = kind: kind == "unknown";

    ## Get a file path relative to the user's flake.
    #@ String -> String
    get-file = path: "${user-inputs.src}/${path}";

    ## Get a file path relative to the user's snowfall directory.
    #@ String -> String
    get-snowfall-file = path: "${snowfall-config.root}/${path}";

    ## Get a file path relative to the core snowfall-lib flake.
    #@ String -> String
    internal-get-file = path: "${core-inputs.src}/${path}";

    ## Safely read from a directory if it exists.
    #@ Path -> Attrs
    safe-read-directory = path:
      if pathExists path then readDir path else {};

    ## Get directories at a given path.
    #@ Path -> [Path]
    get-directories = path:
      let
        entries = safe-read-directory path;
        dirs = filterAttrs (_: is-directory-kind) entries;
      in
      mapAttrsToList (name: _: "${path}/${name}") dirs;

    ## Get files at a given path.
    #@ Path -> [Path]
    get-files = path:
      let
        entries = safe-read-directory path;
        files = filterAttrs (_: is-file-kind) entries;
      in
      mapAttrsToList (name: _: "${path}/${name}") files;

    ## Get files at a given path, traversing any directories within.
    #@ Path -> [Path]
    get-files-recursive = path:
      let
        entries = safe-read-directory path;
        relevant = filterAttrs (_: kind: is-file-kind kind || is-directory-kind kind) entries;
      in
      snowfall-lib.attrs.map-concat-attrs-to-list (name: kind:
        let path' = "${path}/${name}";
        in if is-directory-kind kind then get-files-recursive path' else path'
      ) relevant;

    ## Get nix files at a given path.
    #@ Path -> [Path]
    get-nix-files = path:
      builtins.filter (snowfall-lib.path.has-file-extension "nix") (get-files path);

    ## Get nix files at a given path, traversing any directories within.
    #@ Path -> [Path]
    get-nix-files-recursive = path:
      builtins.filter (snowfall-lib.path.has-file-extension "nix") (get-files-recursive path);

    ## Get nix files at a given path named "default.nix".
    #@ Path -> [Path]
    get-default-nix-files = path:
      builtins.filter (name: builtins.baseNameOf name == "default.nix") (get-files path);

    ## Get nix files at a given path named "default.nix", traversing any directories within.
    #@ Path -> [Path]
    get-default-nix-files-recursive = path:
      builtins.filter (name: builtins.baseNameOf name == "default.nix") (get-files-recursive path);

    ## Get nix files at a given path not named "default.nix".
    #@ Path -> [Path]
    get-non-default-nix-files = path:
      builtins.filter (name:
        (snowfall-lib.path.has-file-extension "nix" name)
        && (builtins.baseNameOf name != "default.nix")
      ) (get-files path);

    ## Get nix files at a given path not named "default.nix", traversing any directories within.
    #@ Path -> [Path]
    get-non-default-nix-files-recursive = path:
      builtins.filter (name:
        (snowfall-lib.path.has-file-extension "nix" name)
        && (builtins.baseNameOf name != "default.nix")
      ) (get-files-recursive path);
  };
}
