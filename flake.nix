{
  # flake format https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-format
  description = "Holonix - Holochain Nix flake";

  # specify all input dependencies needed to create the outputs of the flake
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";

    # utility to iterate over multiple target platforms
    flake-parts.url = "github:hercules-ci/flake-parts";

    # lib to build a nix package from a rust crate
    crane = {
      url = "github:ipetkov/crane";
    };

    # Rust toolchain
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kitsune2 = {
      url = "github:holochain/kitsune2?ref=v0.1.5";
      flake = false;
    };

    # Holochain sources
    holochain = {
      url = "github:holochain/holochain?ref=holochain-0.6.0-dev.1";
      flake = false;
    };

    # Lair keystore sources
    lair-keystore = {
      url = "github:holochain/lair?ref=lair_keystore-v0.6.1";
      flake = false;
    };

    # Holochain Launch CLI
    hc-launch = {
      url = "github:holochain/hc-launch?ref=holochain-weekly";
      flake = false;
    };

    # Holochain scaffolding CLI
    hc-scaffold = {
      url = "github:holochain/scaffolding?ref=holochain-weekly";
      flake = false;
    };

    # Third-party tool from Darksoil Studio for exploring DHT data.
    playground = {
      url = "github:darksoil-studio/holochain-playground?ref=main-0.5";
      flake = false;
    };
  };

  # outputs that this flake should produce
  outputs = inputs @ { self, nixpkgs, flake-parts, rust-overlay, crane, ... }:
    # refer to flake-parts docs https://flake.parts/
    flake-parts.lib.mkFlake { inherit inputs; }
      {
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

            rustVersion = "1.83.0";

            # define Rust toolchain version and targets to be exported from this flake
            rust = (pkgs.rust-bin.stable.${rustVersion}.minimal.override
              {
                extensions = [ "clippy" "rustfmt" ];
                targets = [ "wasm32-unknown-unknown" ];
              });

            # instruct crane to use Rust toolchain specified above
            craneLib = (crane.mkLib pkgs).overrideToolchain (p: p.rust-bin.stable.${rustVersion}.minimal);

            bootstrap-srv =
              craneLib.buildPackage {
                pname = "kitsune2-bootstrap-srv";
                # only build kitsune2-bootstrap-srv binary
                cargoExtraArgs = "-p kitsune2_bootstrap_srv";
                # Use Kitsune2 sources as defined in input dependencies.
                src = craneLib.cleanCargoSource inputs.kitsune2;
                # additional packages needed for build
                nativeBuildInputs = [ pkgs.perl pkgs.cmake ];
                buildInputs = [
                  pkgs.openssl
                ] ++ (pkgs.lib.optional (system == "x86_64-darwin") pkgs.apple-sdk_10_15);
                # do not check built package as it either builds successfully or not
                doCheck = false;
              };

            # Common Crane configuration to build binaries from the Holochain workspace.
            holochainCommon =
              let
                # Crane filters out all non-cargo related files. Define include filter with files needed for build.
                nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
                includeFilesFilter = path: type:
                  (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
              in
              {
                # Set a placeholder name for the dependencies derivation.
                pname = "holochain";

                # Crane wants a version when it builds dependencies but these arguments get re-used for different
                # binaries. Set to 0.0.0 and expect packages to override it.
                version = "0.0.0";

                # Use Holochain sources as defined in input dependencies and include only those files defined in the
                # filter previously.
                src = pkgs.lib.cleanSourceWith {
                  src = inputs.holochain;
                  filter = includeFilesFilter;
                };
                # additional packages needed for build
                buildInputs = [
                  pkgs.perl
                  pkgs.cmake
                ]
                # Holochain needs `clang` to build but the clang provided for x86_64-darwin fetches the wrong macos SDK.
                ++ (pkgs.lib.optionals (system != "x86_64-darwin") [
                  pkgs.clang
                ])
                # On intel macs, the default SDK is still 10.12 and Holochain won't build against that because we're
                # using a newer Go version. So override with the newest SDK available for x86_64-darwin.
                ++ (pkgs.lib.optional (system == "x86_64-darwin") pkgs.apple-sdk_10_15);

                # do not check built package as it either builds successfully or not
                doCheck = false;

                # Make sure libdatachannel can find C++ standard libraries from clang.
                LIBCLANG_PATH = "${pkgs.llvmPackages_18.libclang.lib}/lib";
              };

            # Define a derivation for just the Holochain dependencies.
            holochainDeps = craneLib.buildDepsOnly holochainCommon;

            # Define a function to build the Holochain binary. This allows consumers to customize the
            # build by overriding function arguments.
            holochainBuilder =
              {
                # Specify features to be built into Holochain. Can be overridden by the consumer.
                # See the custom feature template for an example.
                cargoExtraArgs ? ""
              }:
              let
                # Crane doesn't know which version to select from a workspace, so we tell it where to look
                crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/holochain/Cargo.toml"; };
              in
              craneLib.buildPackage (holochainCommon // { cargoArtifacts = holochainDeps; } // {
                pname = "holochain";
                version = crateInfo.version;
                cargoExtraArgs = "--manifest-path crates/holochain/Cargo.toml --bin holochain " + cargoExtraArgs;
              });

            # Default Holochain build, made overridable to allow consumers to extend cargo build arguments.
            holochain = pkgs.lib.makeOverridable holochainBuilder { };

            # Similar to the Holochain builder above, but for the hc binary.
            hcBuilder =
              { cargoExtraArgs ? "" }:
              let
                # Crane doesn't know which version to select from a workspace, so we tell it where to look
                crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/hc/Cargo.toml"; };
              in
              craneLib.buildPackage (holochainCommon // { cargoArtifacts = holochainDeps; } // {
                pname = "hc";
                version = crateInfo.version;
                # only build hc binary
                cargoExtraArgs = "--manifest-path crates/hc/Cargo.toml --bin hc " + cargoExtraArgs;
              });

            # Default hc binary.
            hc = pkgs.lib.makeOverridable hcBuilder { };

            # The Holochain terminal, which has no feature flags and can just be defined as a normal package.
            hcterm =
              let
                # Crane doesn't know which version to select from a workspace, so we tell it where to look
                crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/holochain_terminal/Cargo.toml"; };
              in
              craneLib.buildPackage (holochainCommon // { cargoArtifacts = holochainDeps; } // {
                pname = "hcterm";
                version = crateInfo.version;
                # only build hcterm binary
                cargoExtraArgs = "--manifest-path crates/holochain_terminal/Cargo.toml --bin hcterm";
              });

            # define how to build Lair keystore binary
            lair-keystore =
              let
                # Crane filters out all non-cargo related files. Define include filter with files needed for build.
                nonCargoBuildFiles = path: _type: builtins.match ".*(sql|md)$" path != null;
                includeFilesFilter = path: type:
                  (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);

                # Crane doesn't know which version to select from a workspace, so we tell it where to look
                crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.lair-keystore + "/crates/lair_keystore/Cargo.toml"; };
              in
              craneLib.buildPackage {
                pname = "lair-keystore";
                version = crateInfo.version;
                # only build lair-keystore binary
                cargoExtraArgs = "--bin lair-keystore";
                # Use Lair keystore sources as defined in input dependencies and include only those files defined in the
                # filter previously.
                src = pkgs.lib.cleanSourceWith {
                  src = inputs.lair-keystore;
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

            # define how to build hc-launch binary
            hc-launch =
              let
                # Crane filters out all non-cargo related files. Define include filter with files needed for build.
                nonCargoBuildFiles = path: _type: builtins.match ".*(js|json|png)$" path != null;
                includeFilesFilter = path: type:
                  (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);

                # Crane doesn't know which version to select from a workspace, so we tell it where to look
                crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.hc-launch + "/crates/hc_launch/src-tauri/Cargo.toml"; };

                # Use consistent version of Apple SDK throughout. Without this, building on x86_64-darwin fails.
                # See below.
                apple_sdk =
                  if system == "x86_64-darwin"
                  then pkgs.darwin.apple_sdk_10_12
                  else pkgs.darwin.apple_sdk_11_0;

                commonArgs = {
                  pname = "hc-launch";
                  version = crateInfo.version;
                  # Use hc-launch sources as defined in input dependencies and include only those files defined in the
                  # filter previously.
                  src = pkgs.lib.cleanSourceWith {
                    src = inputs.hc-launch;
                    filter = includeFilesFilter;
                  };
                  # Only build hc-launch command
                  cargoExtraArgs = "--bin hc-launch";

                  # commands required at build time
                  nativeBuildInputs = (
                    if pkgs.stdenv.isLinux then [ pkgs.pkg-config ]
                    else [ ]
                  );

                  # build inputs required for linking to execute at runtime
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
                    ];

                  # do not check built package as it either builds successfully or not
                  doCheck = false;
                };

                # derivation building all dependencies
                deps = craneLib.buildDepsOnly commonArgs;
              in
              # derivation with the main crates
              craneLib.buildPackage
                (commonArgs // {
                  cargoArtifacts = deps;

                  # Override stdenv Apple SDK packages. It's unclear why this is needed, but building on x86_64-darwin
                  # fails without it.
                  # https://discourse.nixos.org/t/need-help-from-darwin-users-syntax-errors-in-library-frameworks-foundation-framework-headers/30467/3
                  stdenv = p:
                    if p.stdenv.isDarwin then
                      p.overrideSDK p.stdenv "11.0"
                    else
                      p.stdenv;
                });

            hc-scaffold =
              let
                # Crane filters out all non-cargo related files. Define include filter with files needed for build.
                nonCargoBuildFiles = path: _type: builtins.match ".*(gitignore|md|hbs|nix|sh)$" path != null;
                includeFilesFilter = path: type:
                  (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
              in
              craneLib.buildPackage {
                pname = "hc-scaffold";
                src = pkgs.lib.cleanSourceWith {
                  src = inputs.hc-scaffold;
                  filter = includeFilesFilter;
                };

                doCheck = false;

                buildInputs = [
                  pkgs.perl
                ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
                  # Required by the git2 crate, see https://github.com/rust-lang/git2-rs/blob/master/libgit2-sys/build.rs#L251
                  pkgs.darwin.apple_sdk.frameworks.Security
                  pkgs.darwin.apple_sdk.frameworks.CoreFoundation
                ];
              };

            # Define how to build the Holochain Playground CLI.
            hc-playground =
              let
                # Filter down to required files for the CLI build.
                pnpmFilter = path: type: type == "directory" || builtins.match ".*(ts|js|json|yaml|html)$" path != null;

                cli = pkgs.stdenv.mkDerivation (finalAttrs: {
                  pname = "hc-playground";
                  # See the `package.json` version for the source code being imported.
                  version = "0.500.0";

                  src = pkgs.lib.sources.cleanSourceWith {
                    src = inputs.playground;
                    filter = pnpmFilter;
                  };

                  nativeBuildInputs = with pkgs; [
                    nodejs
                    pnpm_9.configHook
                  ];

                  # See what is required by the `pnpm build:cli` command.
                  # This filters down to just the dependencies needed for the CLI.
                  pnpmWorkspaces = [
                    "@holochain-playground/simulator"
                    "@holochain-playground/elements"
                    "@holochain-playground/cli-client"
                    "@holochain-playground/cli"
                  ];

                  # Fetch dependencies with a fixed-output-derivation.
                  #
                  # When updating the input, this fixed derivation will need to be updated.
                  # If you leave this hash alone, you'll get errors about dependencies needing to be
                  # fetched in the build phase.
                  pnpmDeps = pkgs.pnpm_9.fetchDeps {
                    inherit (finalAttrs) pname version src;
                    hash = "sha256-vCFZPfrWFKq65LIsPN+0V5iDtzUlsVIcHMpW9pKV61Q=";
                  };

                  buildPhase = ''
                    runHook preBuild
                    pnpm build:cli
                    runHook postBuild

                    mkdir $out
                    cp -R packages/cli/server/dist $out
                  '';
                });
              in
              # Turn the built JS into a runnable CLI.
              pkgs.writeShellScriptBin "hc-playground" ''
                node ${cli}/dist/app.js "$@"
              '';

            # Shell script to show what versions of the Holochain tools are installed.
            # It can be included as a package into the dev shell and is then available by its name - `hn-introspect`.
            hn-introspect = pkgs.writeShellScriptBin "hn-introspect" ''
              #!/usr/bin/env bash

              if command -v "hc-scaffold" > /dev/null; then
                echo "hc-scaffold            : $(hc-scaffold --version) (${builtins.substring 0 7 inputs.hc-scaffold.rev})"
              else
                echo "hc-scaffold            : not installed"
              fi

              if command -v "hc-launch" > /dev/null; then
                echo "hc-launch              : $(hc-launch --version) (${builtins.substring 0 7 inputs.hc-launch.rev})"
              else
                echo "hc-launch              : not installed"
              fi

              if command -v "lair-keystore" > /dev/null; then
                echo "Lair keystore          : $(lair-keystore --version) (${builtins.substring 0 7 inputs.lair-keystore.rev})"
              else
                echo "Lair keystore          : not installed"
              fi

              if command -v "kitsune2-bootstrap-srv" > /dev/null; then
                echo "Kitsune2 bootstrap srv : $(kitsune2-bootstrap-srv --version) (${builtins.substring 0 7 inputs.kitsune2.rev})"
              else
                echo "Kitsune2 bootstrap srv : not installed"
              fi

              if command -v "hc" > /dev/null; then
                echo "Holochain CLI          : $(hc --version) (${builtins.substring 0 7 inputs.holochain.rev})"
              else
                echo "Holochain CLI          : not installed"
              fi

              if command -v "hcterm" > /dev/null; then
                echo "Holochain terminal     : $(hcterm --version) (${builtins.substring 0 7 inputs.holochain.rev})"
              else
                echo "Holochain terminal     : not installed"
              fi

              if command -v "holochain" > /dev/null; then
                echo "Holochain              : $(holochain --version) (${builtins.substring 0 7 inputs.holochain.rev})"

                printf "\nHolochain build info: "
                holochain --build-info | ${pkgs.jq}/bin/jq
              else
                echo "Holochain              : not installed"
              fi
            '';
          in
          {
            # Configure a formatter so that `nix fmt` can be used to format this file.
            formatter = pkgs.nixpkgs-fmt;

            packages = {
              inherit holochain;
              inherit hc;
              inherit hcterm;
              inherit bootstrap-srv;
              inherit lair-keystore;
              inherit hc-launch;
              inherit hc-scaffold;
              inherit rust;
              inherit hn-introspect;
              inherit hc-playground;
            };

            # Define runnable applications for use with `nix run`.
            # These can be used like `nix run "github:holochain/holonix#hc-scaffold" -- --version`.
            # https://flake.parts/options/flake-parts.html?highlight=perSystem.apps#opt-perSystem.apps
            apps = {
              holochain.program = "${holochain}/bin/holochain";
              hc.program = "${hc}/bin/hc";
              hcterm.program = "${hcterm}/bin/hcterm";
              kitsune2-bootstrap-srv.program = "${bootstrap-srv}/bin/kitsune2-bootstrap-srv";
              lair-keystore.program = "${lair-keystore}/bin/lair-keystore";
              hc-launch.program = "${hc-launch}/bin/hc-launch";
              hc-scaffold.program = "${hc-scaffold}/bin/hc-scaffold";
              hc-playground.program = "${hc-playground}/bin/hc-playground";
            };

            devShells = {
              default = pkgs.mkShell {
                packages = [
                  holochain
                  hc
                  hcterm
                  bootstrap-srv
                  lair-keystore
                  hc-launch
                  hc-scaffold
                  hn-introspect
                  hc-playground
                  rust
                ];
              };
            };
          };
      } // {
      # Add content which is not platform specific after using flake-parts to generate platform specific content.
      templates = {
        # A template that can be used to create a flake that depends on this flake, with recommended defaults.
        default = {
          path = ./templates/default;
          description = "Holonix default template";
        };
        custom-holochain = {
          path = ./templates/custom-holochain;
          description = "Holonix template for custom Holochain build";
        };
        custom-rust = {
          path = ./templates/custom-rust;
          description = "Flake for Holochain app development with Rust stable";
        };
      };
    };

  nixConfig = {
    # https://nixos.wiki/wiki/Maintainers:Fastly#BETA:_Try_cache_v2.21
    substituters = [ "https://aseipp-nix-cache.freetls.fastly.net" "https://cache.nixos.org" "https://holochain-ci.cachix.org" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" "holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=" ];
  };
}
