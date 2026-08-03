# Shared builder for both flavours of the Nebius CLI.
#
# Upstream builds the public (`nebius`) and private (`npc`) CLIs from one
# codebase and ships them with a byte-identical install script, differing only in
# binary name, storage URL and version pointer. Both are statically linked Go
# binaries laid out as <baseUrl>/release/<version>/<os>/<arch>/<binName>, with
# <baseUrl>/release/stable holding the current version.
#
# To bump either flavour:
#   curl -sS <baseUrl>/release/stable
#   nix-prefetch-url <baseUrl>/release/<version>/<os>/<arch>/<binName>
#   nix hash convert --hash-algo sha256 --to sri <base32-hash>
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,

  pname,
  binName,
  version,
  baseUrl,

  # Attrset of nix system -> { os, arch, hash }. Doubles as meta.platforms.
  sources,
  description,
  homepage,
}:

let
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "${pname}: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "${baseUrl}/release/${version}/${source.os}/${source.arch}/${binName}";
    inherit (source) hash;
  };

  # Statically linked Go binary, so no autoPatchelfHook or interpreter fixup.
  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [ installShellFiles ];

  # Deliberately unwrapped. --no-check-update would silence the self-update nag
  # (`<cli> update` rewrites its own binary, which cannot work from the store),
  # but the completion and __complete subcommands reject that persistent flag —
  # a wrapper adding it builds fine and then breaks shell completion at runtime.
  # Confirmed on both flavours.
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/${binName}
    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform) ''
    installShellCompletion --cmd ${binName} \
      --bash <($out/bin/${binName} completion bash) \
      --zsh <($out/bin/${binName} completion zsh) \
      --fish <($out/bin/${binName} completion fish)
  '';

  # The version and hashes are hand-maintained, so catch a stale pairing here
  # rather than halfway through a home-manager switch.
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    [ "$($out/bin/${binName} version)" = "${version}" ]
  '';

  meta = {
    inherit description homepage;
    # Neither flavour publishes a license or EULA, and the binaries embed none.
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = binName;
    platforms = lib.attrNames sources;
  };
}
