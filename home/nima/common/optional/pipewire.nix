{ pkgs, lib, ... }:

let
  # Everything except wireplumber.service lives in the pipewire package.
  pipewireUnits = [
    "pipewire.service"
    "pipewire.socket"
    "pipewire-pulse.service"
    "pipewire-pulse.socket"
    "filter-chain.service"
  ];
in
{
  # PipeWire from nixpkgs on a non-NixOS host (Ubuntu 24.04).
  #
  # Ubuntu noble ships PipeWire 1.0.5 / WirePlumber 0.4.17 and, being an LTS,
  # never will ship newer. That stack handles abrupt device removal badly: a
  # USB-C monitor is a DP-audio sink plus a USB hub (mic and friends), and
  # unplugging it removes all of them mid-stream — 1.0.5 then wedges the whole
  # graph (clock stalls, XRUN loops, clients frozen), which froze video and
  # produced clicking until streams were moved. Fixed upstream in the 1.2+
  # releases, so run nixpkgs' pipewire/wireplumber as the session audio stack.
  #
  # Mechanism: the nix packages ship complete systemd user units whose
  # ExecStart points into the store. Symlinking them into
  # ~/.config/systemd/user shadows Ubuntu's identically-named units (user
  # config dir beats /usr/lib/systemd/user), and the distro's enablement
  # symlinks still apply because systemd resolves them by unit *name*. Apt
  # apps don't notice: they speak the (stable) native protocol over the same
  # %t/pipewire-0 and pulse sockets, and realtime priority still comes from
  # Ubuntu's rtkit over D-Bus.
  #
  # After a switch that changes these units:
  #   systemctl --user daemon-reload
  #   systemctl --user restart pipewire.socket pipewire-pulse.socket \
  #     pipewire.service pipewire-pulse.service wireplumber.service filter-chain.service
  xdg.configFile =
    lib.listToAttrs (
      map (unit: {
        name = "systemd/user/${unit}";
        value.source = "${pkgs.pipewire}/lib/systemd/user/${unit}";
      }) pipewireUnits
    )
    // {
      "systemd/user/wireplumber.service".source =
        "${pkgs.wireplumber}/lib/systemd/user/wireplumber.service";
    };

  # CLI tools (pw-cli, pw-top, wpctl, ...) matching the running server, so
  # diagnostics don't come from Ubuntu's older client tools.
  home.packages = [
    pkgs.pipewire
    pkgs.wireplumber
  ];
}
