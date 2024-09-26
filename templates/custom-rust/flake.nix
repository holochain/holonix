{
  description = "Flake for Holochain app development with Rust stable";

  inputs = {
    holonix.url = "github:holochain/holonix?ref=main";

    nixpkgs.follows = "holonix/nixpkgs";
    flake-parts.follows = "holonix/flake-parts";

    # Rust toolchain overlay for importing specific versions of Rust
    rust-overlay.follows = "holonix/rust-overlay";
  };

  outputs = inputs@{ flake-parts, nixpkgs, rust-overlay, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = builtins.attrNames inputs.holonix.devShells;
    perSystem = { system, inputs', pkgs, ... }: {
      formatter = pkgs.nixpkgs-fmt;

      devShells.default =
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs {
            inherit system overlays;
          };

          # Define a Rust setup that works for your project. This should be a functional default
          # for a scaffolded project but can be adjusted.
          # Options: https://github.com/oxalica/rust-overlay?tab=readme-ov-file#cheat-sheet-common-usage-of-rust-bin
          rust = (pkgs.rust-bin.stable.latest.minimal.override
            {
              extensions = [ "clippy" "rustfmt" ];
              targets = [ "wasm32-unknown-unknown" ];
            });
        in
        pkgs.mkShell {
          packages = [
            rust
          ] ++ (with inputs'.holonix.packages; [
            holochain
            lair-keystore
            hc-launch
            hc-scaffold
            hn-introspect
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
