{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.my.nebius.npc.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install npc, the internal Nebius Private CLI.

      Its binary is fetched from artifactory.nebius.dev, which is only reachable
      over Tailscale. Nix cannot degrade gracefully here, a failed fetch is a
      build failure that takes the whole activation down, and eval is pure so it
      cannot probe the network to decide. Set this to false to switch while off
      the corporate network.

      In practice the fetch only happens on the first build, after a version
      bump, or if the store path is garbage collected: an installed npc is a GC
      root via the home-manager generation, so routine switches never refetch.
    '';
  };

  # Nebius AI Cloud tooling. Both CLIs are built from ../../../pkgs/nebius-cli
  # and reach this module via the overlay in ../../../overlays.
  config.home.packages = [
    # Public, customer-facing CLI. User-level operations.
    pkgs.nebius-cli

    pkgs.awscli2
    pkgs.kubectl

    # The Nebius API is gRPC-first. Anything the CLI doesn't wrap is reachable
    # with: grpcurl -H "Authorization: Bearer $(nebius iam get-access-token)"
    pkgs.grpcurl
  ]
  ++ lib.optional config.my.nebius.npc.enable pkgs.npc;
}
