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
          patches = [
            ./mediasoup-sys.patch
            # wrap-files.openssl.wrap-patch
          ];
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

        # simpleTransform = name: buildPhase: src:
        #   pkgs.stdenv.mkDerivation {
        #     inherit name src buildPhase;
        #     phases = "buildPhase";
        #   };

        # substitute = subs:
        #   simpleTransform "substitute-drv" "substitute $src $out ${subs}";

        mkSubstituteCmd = file: pre: post: ''
          echo pwd: $PWD
          echo substituteInPlace "${file}" --replace "${pre}" "${post}"
          substituteInPlace "${file}" --replace "${pre}" "${post}"
          cat ${file}
          echo
        '';

        wraps = [{
          name = "openssl";
          replacements = [
            {
              url = "https://www.openssl.org/source/openssl-3.0.2.tar.gz";
              sha256 = "sha256-mOkczq1NR1auPJzeXgkZGo5YbZ9NUIOOfsCdZBHf22M=";
            }
            {
              url =
                "https://wrapdb.mesonbuild.com/v2/openssl_3.0.2-1/get_patch";
              sha256 = "sha256-diq06pTQIXjWodPrY0CcLE1hMV01g5HNrGLfFSERdNQ=";
            }
          ];
        }];

        patchDerivation = src: patchPhase:
          pkgs.stdenv.mkDerivation {
            inherit src patchPhase;
            name = "patch-derivation";
            phases = "unpackPhase patchPhase installPhase";
            installPhase = "cp -r . $out";
          };

        # log = msg: e:
        #   pkgs.lib.traceVal
        #   ("${msg} (${builtins.typeOf e}): ${builtins.toJSON e}");

        mkWrapPatchPhase = wraps:
          let
            getFilename = wrapName: "worker/subprojects/${wrapName}.wrap";
            mkCommand = name: replacement:
              let
                filename = getFilename name;
                newPath = pkgs.fetchurl replacement;
                newUrl = "file://${newPath}";
              in (mkSubstituteCmd filename replacement.url newUrl);
            mkWrapCommands = wrap: map (mkCommand wrap.name) wrap.replacements;
            allCommands = builtins.concatMap mkWrapCommands wraps;
          in pkgs.lib.concatStrings allCommands;

        mediasoup-wrap-patched =
          patchDerivation patched-mediasoup (mkWrapPatchPhase wraps);

        # mkWrapFilePatch = { source, patch }:
        #   let
        #     sourceFile = pkgs.fetchurl source;
        #     patchFile = pkgs.fetchurl patch;
        #   in pkgs.writeText "openssl-wrap.patch" ''
        #     diff --git a/worker/subprojects/openssl.wrap b/worker/subprojects/openssl.wrap
        #     index 274b544c..5cc400ae 100644
        #     --- a/worker/subprojects/openssl.wrap
        #     +++ b/worker/subprojects/openssl.wrap
        #     @@ -3 +3 @@ directory = openssl-3.0.2
        #     -source_url = https://www.openssl.org/source/openssl-3.0.2.tar.gz
        #     +source_url = file://${sourceFile}
        #     @@ -7 +7 @@ patch_filename = openssl_3.0.2-1_patch.zip
        #     -patch_url = https://wrapdb.mesonbuild.com/v2/openssl_3.0.2-1/get_patch
        #     +patch_url = file://${patchFile}
        #   '';

        # openssl-patch = mkWrapFilePatch {
        #   source = {
        #     url = "https://www.openssl.org/source/openssl-3.0.2.tar.gz";
        #     sha256 = "sha256-mOkczq1NR1auPJzeXgkZGo5YbZ9NUIOOfsCdZBHf22M=";
        #   };
        #   patch = {
        #     url = "https://wrapdb.mesonbuild.com/v2/openssl_3.0.2-1/get_patch";
        #     sha256 = "sha256-diq06pTQIXjWodPrY0CcLE1hMV01g5HNrGLfFSERdNQ=";
        #   };
        # };

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

        # wrap-files = {
        #   openssl = rec {
        #     source = pkgs.fetchurl {
        #       url = "https://www.openssl.org/source/openssl-3.0.2.tar.gz";
        #       sha256 = "sha256-mOkczq1NR1auPJzeXgkZGo5YbZ9NUIOOfsCdZBHf22M=";
        #     };
        #     patch = pkgs.fetchurl {
        #       url =
        #         "https://wrapdb.mesonbuild.com/v2/openssl_3.0.2-1/get_patch";
        #       sha256 = "sha256-diq06pTQIXjWodPrY0CcLE1hMV01g5HNrGLfFSERdNQ=";
        #     };
        #     wrap-patch = pkgs.writeText "openssl-wrap.patch" ''
        #       diff --git a/worker/subprojects/openssl.wrap b/worker/subprojects/openssl.wrap
        #       index 274b544c..5cc400ae 100644
        #       --- a/worker/subprojects/openssl.wrap
        #       +++ b/worker/subprojects/openssl.wrap
        #       @@ -3 +3 @@ directory = openssl-3.0.2
        #       -source_url = https://www.openssl.org/source/openssl-3.0.2.tar.gz
        #       +source_url = file://${source}
        #       @@ -7 +7 @@ patch_filename = openssl_3.0.2-1_patch.zip
        #       -patch_url = https://wrapdb.mesonbuild.com/v2/openssl_3.0.2-1/get_patch
        #       +patch_url = file://${patch}
        #     '';
        #   };
        # };

      in {

        packages.mediasoup = patched-mediasoup;
        packages.built-worker = built-mediasoup-worker;
        packages.cargoLock = patched-cargo-lock;
        packages.src = patched-src;
        # packages.wrap-patches = pkgs.writeText "out.txt" (mkPatchPhase wraps);
        packages.patched = mediasoup-wrap-patched;

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
            cp -r ${mediasoup-wrap-patched} ${patched-mediasoup-rel-path}
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
