{
  # flake format https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-format
  description = "Holonix - Holochain Nix flake";

  # specify all input dependencies needed to create the outputs of the flake
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # utility to iterate over multiple target platforms
    flake-parts.url = "github:hercules-ci/flake-parts";

    # lib to build a nix package from a rust crate
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust toolchain
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Holochain sources
    holochain-src = {
      url = "github:holochain/holochain";
      flake = false;
    };

    # Lair keystore sources
    lair-keystore-src = {
      url = "github:holochain/lair";
      flake = false;
    };
  };

  # outputs that this flake should produce
  outputs = inputs @ { self, nixpkgs, flake-parts, rust-overlay, crane, holochain-src, lair-keystore-src, ... }:
    # refer to flake-parts docs https://flake.parts/
    flake-parts.lib.mkFlake { inherit inputs; } {
      # systems that his flake can be used on
      systems = [ "aarch64-darwin" "x86_64-linux" "x86_64-darwin" "aarch64-linux" ];

      # for each system...
      perSystem = { config, pkgs, system, ... }:
        let
          # include Rust overlay in nixpkgs
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs {
            inherit system overlays;
          };

          # define Rust toolchain version and targets to be used in this flake
          rust = (pkgs.rust-bin.stable."1.78.0".default.override
            {
              targets = [ "wasm32-unknown-unknown" ];
            });

          # instruct crane to use Rust toolchain specified above
          craneLib = (crane.mkLib pkgs).overrideToolchain rust;

          # define how to build Holochain binaries
          holochain =
            let
              # Crane filters out all non-cargo related files. Define include filter with files needed for build.
              nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
              includeFilesFilter = path: type:
                (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
            in
            craneLib.buildPackage {
              pname = "holochain";
              version = "workspace";
              # Use Holochain sources as defined in input dependencies and include only those files defined in the
              # filter previously.
              src = pkgs.lib.cleanSourceWith {
                src = holochain-src;
                filter = includeFilesFilter;
              };
              # additional packages needed for build
              buildInputs = [
                pkgs.perl
                pkgs.go
              ];
              # do not check built package as it either builds successfully or not
              doCheck = false;
            };

          # define how to build Lair keystore binary
          lair-keystore =
            let
              # Crane filters out all non-cargo related files. Define include filter with files needed for build.
              nonCargoBuildFiles = path: _type: builtins.match ".*(sql|md)$" path != null;
              includeFilesFilter = path: type:
                (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
            in
            craneLib.buildPackage {
              pname = "lair-keystore";
              version = "workspace";
              # Use Lair keystore sources as defined in input dependencies and include only those files defined in the
              # filter previously.
              src = pkgs.lib.cleanSourceWith {
                src = lair-keystore-src;
                filter = includeFilesFilter;
              };
              # additional packages needed for build
              # perl needed for openssl on all platforms
              buildInputs = [ pkgs.perl ]
                ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
                # additional packages needed for darwin platforms
                pkgs.libiconv
                pkgs.darwin.apple_sdk.frameworks.Security
                # additional packages needed for darwin platforms on x86_64
                pkgs.darwin.apple_sdk_11_0.frameworks.CoreFoundation
              ]);
              # do not check built package as it either builds successfully or not
              doCheck = false;
            };
        in
        {
          packages = {
            inherit holochain;
            inherit lair-keystore;
            inherit rust;
          };

          devShells = {
            default = pkgs.mkShell {
              packages = [
                holochain
                lair-keystore
                rust
              ];
            };
          };
        };
    };
}
