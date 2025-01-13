{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    xc = {
      url = "github:joerdav/xc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, xc, uv2nix, pyproject-nix, pyproject-build-systems, }:
    let
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        system = system;
        pkgs = import nixpkgs {
          inherit system;
        };
      });

      # Load a uv workspace from a workspace root.
      # Uv2nix treats all uv projects as workspace projects.
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      # Create package overlay from workspace.
      overlay = workspace.mkPyprojectOverlay {
        # Prefer prebuilt binary wheels as a package source.
        # Sdists are less likely to "just work" because of the metadata missing from uv.lock.
        # Binary wheels are more likely to, but may still require overrides for library dependencies.
        sourcePreference = "wheel"; # or sourcePreference = "sdist";
        # Optionally customise PEP 508 environment
        # environ = {
        #   platform_release = "5.10.65";
        # };
      };

      # Extend generated overlay with build fixups
      #
      # Uv2nix can only work with what it has, and uv.lock is missing essential metadata to perform some builds.
      # This is an additional overlay implementing build fixups.
      # See:
      # - https://pyproject-nix.github.io/uv2nix/FAQ.html
      pyprojectOverrides = _final: _prev: {
        # Implement build fixups here.
        # Note that uv2nix is _not_ using Nixpkgs buildPythonPackage.
        # It's using https://pyproject-nix.github.io/pyproject.nix/build.html
      };

      pythonSet = pkgs:
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage pyproject-nix.build.packages {
          python = pkgs.python312;
        }).overrideScope
          (
            pkgs.lib.composeManyExtensions [
              pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
            ]
          );

      appVirtualEnv = pkgs: (pythonSet pkgs).mkVirtualEnv "${name}-venv" workspace.deps.default;

      # Build app.
      app = { name, pkgs, system }: pkgs.stdenv.mkDerivation {
        name = name;
        src = ./.;
        buildInputs = [
          (appVirtualEnv pkgs)
        ];
        installPhase = ''
          # Create a wrapper script to run the app.
          # Run it by executing python ./src/app/app.py
          mkdir -p $out/bin
          echo "#!${pkgs.bash}/bin/bash" > $out/bin/${name}
          echo "${(appVirtualEnv pkgs)}/bin/python $out/src/app/app.py" >> $out/bin/${name}
          chmod +x $out/bin/${name}

          # Copy the source content.
          cp -rv $src/* $out
        '';
      };

      # Build Docker containers.
      dockerUser = pkgs: pkgs.runCommand "user" { } ''
        mkdir -p $out/etc
        echo "user:x:1000:1000:user:/home/user:/bin/false" > $out/etc/passwd
        echo "user:x:1000:" > $out/etc/group
        echo "user:!:1::::::" > $out/etc/shadow
      '';
      dockerImage = { name, pkgs, system }: pkgs.dockerTools.buildImage {
        name = name;
        tag = "latest";

        copyToRoot = [
          # Remove coreutils and bash for a smaller container.
          pkgs.coreutils
          pkgs.bash
          # CA certificates to access HTTPS sites.
          pkgs.cacert
          pkgs.dockerTools.caCertificates
          (dockerUser pkgs)
          (app { inherit name pkgs system; })
        ];
        config = {
          Cmd = [ name ];
          User = "user:user";
          Env = [ "ADD_ENV_VARIABLES=1" ];
          ExposedPorts = {
            "8080/tcp" = { };
          };
        };
      };

      # Development tools used.
      devTools = { system, pkgs }: [
        pkgs.crane
        pkgs.gh
        pkgs.git
        xc.packages.${system}.xc
        pkgs.uv
      ];

      name = "app";
    in
    {
      # `nix build` builds the app.
      # `nix build .#docker-image` builds the Docker container.
      packages = forAllSystems ({ system, pkgs }: {
        default = app { name = name; pkgs = pkgs; system = system; };
        docker-image = dockerImage { name = name; pkgs = pkgs; system = system; };
      });
      # `nix develop` provides a shell containing required tools.
      devShells = forAllSystems ({ system, pkgs }: {
        default =
          let
            # Create an overlay enabling editable mode for all local dependencies.
            editableOverlay = workspace.mkEditablePyprojectOverlay {
              # Use environment variable
              root = "$REPO_ROOT";
              # Optional: Only enable editable for these packages
              # members = [ "hello-world" ];
            };

            # Override previous set with our overrideable overlay.
            editablePythonSet = (pythonSet pkgs).overrideScope editableOverlay;

            # Build virtual environment, with local packages being editable.
            #
            # Enable all optional dependencies for development.
            virtualenv = editablePythonSet.mkVirtualEnv "${name}-dev-venv" workspace.deps.all;
          in
          pkgs.mkShell {
            buildInputs = (devTools { system = system; pkgs = pkgs; });
            packages = [ virtualenv ];

            env = {
              # Don't create venv using uv.
              UV_NO_SYNC = "1";

              # Force uv to use Python interpreter from venv.
              UV_PYTHON = "${virtualenv}/bin/python";

              # Prevent uv from downloading managed Python's.
              UV_PYTHON_DOWNLOADS = "never";
            };

            shellHook = ''
              # Undo dependency propagation by nixpkgs.
              unset PYTHONPATH

              # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };
      });
    };
}
