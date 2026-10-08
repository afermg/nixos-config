# Seed editable scenes once; never overwrite subsequent HA visual-editor changes.
{ lib, ... }:
{
  services.home-assistant.config."scene ui" = "!include /var/lib/hass/scenes.yaml";

  systemd.services.home-assistant.preStart = lib.mkAfter ''
    if [ ! -e /var/lib/hass/scenes.yaml ] && [ ! -L /var/lib/hass/scenes.yaml ]; then
      install -m 0600 ${./lighting-scenes-defaults.json} /var/lib/hass/scenes.yaml
    fi
  '';
}
