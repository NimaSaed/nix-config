# Public Nebius AI Cloud CLI — the customer-facing `nebius` command.
{ callPackage }:

callPackage ./generic.nix {
  pname = "nebius-cli";
  binName = "nebius";
  version = "0.12.252";
  baseUrl = "https://storage.eu-north1.nebius.cloud/cli";

  sources = {
    x86_64-linux = {
      os = "linux";
      arch = "x86_64";
      hash = "sha256-2CSIBxUVfwMR+DZDwQWHnVbZqgZbq78+NhAWgVYPriU=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-z0mY7XS9bQnVWMiof0djQ/Nmx93PkJ4nlH8j+VNK2EM=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "x86_64";
      hash = "sha256-6NPwR9jkL+XLC0C4t3IUPKFsO/yAVeJh23jYR3r6aew=";
    };
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-dnDj9pVtC544Z174Ka1rXn1pq4SCICVHCvB4GEpa2qQ=";
    };
  };

  description = "Command-line interface for Nebius AI Cloud";
  homepage = "https://docs.nebius.com/cli";
}
