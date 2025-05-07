{
  description = "Flake for Holochain app development with customized Holochain build";

  inputs = {
    holonix.url = "github:holochain/holonix?ref=main";

    nixpkgs.follows = "holonix/nixpkgs";
    flake-parts.follows = "holonix/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = builtins.attrNames inputs.holonix.devShells;
    perSystem = { inputs', pkgs, ... }:
      let
        # Override arguments passed in to Holochain build with above feature arguments.
        customHolochain = inputs'.holonix.packages.holochain.override {
          # Disable default features and enable CHC and unstable sharding.
          cargoExtraArgs = "--features chc,unstable-sharding";
        };
        # Customize the Holochain CLI build.
        customHc = inputs'.holonix.packages.hc.override {
          # Check whether you need to customize the Holochain CLI build because it
          # might be that the default (cached) binary will work for you even when adding features to Holochain.
          cargoExtraArgs = "--features chc";
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          packages = [
            # Include custom builds of Holochain and the Holochain CLI in dev shell.
            customHolochain
            customHc
          ]
          ++ (with inputs'.holonix.packages; [
            hcterm
            bootstrap-srv
            lair-keystore
            hc-launch
            hc-scaffold
            hn-introspect
            hc-playground
            rust # For Rust development, with the WASM target included for zome builds
          ]) ++ (with pkgs; [
            nodejs_20 # For UI development
            binaryen # For WASM optimisation
            # Add any other packages you need here
          ]);

          shellHook = ''
            export PS1='\[\033[1;34m\][holonix:\w]\$\[\033[0m\] '
          '';
        };
      };
  };
}
