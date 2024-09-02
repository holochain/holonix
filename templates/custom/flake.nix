{
  description = "Flake for Holochain app development with customized Holochain build";

  inputs = {
    holonix.url = "github:holochain/holonix?ref=main-0.3";

    nixpkgs.follows = "holonix/nixpkgs";
    flake-parts.follows = "holonix/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = builtins.attrNames inputs.holonix.devShells;
    perSystem = { inputs', pkgs, ... }:
      let
        # Enable CHC (chain head coordination) feature for Holochain package.
        cargoExtraArgs = "--features chc";
        # Override arguments passed in to Holochain build with above feature arguments.
        customHolochain = inputs'.holonix.packages.holochain.override { inherit cargoExtraArgs; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ inputs'.holonix.devShells ];

          packages = [
            # Include custom build of Holochain in dev shell.
            customHolochain
          ]
          ++ (with inputs'.holonix.packages; [
            lair-keystore
            hc-launch
            hc-scaffold
            hn-introspect
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
