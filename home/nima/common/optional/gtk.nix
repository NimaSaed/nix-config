{
  config,
  pkgs,
  lib,
  ...
}:

let
  dark = config.my.polarity == "dark";
in
{
  # ===========================================================================
  # GTK theming — follows the active theme's polarity
  # ===========================================================================
  # GTK (and especially libadwaita) won't accept an arbitrary palette, so this
  # tracks light/dark only, driven by my.polarity (see common/core/theme.nix):
  #   - GTK2/3 apps (pavucontrol, wdisplays, …) read the theme name + the
  #     prefer-dark flag from the generated settings.ini.
  #   - GTK4/libadwaita apps (nautilus) and Electron/Chromium apps (Slack,
  #     Bitwarden) read `color-scheme` from the desktop portal's Settings
  #     interface. The portal's gtk backend answers it from the gsettings value
  #     set below — but only once a backend is routed to serve Settings under
  #     sway (peanut: user portals.conf; hazelnut: NixOS xdg.portal.config).
  #   - Qt5 apps (Zoom) ignore all of this; their theme lives in-app.
  # Icons use Papirus to match the notification daemon (dunst).
  gtk = {
    enable = true;
    theme = {
      name = if dark then "Adwaita-dark" else "Adwaita";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = if dark then 1 else 0;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = if dark then 1 else 0;
  };

  # gsettings mirror of the preference; the portal's gtk backend reads this to
  # answer color-scheme for GTK4/libadwaita and Electron/Chromium apps.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = if dark then "prefer-dark" else "prefer-light";
    gtk-theme = if dark then "Adwaita-dark" else "Adwaita";
  };
}
