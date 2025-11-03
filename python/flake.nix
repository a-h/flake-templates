{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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

  outputs = { nixpkgs, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
    let
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      pyprojectOverrides = final: prev: {
        # These projects don't have setuptools declared as a build system requirement,
        # so we need to add it manually.
        antlr4-python3-runtime = prev.antlr4-python3-runtime.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ final.resolveBuildSystem ({ setuptools = [ ]; });
        });
        dsnparse = prev.dsnparse.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ final.resolveBuildSystem ({ setuptools = [ ]; });
        });
        # Some projects are complex to build. If there's a version in nixpkgs, we can
        # use that instead.
        mysql-connector-python = final.pkgs.python312Packages.mysql-connector;
        pip = final.pkgs.python312Packages.pip;
        python-lsp-server = final.pkgs.python312Packages.python-lsp-server;
        # If the package isn't in nixpkgs at all, then you'll have to package it.
        # See https://github.com/NixOS/nixpkgs/blob/nixos-24.11/pkgs/development/python-modules/streamlit/default.nix
        # as an example.
      };

      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          python = pkgs.python312;
          pythonPkgs = (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              nixpkgs.lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
                pyprojectOverrides
              ]
            );
          pythonPkgsEditable = (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              nixpkgs.lib.composeManyExtensions [
                pyproject-build-systems.overlays.wheel
                editableOverlay
                pyprojectOverrides
              ]
            );

          pythonEnv = (pythonPkgs.mkVirtualEnv "app-env" workspace.deps.all);
          app = (pkgs.stdenv.mkDerivation {
            name = "app";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = [ pythonEnv ];

            installPhase = ''
              mkdir -p $out/bin
              cp -r ./ $out/bin/${name}-script
              makeWrapper ${pythonEnv}/bin/python $out/bin/${name} \
                --set PYTHONPATH "$out/bin/${name}-script/src" \
                --add-flags $out/bin/${name}-script/src/app/main.py
            '';
          });
        in
        f {
          inherit system pkgs pythonPkgs pythonPkgsEditable pythonEnv app;
        }
      );

      extraPythonDeps = pkgs: ps: [
        ps.python-lsp-server
        ps.pip
      ];

      # Build Docker containers.
      dockerUser = pkgs: pkgs.runCommand "user" { } ''
        mkdir -p $out/etc
        echo "user:x:1000:1000:user:/home/user:/bin/false" > $out/etc/passwd
        echo "user:x:1000:" > $out/etc/group
        echo "user:!:1::::::" > $out/etc/shadow
      '';
      dockerImage = { name, pkgs, app, ... }: pkgs.dockerTools.buildImage {
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
          app
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
      devTools = pkgs: [
        pkgs.crane
        pkgs.uv
        pkgs.xc
      ];

      name = "app";
    in
    {
      devShells = forAllSystems ({ pkgs, pythonPkgsEditable, pythonEnv, ... }: {
        default = pkgs.mkShell {
          packages = [ pythonEnv ] ++ (devTools pkgs) ++ (extraPythonDeps pkgs pythonPkgsEditable);
          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = "${pythonEnv}/bin/python";
            UV_PYTHON_DOWNLOADS = "never";
          };
          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
            export PYTHONPATH=$REPO_ROOT/src
          '';
        };
      });
      packages = forAllSystems
        ({ system, pkgs, app, ... }: {
          default = app;
          docker-image = dockerImage {
            inherit name system pkgs app;
          };
        });
    };
}

