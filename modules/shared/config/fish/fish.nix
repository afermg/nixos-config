# Shared interactive Fish configuration and the active plugin set.
{ pkgs, ... }:
{
  programs.fish = {
    enable = true;
    plugins =
      map
        (name: {
          inherit name;
          src = pkgs.fishPlugins.${name}.src;
        })
        [
          "pure"
          "autopair"
          "fishbang"
          "fish-you-should-use"
          "sponge"
          "async-prompt"
        ];
    interactiveShellInit = ''
      set --universal pure_enable_nixdevshell true
      set -gx FZF_DEFAULT_OPTS "--bind=alt-k:up,alt-j:down --expect=tab,enter --layout=reverse
        --height=17 --delimiter='\t' --with-nth=1
          --preview-window='border-rounded' --prompt='  ' --marker=' ' --pointer=' '
          --separator='─' --scrollbar='┃' --layout='reverse'
        "
    '';
  };
}
