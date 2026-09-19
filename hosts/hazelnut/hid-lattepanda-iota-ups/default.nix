{ lib, stdenv, kernel }:

stdenv.mkDerivation {
  pname = "hid-lattepanda-iota-ups";
  version = "0.1";

  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD modules
  '';

  installPhase = ''
    install -D hid-lattepanda-iota-ups.ko \
      $out/lib/modules/${kernel.modDirVersion}/extra/hid-lattepanda-iota-ups.ko
  '';

  meta = {
    description = "LattePanda IOTA UPS power supply driver (upstream-pending, LKML patch v3)";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
