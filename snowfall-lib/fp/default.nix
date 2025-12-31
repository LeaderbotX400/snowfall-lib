{
  core-inputs,
  user-inputs,
  snowfall-lib,
  snowfall-config,
}:
let
  inherit (core-inputs.nixpkgs.lib) flip foldr id;
in
{
  fp = rec {
    ## Compose two functions (right-to-left).
    #@ (b -> c) -> (a -> b) -> a -> c
    compose = f: g: x: f (g x);

    ## Compose many functions (right-to-left).
    #@ [(x -> y)] -> a -> b
    compose-all = foldr compose id;

    ## Call a function with an argument.
    #@ (a -> b) -> a -> b
    call = f: x: f x;

    ## Apply an argument to a function (flip of call).
    #@ a -> (a -> b) -> b
    apply = flip call;
  };
}
