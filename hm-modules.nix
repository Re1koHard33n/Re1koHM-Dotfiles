{ config, lib, dotfiles, ... }:
let
  cfg = config.re1ko.dotfiles;

  registry = {
    alacritty = ".config/alacritty";
    fish = ".config/fish";
    mangohud = ".config/MangoHud";
    niri = ".config/niri";
    starship = ".config/starship.toml";
    zsh = ".zshrc";
  };
in
{
  options.re1ko.dotfiles.packages = lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames registry));
    default = [ ];
    example = [ "fish" "starship" "alacritty" ];
    description = "Dotfiles packages deployment in this machine";
  };

  config.home.file = lib.listToAttrs (map
  (name:
    let target = registry.${name};
    in lib.nameValuePair target {
      source = "${dotfiles}/${name}/${target}";
      recursive = true;
    })
  cfg.packages);
}