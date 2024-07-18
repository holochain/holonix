{
  description = "Flake for Holochain app development";

  inputs = {
    holonix.url = "github:holochain/holonix/main";

    nixpkgs.follows = "holonix/nixpkgs";
    flake-parts.follows = "holonix/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = builtins.attrNames inputs.holonix.devShells;
    perSystem = { inputs', pkgs, ... }: {
      formatter = pkgs.nixpkgs-fmt;

      devShells.default = pkgs.mkShell {
        inputsFrom = [ inputs'.holonix.devShells ];

        packages = (with inputs'.holonix.packages; [
          holochain
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
      };
    };
  };
}
