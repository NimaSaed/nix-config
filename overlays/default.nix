# Overlays allow you to modify or add packages to nixpkgs
# Example usage:
#   overlays.default = final: prev: {
#     myCustomPackage = prev.myPackage.overrideAttrs (old: {
#       version = "1.2.3";
#     });
#   };

final: prev: {
  # Add your custom package overlays here

  # Example: Override a package version
  # git = prev.git.overrideAttrs (old: {
  #   version = "2.40.0";
  # });

  # Example: Add a custom package
  # myScript = prev.writeShellScriptBin "my-script" ''
  #   echo "Hello from my custom script!"
  # '';

  # Custom packages live under ../pkgs; the overlay only re-exports them so they
  # are reachable as pkgs.<name> from any host.
  nebius-cli = final.callPackage ../pkgs/nebius-cli { };
  npc = final.callPackage ../pkgs/nebius-cli/npc.nix { };
}
