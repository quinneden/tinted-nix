{
  description = "Tinted-theming's base16 & base24 colorschemes as nix flake outputs.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    schemes = {
      url = "github:tinted-theming/schemes";
      flake = false;
    };
  };

  outputs =
    { ... }@inputs:
    let
      lib = inputs.nixpkgs.lib.extend (self: super: import ./lib { inherit (inputs.nixpkgs) lib; });

      base16 =
        with lib;
        let
          source = inputs.schemes + "/base16/";
          names = map (scheme: replaceStrings [ ".yml" ".yaml" ] [ "" "" ] scheme) yamls;
          paths = map (yaml: source + yaml) yamls;
          yamls = filter (name: (hasSuffix ".yml" name) || (hasSuffix ".yaml" name)) (
            attrNames (builtins.readDir source)
          );
          attrsList = (
            zipListsWith (name: path: {
              ${name} = fromYaml (readFile path);
            }) names paths
          );
        in
        foldl recursiveUpdate { } attrsList;

      base24 =
        with lib;
        let
          source = inputs.schemes + "/base24/";
          names = map (scheme: replaceStrings [ ".yml" ".yaml" ] [ "" "" ] scheme) yamls;
          paths = map (yaml: source + yaml) yamls;
          yamls = filter (name: (hasSuffix ".yml" name) || (hasSuffix ".yaml" name)) (
            attrNames (builtins.readDir source)
          );
          attrsList = (
            zipListsWith (name: path: {
              ${name} = fromYaml (readFile path);
            }) names paths
          );
        in
        foldl recursiveUpdate { } attrsList;
    in
    {
      inherit lib;
      schemes = { inherit base16 base24; };
    };
}
