{ lib, ... }:
{
  fromYaml = import ./from-yaml.nix { inherit lib; };
}
