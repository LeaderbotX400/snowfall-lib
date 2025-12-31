{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (builtins) baseNameOf concatStringsSep dirOf match toString;
  inherit (core-inputs.nixpkgs.lib) assertMsg init last;

  file-name-regex = "(.*)\\.(.*)$";
in
{
  path = rec {
    ## Split a file name and its extension.
    #@ String -> [String]
    split-file-extension = file:
      let result = match file-name-regex file;
      in assert assertMsg (result != null) "lib.snowfall.split-file-extension: File must have an extension to split.";
      result;

    ## Check if a file name has a file extension.
    #@ String -> Bool
    has-any-file-extension = file: match file-name-regex (toString file) != null;

    ## Get the file extension of a file name.
    #@ String -> String
    get-file-extension = file:
      if has-any-file-extension file
      then last (match file-name-regex (toString file))
      else "";

    ## Check if a file name has a specific file extension.
    #@ String -> String -> Bool
    has-file-extension = extension: file:
      has-any-file-extension file && extension == get-file-extension file;

    ## Get the parent directory for a given path.
    #@ Path -> Path
    get-parent-directory = snowfall-lib.fp.compose baseNameOf dirOf;

    ## Get the file name of a path without its extension.
    #@ Path -> String
    get-file-name-without-extension = path:
      let file-name = baseNameOf path;
      in if has-any-file-extension file-name
         then concatStringsSep "" (init (split-file-extension file-name))
         else file-name;
  };
}
