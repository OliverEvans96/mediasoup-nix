{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, fenix, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        rustPlatform = pkgs.rustPlatform;
        patched-mediasoup = pkgs.stdenv.mkDerivation rec {
          pname = "mediasoup-patched";
          version = "rust-0.11.1";

          src = pkgs.fetchFromGitHub {
            owner = "versatica";
            repo = "mediasoup";
            rev = version;
            sha256 = "sha256-V4gVOL3wTetuaLf2IQx/zhDUC0lMCgyZXRsXltz+JF4=";
          };

          phases = "unpackPhase patchPhase installPhase";
          patches = [ ./mediasoup-sys.patch ];
          installPhase = "cp -r . $out";
        };
        built-mediasoup-worker = pkgs.stdenv.mkDerivation {
          name = "built-mediasoup-worker";
          src = patched-mediasoup;
          buildPhase = ''
            cd worker
            make libmediasoup-worker
          '';

          nativeBuildInputs = with pkgs; [ meson openssl ];
        };
        patched-cargo-lock = pkgs.stdenv.mkDerivation {
          name = "patched-cargo-lock";
          src = ./.;
          phases = "unpackPhase patchPhase installPhase";
          patches = [ ./update-cargo-lock.patch ];
          installPhase = "cp Cargo.lock $out";
        };
        patched-mediasoup-rel-path = "./patched-mediasoup-src";
        cargo-toml-patch-lines = pkgs.writeText "cargo-toml-patch-lines.txt" ''
          [patch.crates-io]
          # mediasoup-sys = { path = "${patched-mediasoup}/worker" }
          mediasoup-sys = { path = "${patched-mediasoup-rel-path}/worker" }
        '';
        patched-src = pkgs.stdenv.mkDerivation {
          name = "patched-src";
          src = ./.;
          phases = "unpackPhase buildPhase installPhase";
          buildPhase = ''
            cat ${cargo-toml-patch-lines} >> Cargo.toml
          '';
          installPhase = "cp -r . $out";
        };
      in {

        packages.mediasoup = patched-mediasoup;
        packages.built-worker = built-mediasoup-worker;
        packages.cargoLock = patched-cargo-lock;
        packages.src = patched-src;

        defaultPackage = rustPlatform.buildRustPackage {
          pname = "mediasoup-nix";
          version = "0.1.0";

          nativeBuildInputs = with pkgs; [ lld pkgconfig udev meson ];

          cargoLock = { lockFile = patched-cargo-lock; };
          # cargoLock = { lockFile = ./Cargo.lock; };

          postPatch = ''
            cp ${patched-cargo-lock} Cargo.lock
          '';

          preBuild = ''
            cp -r ${patched-mediasoup} ${patched-mediasoup-rel-path}
            chmod u+w -R ${patched-mediasoup-rel-path}
          '';

          # # patches = [ cargo-toml-patch ];

          src = patched-src;
        };

        devShell = pkgs.mkShell {
          name = "mediasoup-nix-shell";
          src = ./.;

          # build-time deps
          nativeBuildInputs = (with pkgs; [
            python
            pythonPackages.pip
            rustc
            cargo
            lld
            pkgconfig
            udev
            meson
            ninja
          ]);
        };
      });
}
