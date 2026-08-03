# NPC (Nebius Private CLI) — the internal CLI with advanced privileges. Same
# codebase as the public `nebius`, but a superset build: it adds ~40 internal
# command trees (breakglass, controlcenter, firewall, soperator, o11y, support,
# marketplace, …) and the --force-routing-code / --skip-tls-verification flags.
#
# Its config lives at ~/.config/newbius/, entirely separate from ~/.nebius/, so
# the two CLIs' profiles do not interact. Docs: https://docs.nebius.dev/en/cli
#
# The binary comes from internal Artifactory, which is only reachable over
# Tailscale — see my.nebius.npc.enable in
# home/nima/common/optional/nebius.nix for the off-network escape hatch.
#
# Only x86_64-linux is listed: peanut is the sole consumer, and each platform
# costs a ~150 MB prefetch to pin.
{ callPackage }:

callPackage ./generic.nix {
  pname = "npc";
  binName = "npc";
  version = "0.0.172";
  baseUrl = "https://artifactory.nebius.dev/artifactory/npc";

  sources = {
    x86_64-linux = {
      os = "linux";
      arch = "x86_64";
      hash = "sha256-SYJ1rsjaSGIEz6VDx5NRPyrPTayrElRa6EPDV4HXng0=";
    };
  };

  description = "Nebius Private CLI — internal CLI with advanced privileges";
  homepage = "https://docs.nebius.dev/en/cli";
}
