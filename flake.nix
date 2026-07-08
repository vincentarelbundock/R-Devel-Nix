{
  description = "Track, build, and run R-devel (SVN trunk) against nixpkgs libraries, fully isolated from the system profile.";

  # Pinned to the same nixpkgs revision as the host system so this flake reuses
  # the exact store paths already cached locally (no extra downloads/rebuilds).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/714a5f8c4ead6b31148d829288440ed033ccc041";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;

      svnUrl = "https://svn.r-project.org/R/trunk";

      # Libraries R links against. Their -isystem/-L/-rpath flags are computed
      # below from the .dev and runtime outputs.
      rLibs = with pkgs; [
        blas
        lapack
        bzip2
        xz
        zlib
        pcre2
        curl
        openssl
        readline
        ncurses
        icu
        libuv
        libxml2
        cairo
        pango
        fontconfig
        freetype
        fribidi
        harfbuzz
        gdk-pixbuf
        glib
        librsvg
        libjpeg
        libpng
        libtiff
        libwebp
        imagemagick
        gsl
        jags
        poppler
        tcl
        tk
        # X11 graphics device (devX11.o) and its transitive headers.
        libx11
        libxt
        libxmu
        xorgproto
        libsm
        libice
      ];

      # Host tools needed on PATH during checkout / configure / make.
      rTools = with pkgs; [
        coreutils
        gcc
        gfortran
        gnumake
        pkg-config
        perl
        bison
        texinfo
        which
        file
        subversion
        rsync
      ];

      # Standard autoconf CPPFLAGS/LDFLAGS that ./configure passes straight to
      # the compiler. We set these (rather than the Nix cc-wrapper's
      # NIX_CFLAGS_COMPILE/NIX_LDFLAGS) because the wrapper only injects its own
      # vars when the per-wrapper suffix-salt variable is set, which is not the
      # case inside a `nix run` app — so the wrapper path silently no-ops there.
      cppflags = lib.concatMapStringsSep " " (p: "-isystem ${lib.getDev p}/include") rLibs;
      ldflags = lib.concatMapStringsSep " " (
        p: "-L${lib.getLib p}/lib -Wl,-rpath,${lib.getLib p}/lib"
      ) rLibs;
      pkgConfigPath = lib.makeSearchPathOutput "dev" "lib/pkgconfig" rLibs;
      # The .dev outputs also carry the "*-config" helpers (curl-config,
      # xml2-config, ...) that R's configure invokes directly.
      devBins = lib.makeBinPath (map lib.getDev rLibs);
      fileCmd = "${lib.getBin pkgs.file}/bin/file";

      # Shared environment used by every entry point. R_SRC_DIR overrides the
      # location of the mutable SVN working tree (default: ./R-devel).
      envSetup = ''
        export SRC_DIR="''${R_SRC_DIR:-$PWD/R-devel}"
        export PATH="${devBins}''${PATH:+:$PATH}"
        export CPPFLAGS="${cppflags}''${CPPFLAGS:+ $CPPFLAGS}"
        export LDFLAGS="${ldflags}''${LDFLAGS:+ $LDFLAGS}"
        export PKG_CONFIG_PATH="${pkgConfigPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        export FILECMD="${fileCmd}"
        export MAGIC_CMD="${fileCmd}"
        # R detects libcurl via curl-config, not pkg-config; pin it explicitly.
        export CURL_CONFIG="${lib.getDev pkgs.curl}/bin/curl-config"
      '';

      updateApp = pkgs.writeShellApplication {
        name = "r-update";
        runtimeInputs = [
          pkgs.subversion
          pkgs.coreutils
        ];
        text = ''
          ${envSetup}
          if [ -d "$SRC_DIR/.svn" ]; then
            echo "Updating existing checkout at $SRC_DIR ..."
            svn update "$SRC_DIR"
          elif [ -d "$SRC_DIR" ]; then
            echo "Error: $SRC_DIR exists but is not an SVN working copy." >&2
            exit 1
          else
            echo "Checking out ${svnUrl} -> $SRC_DIR ..."
            svn checkout "${svnUrl}" "$SRC_DIR"
          fi
          echo "Fetching recommended packages ..."
          ( cd "$SRC_DIR" && ./tools/rsync-recommended )
          echo "Source ready at $SRC_DIR. Next: nix run .#build"
        '';
      };

      buildApp = pkgs.writeShellApplication {
        name = "r-build";
        runtimeInputs = rTools;
        text = ''
          ${envSetup}
          if [ ! -d "$SRC_DIR" ]; then
            echo "No source tree at $SRC_DIR. Run 'nix run .#update' first." >&2
            exit 1
          fi
          cd "$SRC_DIR"
          # R's configure has /usr/bin/file hard-coded; repoint it at the Nix file.
          if [ -f configure ]; then
            perl -0pi -e "s#/usr/bin/file#$FILECMD#g" configure
          fi
          # Clear stale configure state from a previous build.
          if [ -f Makefile ]; then
            make -s distclean >/dev/null 2>&1 || make -s clean || true
          fi
          [ -x tools/rsync-recommended ] && ./tools/rsync-recommended || true
          # shellcheck disable=SC2086
          ./configure ''${R_CONFIGURE_ARGS:---enable-R-shlib}
          make -j"$(nproc)"
          echo
          echo "Built R-devel: $SRC_DIR/bin/R    (run it with: nix run .#run)"
        '';
      };

      runApp = pkgs.writeShellApplication {
        name = "r-run";
        # Carry the full build env so install.packages() can compile from source.
        runtimeInputs = rTools;
        text = ''
          ${envSetup}
          RBIN="$SRC_DIR/bin/R"
          if [ ! -x "$RBIN" ]; then
            echo "No built R at $RBIN. Run 'nix run .#build' first." >&2
            exit 1
          fi
          exec "$RBIN" "$@"
        '';
      };
    in
    {
      apps.${system} = {
        update = {
          type = "app";
          program = "${updateApp}/bin/r-update";
        };
        build = {
          type = "app";
          program = "${buildApp}/bin/r-build";
        };
        run = {
          type = "app";
          program = "${runApp}/bin/r-run";
        };
        default = self.apps.${system}.run;
      };

      # `nix develop` for interactive work: same env, plus all tools on PATH so
      # you can run ./configure, make, or bin/R by hand.
      devShells.${system}.default = pkgs.mkShell {
        packages = rTools;
        shellHook = ''
          ${envSetup}
          cat <<'EOF'
        R-devel dev shell. The build environment (NIX_CFLAGS_COMPILE, NIX_LDFLAGS,
        PKG_CONFIG_PATH, curl-config, ...) is configured.
          nix run .#update   # svn checkout/update trunk into ./R-devel
          nix run .#build    # ./configure && make -j
          nix run .#run      # run the freshly built R-devel
        Override the source location with R_SRC_DIR=/path/to/tree.
        EOF
        '';
      };
    };
}
