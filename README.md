[![Holonix cache trigger](https://github.com/holochain/holonix/actions/workflows/holonix-cache-trigger.yaml/badge.svg)](https://github.com/holochain/holonix/actions/workflows/holonix-cache-trigger.yaml)

`main` [![Holonix cache](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml/badge.svg)](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml)
`main-0.6` [![Holonix cache](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml/badge.svg?branch=main-0.6)](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml)
`main-0.5` [![Holonix cache](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml/badge.svg?branch=main-0.5)](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml)
`main-0.4` [![Holonix cache](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml/badge.svg?branch=main-0.4)](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml)
`main-0.3` [![Holonix cache](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml/badge.svg?branch=main-0.3)](https://github.com/holochain/holonix/actions/workflows/holonix-cache.yaml)

# Holonix

Holochain app development environment based on [Nix](https://nixos.org/).

[Instructions to set up Holochain developer environment](https://developer.holochain.org/get-started/#2-installing-holochain-development-environment) and [more about Nix for Holochain app development](https://developer.holochain.org/get-started/install-advanced/).

## Quickstart - Dev shell from default template

hApp developers can use a Nix command to generate a flake that includes Holochain and other required binaries in a dev shell. Change into your project directory where you are developing the app and run

```shell
nix flake init -t github:holochain/holonix
```

You will be asked to allow substituters to be set to make use of binaries cached on cachix. This is not required to generate the flake, but when invoking the dev shell, Nix can benefit from the cache and download all binaries instead of building them on your machine from scratch. Further note that this is a local setting that only affects this project and not your global Nix settings. Even if the caches are already configured globally on your system, Nix will ask anyway for this particular project.

Inspecting the flake reveals the definition found under [./templates/default/flake.nix](./templates/default/flake.nix).

The command to enter the dev shell and have the defined binaries available for execution is

```shell
nix develop
```

With the binary cache configured correctly, most or all binaries will be downloaded. How long this takes depends on your internet connection speed, but in any case the first time the dev shell is invoked will take longer than subsequent times.

After the dev shell has built, Holochain and scaffolding commands are available.

```console
[holonix:]$ holochain --version
holochain x.y
[holonix:]$ hc-scaffold --version
holochain_scaffolding_cli x.y
```

## Updating Holonix flake

As new Holochain versions are released, they are added to the binary cache. The cache has a limited capacity, thus over time older versions get removed from the cache. If you don't stay near the most recent versions, you will end up rebuilding everything from scratch every time on a CI system.

At that point, you either need to create your own binary cache or update your Holonix input in the Nix flake.

At the top of the `flake.nix` file, inputs are defined, which are the sources of the packages to be included in the dev shell. In the `flake.lock` file the revision of each of the inputs is pinned. If you want to update this pinned revision to the latest state, you can run

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

By default the Holonix input references the `main` branch of the Holonix repository. Whatever the current revision of that branch at the moment of invoking the dev shell for the first time is will be written to the `flake.lock` file. The `main` branch uses version 0.5 of Holochain and compatible versions of scaffolding etc.

If you want to develop using the 0.3 (recommended) or 0.4 (RC) release series of Holochain instead, you can create the corresponding Nix flake by running this command inside your project folder, replacing `<ver>` with the correct version number:

```shell
nix flake init -t github:holochain/holonix?ref=main-<ver>
```

Alternatively you can modify an existing `flake.nix` file, changing the `holonix` url in the inputs section to point to `main-0.3`.

```diff
inputs = {
-   holonix.url = "github:holochain/holonix?ref=main";
+   holonix.url = "github:holochain/holonix?ref=main-0.3";
    ...
};
```

Running `nix develop` now will update the flake lock file with the current revision of the `main-0.3` branch of the Holonix repository and enter the dev shell.

### Overriding Holochain version

It could be that you want to use another version of Holochain, Lair or Scaffolding etc. For example there is a breaking change from one version to the next one and you can't update your app. In that case you can override the Holonix inputs and safely run `nix flake update` without risking to move to another version of Holochain before you're ready. To override the Holochain version, modify the `flake.nix` file as follows

```diff
inputs = {
    holonix.url = "github:holochain/holonix?ref=main";
+   holonix.inputs.holochain.url = "github:holochain/holochain?ref=branch-or-tag-name";
  };
}
```

> Note that the overridden version of Holochain may not be available to download from the binary cache and will then be built from scratch on your machine or on CI. Also it's important to make sure that the overridden packages are compatible with each other.


## Defining packages to include in the dev shell

It may be that you want to add or remove packages included in the dev shell. If you wanted to only use the Holochain binaries in a dev shell, all other packages can be removed from the default shell.

```diff
...
packages = (with inputs'.holonix.packages; [
    holochain
-   lair-keystore
-   hc-launch
-   hc-scaffold
-   hn-introspect
    rust # For Rust development, with the WASM target included for zome builds
])
...
```

Other packages from the Nix packages collection can be added here. For example the `jq` package can be added.

```diff
]) ++ (with pkgs; [
    nodejs_20 # For UI development
    binaryen # For WASM optimisation
    # Add any other packages you need here
+   jq
]);
```

> Note that by default Rust is included in the dev shell. If you want to use your globally installed version of Rust instead, remove the `rust` package from the list of packages. Using a newer version of Rust than Holochain is currently built with might, however, result in warnings or build issues. If you encounter such issue, you're invited to [create an issue](https://github.com/holochain/holochain/issues/new/choose).

## Customized Holochain build

In the default flake template, Holochain comes built with default features. If you need Holochain with a different feature set, you can customize the Holochain build. The `custom` template shows how to customize the Holochain build.

To initialize a flake based on the custom template, run the following command inside your project folder

```shell
nix flake init -t github:holochain/holonix#custom
```

In [the generated `flake.nix` file](./templates/custom-holochain/flake.nix), locate the section that specifies the cargo build parameters to be passed to the Holochain build.

```nix
let
    # Disable default features and enable wasmer_wamr for a wasm interpreter,
    # as well as re-enabling tx5 and sqlite-encrypted.
    cargoExtraArgs = "--no-default-features --features wasmer_wamr,sqlite-encrypted,tx5";
    # Override arguments passed in to Holochain build with above feature arguments.
    customHolochain = inputs'.holonix.packages.holochain.override { inherit cargoExtraArgs; };
in
```

Under `cargoExtraArgs` additional features can be defined or default features disabled. Once you modified these arguments as desired, run `nix develop` to build the dev shell.

Note that the resulting custom binary of Holochain is not cached, so it must be built on your computer which will take time, depending on the specifications of your machine.

## References

- [Nix Flake Wiki](https://wiki.nixos.org/wiki/Flakes)
- [Nix Reference Manual](https://nix.dev/manual/nix/latest)
