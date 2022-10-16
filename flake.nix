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
      in {
        defaultPackage = rustPlatform.buildRustPackage {
          pname = "mediasoup-nix";
          version = "0.1.0";

          nativeBuildInputs = with pkgs; [ python pip lld pkgconfig udev ];

          cargoLock = { lockFile = ./Cargo.lock; };

          src = ./.;
        };

        devShell = pkgs.mkShell {
          name = "mediasoup-nix-shell";
          src = ./.;

          # build-time deps
          nativeBuildInputs =
            (with pkgs; [ python pip rustc cargo lld pkgconfig udev ]);
        };
      });
}
