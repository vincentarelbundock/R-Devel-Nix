# R-Devel-Nix

Building R from source requires a considerable amount of tooling, and new developers rarely have everything they need out of the box. The R development team supplies [a useful containerized development environment](https://github.com/r-devel/r-dev-env), but it requires GitHub, Docker, VS Code, and the VS Code Dev Containers extension. 

This repository lets you build R from source more easily, straight from the command line. The required build dependencies are installed into an isolated Nix environment. Nothing is installed into your system profile. You can work on the source code from the terminal or using your favorite IDE. Building R only requires a single command.

Easy.

## Installing Nix

The only prerequisite is the [Nix package manager.](https://nixos.org/) On **macOS** and **Linux**:

```sh
curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon
```

Then open a new terminal and enable flakes (once):

```sh
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

## Usage

The next command operate on the **current working directory**, creating and building `./R-devel`, so first `cd` to where you want the source tree to live:

```sh
mkdir -p ~/r && cd ~/r

# svn checkout/update trunk into ./R-devel
nix run github:vincentarelbundock/R-devel-nix#update   

# ./configure && make -j
nix run github:vincentarelbundock/R-devel-nix#build    

# launch the built R interactively
nix run github:vincentarelbundock/R-devel-nix#run      
```

`#run` with no arguments starts an interactive R session; pass flags after `--`:

```sh
nix run github:vincentarelbundock/R-devel-nix#run -- --version
```

## Interactive dev shell

For hands-on work, drop into a shell with the full build environment and all tools on `PATH`. For example, this shows that I do not have subversion installed on my local computer:

```sh
svn

> zsh: command not found: svn
```

But when I call `nix develop`, I suddenly have access to all the tools required for R development:

```sh
nix develop github:vincentarelbundock/R-devel-nix
svn

> Type 'svn help' for usage.
```

This allows you do to things like pass flags to `./configure` when building:

```sh
nix develop github:vincentarelbundock/R-devel-nix

# then, in the source tree:
cd R-devel && ./configure --enable-R-shlib && make -j$(nproc) && ./bin/R
```

## Notes

- Point the build at a different source tree with `R_SRC_DIR=/path/to/tree`.
- Override configure flags with `R_CONFIGURE_ARGS` (default `--enable-R-shlib`).
- Nix caches the fetched flake, so after this repository is updated you may keep
  getting the old version. Force a refetch with `--refresh`:

  ```sh
  nix run --refresh github:vincentarelbundock/R-devel-nix#build
  ```

  You only need it once after an update; later runs pick up the cached new version.
