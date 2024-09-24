# Holonix

Holochain app development environment based on Nix.

## Quickstart - Dev shell from default template

hApp developers can use a Nix command to generate a flake that includes Holochain and other required binaries in a dev shell.

```shell
nix flake init -t github:holochain/holonix
```

You may be asked to allow substituters to be set to make use of binaries cached on cachix. This is not required to generate the flake, but when invoking the dev shell, Nix can benefit from the cache and download all binaries instead of building them on your machine from scratch.

Inspecting the flake reveals the definition found under [./templates/default/flake.nix](./templates/default/flake.nix).

The command to enter the dev shell and have the defined binaries available for execution is

```shell
nix develop
```

With the binary cache configured correctly, most or all binaries will be downloaded. How long this takes depends on your internet connection speed, but in any case the first time the dev shell is invoked will take longer than subsequent times.

After the dev shell has built, Holochain and scaffolding commands are available.

```shell
[holonix:]$ holochain --version
holochain x.y
[holonix:]$ hc-scaffold --version
holochain_scaffolding_cli x.y
```

## Updating Holonix flake

At the top of the Nix flake inputs are defined which are the sources of the packages to be included in the dev shell. In the `flake.lock` file the revision of each of the inputs is pinned. If you want to update this pinned revision to the latest state, you can run

```shell
nix flake update
```

This will update all inputs to the latest version. In case you just want to update an individual input, append the input identifier to the above command.

```shell
nix flake update holonix
```

The next time you enter the dev shell, the updated binaries will be downloaded and provided in the resulting shell. Should you have run `nix flake update` from inside the dev shell, you need to `exit` the shell first and then enter it again with `nix develop`.

[nix flake update in Nix Reference Manual](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake-update)

## Including other versions of Holochain

By default the Holonix input references the `main` branch of the Holonix repository. Whatever the current revision of that branch at the moment of invoking the dev shell for the first time is will be written to the `flake.lock` file. The `main` branch uses version 0.4 of Holochain and compatible versions of scaffolding etc.

To use other versions of Holochain in the dev shell, the `holonix` input must be modified.

```nix
inputs = {
    holonix.url = "github:holochain/holonix?ref=main";
    ...
};
```

For Holochain v0.3, change it to `main-0.3`.

```nix
inputs = {
    holonix.url = "github:holochain/holonix?ref=main-0.3";
    ...
};
```

Now running `nix develop` will update the flake lock file with the current revision of the `main-0.3` branch of the Holonix repository and enter the dev shell.

## Defining packages to include in the dev shell

It may be that you want to add or remove packages included in the dev shell. This is the relevant section

```nix
...
packages = (with inputs'.holonix.packages; [
    holochain
    lair-keystore
    hc-launch
    hc-scaffold
    hn-introspect
    rust # For Rust development, with the WASM target included for zome builds
])
...
```

If you wanted to only use the Holochain binaries in a dev shell, all other packages can be removed from the default shell.

```nix
...
packages = (with inputs'.holonix.packages; [
    holochain
    rust # For Rust development, with the WASM target included for zome builds
])
...
```

Other packages from the Nix packages collection can be added here.

```nix
]) ++ (with pkgs; [
    nodejs_20 # For UI development
    binaryen # For WASM optimisation
    # Add any other packages you need here
]);
```

For example the `jq` package can be added.

```nix
]) ++ (with pkgs; [
    nodejs_20 # For UI development
    binaryen # For WASM optimisation
    # Add any other packages you need here
    jq
]);
```

> Note that by default Rust is included in the dev shell. If you want to use your globally installed version of Rust instead, remove the `rust` package from the list of packages.

## Customized Holochain build

In the default flake template, Holochain comes built with default features. If you need Holochain with a different feature set, you can customize the Holochain build. The `custom` template shows how to customize the Holochain build.

To initialize a flake based on the custom template, run

```shell
nix flake init -t github:holochain/holonix#custom
```

In [the generated `flake.nix` file](./templates/custom/flake.nix), locate the section that specifies the cargo build parameters to be passed to the Holochain build.

```nix
let
    # Enable CHC (chain head coordination) feature for Holochain package.
    cargoExtraArgs = "--features chc";
    # Override arguments passed in to Holochain build with above feature arguments.
    customHolochain = inputs'.holonix.packages.holochain.override { inherit cargoExtraArgs; };
in
```

Under `cargoExtraArgs` additional features can be defined or default features disabled. Once you modified these arguments as desired, run `nix develop` to build the dev shell.

Note that the resulting custom binary of Holochain is not cached, so it must be built on your computer which will take time, depending on the specifications of your machine.

## References

[Nix Flake Wiki](https://wiki.nixos.org/wiki/Flakes)
[Nix Reference Manual](https://nix.dev/manual/nix/latest)