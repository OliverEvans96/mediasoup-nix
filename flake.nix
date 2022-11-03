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

        mkSubstituteCmd = file: pre: post: ''
          substituteInPlace "${file}" --replace "${pre}" "${post}"
        '';

        # aided (but manually edited) by the following command:
        # rg _url --json | jq -sr '[.[] | select(.type == "match")] | group_by(.data.path.text)[] | { name: (. | first | .data.path.text), replacements: [.[] | .data.lines.text | scan("^(.*?)_url = (.*)") | { url: .[1], sha256: "" }]}'
        wraps = [
          {
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
          }
          {
            name = "abseil-cpp";
            replacements = [
              {
                url =
                  "https://github.com/abseil/abseil-cpp/archive/20211102.0.tar.gz";
                sha256 = "sha256-3PcbnLqNwMqZQMSzFqDHlr6Pq0KwcLtrfKtitI8OZsQ=";
              }
              {
                url =
                  "https://wrapdb.mesonbuild.com/v2/abseil-cpp_20211102.0-2/get_patch";
                sha256 = "sha256-lGOTA2ew25hENTUMfXYU5AD6qIEafpot71pj/zn9syU=";
              }
            ];
          }
          {
            name = "catch2";
            replacements = [
              {
                url = "https://github.com/catchorg/Catch2/archive/v2.13.7.zip";
                sha256 = "sha256-PzzNkK06j7sb7rFebbRAzNy+vjeN/RJdB6H5pYepJ+k=";
              }
              {
                url =
                  "https://wrapdb.mesonbuild.com/v2/catch2_2.13.7-1/get_patch";
                sha256 = "sha256-L3NpZF10flvYZjF6wd1MPQTcl9Oq1PxrhkvfddO1cVg=";
              }
            ];
          }
          {
            name = "libsrtp2";
            replacements = [{
              url =
                "https://github.com/cisco/libsrtp/archive/refs/tags/v2.4.2.zip";
              sha256 = "sha256-NbGuemJWIk/rBY8f60IXBTekSJY0D4Dne0nMWa9oaoI=";
            }];
          }
          {
            name = "libuv";
            replacements = [
              {
                url =
                  "https://dist.libuv.org/dist/v1.44.1/libuv-v1.44.1.tar.gz";
                sha256 = "sha256-nTe2NDD+O5KpOGuUm+vY8LR4SjmhaWTILJVmJHp29ko=";
              }
              {
                url =
                  "https://wrapdb.mesonbuild.com/v2/libuv_1.44.1-1/get_patch";
                sha256 = "sha256-ihBRWM2ryipU8cfMTC+BTBWSceENxeN+0aCPE8/Wf/c=";
              }
            ];
          }
          {
            name = "nlohmann_json";
            replacements = [{
              url =
                "https://github.com/nlohmann/json/releases/download/v3.10.5/include.zip";
              sha256 = "sha256-uUmX32iFZ1O3Lw16NwO31ITUdFxWfzWE75fJbCWleY4=";
            }];
          }
          {
            name = "usrsctp";
            replacements = [{
              url =
                "https://github.com/sctplab/usrsctp/archive/4e06feb01cadcd127d119486b98a4bd3d64aa1e7.zip";
              sha256 = "sha256-FfeETExMqTIorg/oRBgscu3R2Am0YcuXsbtoeoBN1Pw=";
            }];
          }
          {
            name = "wingetopt";
            replacements = [{
              url = "https://github.com/alex85k/wingetopt/archive/v1.00.zip";
              sha256 = "sha256-RFTKA6WXAqTKTRSIyo+mFosMjXfcc5pv4oJcPdhgnYc=";
            }];
          }
        ];

        patchDerivation = src: patchPhase:
          pkgs.stdenv.mkDerivation {
            inherit src patchPhase;
            name = "patch-derivation";
            phases = "unpackPhase patchPhase installPhase";
            installPhase = "cp -r . $out";
          };

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

      in {

        packages.mediasoup = patched-mediasoup;
        packages.built-worker = built-mediasoup-worker;
        packages.cargoLock = patched-cargo-lock;
        packages.src = patched-src;
        packages.patched = mediasoup-wrap-patched;

        defaultPackage = rustPlatform.buildRustPackage {
          pname = "mediasoup-nix";
          version = "0.1.0";

          nativeBuildInputs = with pkgs; [ lld pkgconfig udev meson ninja ];
          dontUseNinjaBuild = true;
          dontUseNinjaCheck = true;
          dontUseNinjaInstall = true;

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
