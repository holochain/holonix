{
  description =
    "Holochain is an open-source framework to develop peer-to-peer applications with high levels of security, reliability, and performance.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # lib to build nix packages from rust crates
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # rustup, rust and cargo
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    launcher = {
      url = "github:holochain/launcher/holochain-weekly";
      flake = false;
    };
  };

  # refer to flake-parts docs https://flake.parts/
  outputs = inputs @ { self, nixpkgs, flake-parts, rust-overlay, ... }:
    # all possible parameters for a module: https://flake.parts/module-arguments.html#top-level-module-arguments
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-darwin" "x86_64-linux" "x86_64-darwin" ];

      perSystem = { pkgs, system, ... }:
        let
          rustedNixpkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          rustToolchain = rustedNixpkgs.rust-bin.stable."1.78.0".minimal;

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;

          apple_sdk =
            if system == "x86_64-darwin"
            then pkgs.darwin.apple_sdk_10_12
            else pkgs.darwin.apple_sdk_11_0;

          commonArgs = {
            pname = "hc-launch";
            src = inputs.launcher;
            cargoExtraArgs = "--bin hc-launch";

            buildInputs = [
              pkgs.perl
            ]
            ++ (pkgs.lib.optionals pkgs.stdenv.isLinux
              [
                pkgs.glib
                pkgs.go
                pkgs.webkitgtk.dev
              ])
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin
              [
                apple_sdk.frameworks.AppKit
                apple_sdk.frameworks.WebKit

                (if pkgs.system == "x86_64-darwin" then
                  pkgs.darwin.apple_sdk_11_0.stdenv.mkDerivation
                    {
                      name = "go";
                      nativeBuildInputs = with pkgs; [
                        makeBinaryWrapper
                        go
                      ];
                      dontBuild = true;
                      dontUnpack = true;
                      installPhase = ''
                        makeWrapper ${pkgs.go}/bin/go $out/bin/go
                      '';
                    }
                else pkgs.go)
              ]
            ;

            nativeBuildInputs = (
              if pkgs.stdenv.isLinux then [ pkgs.pkg-config ]
              else [ ]
            );

            doCheck = false;
          };

          # derivation building all dependencies
          deps = craneLib.buildDepsOnly
            (commonArgs // { });

          # derivation with the main crates
          launcher = craneLib.buildPackage
            (commonArgs // {
              cargoArtifacts = deps;

              stdenv =
                if pkgs.stdenv.isDarwin then
                  pkgs.overrideSDK pkgs.stdenv "11.0"
                else
                  pkgs.stdenv;
            });
        in
        {
          packages = {
            inherit launcher;
          };
        };
    };
}
