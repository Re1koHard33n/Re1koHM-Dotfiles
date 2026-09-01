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
    mozilla = ".config/mozilla";

    cursor = ".icons";
    themes = ".themes/Nordic";
    wallpapers = ".wallpapers";
    "gtk-3.0" = ".config/gtk-3.0";
    "gtk-4.0" = ".config/gtk-4.0";
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
