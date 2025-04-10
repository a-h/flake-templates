{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    xc = {
      url = "github:joerdav/xc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, xc }:
    let
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (self: super: {
                # Add xc to nixpkgs.
                xc = xc.outputs.packages.${system}.xc;
              })
            ];
          };
          # Set the Python version for all packages.
          python = pkgs.python312;
        in
        f {
          inherit system pkgs python;
        }
      );

      # Streamlit in nixpkgs was 1.40.1 when the latest version was 1.44.1.
      # To handle scenarios like this, we can override the src.
      overriddenStreamlit = { pkgs, sl }: sl.overridePythonAttrs (old: rec {
        version = "1.44.1";
        src = pkgs.fetchPypi {
          inherit version;
          pname = "streamlit";
          hash = "sha256-xpFO1tW3aHC0YVEEdoBts3DzZCWuDmZU0ifJiCiBmNM="; # Set this to "", and nix will error after the download, giving the hash.
        };
      });

      # If the package isn't in nixpkgs at all, then you'll have to package it.
      # See https://github.com/NixOS/nixpkgs/blob/nixos-24.11/pkgs/development/python-modules/streamlit/default.nix
      # as an example.

      pythonDeps = pkgs: ps: [
        (overriddenStreamlit { inherit pkgs; sl = ps.streamlit; })
        ps.authlib # Required for streamlit auth.
        ps.uvicorn
        ps.fastapi
        ps.python-lsp-server
        ps.pandas
        ps.watchdog
      ];

      app = { name, pkgs, python, ... }: python.pkgs.buildPythonApplication {
        inherit name;
        src = ./.;
        propagatedBuildInputs = (pythonDeps pkgs python.pkgs);
      };

      # Build Docker containers.
      dockerUser = pkgs: pkgs.runCommand "user" { } ''
        mkdir -p $out/etc
        echo "user:x:1000:1000:user:/home/user:/bin/false" > $out/etc/passwd
        echo "user:x:1000:" > $out/etc/group
        echo "user:!:1::::::" > $out/etc/shadow
      '';
      dockerImage = { name, system, pkgs, python }: pkgs.dockerTools.buildImage {
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
          (app { inherit name system pkgs python; })
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
        pkgs.gh
        pkgs.git
        pkgs.xc
      ];

      name = "app";
    in
    {
      devShells = forAllSystems ({ system, pkgs, python, ... }: {
        default = pkgs.mkShell {
          packages =
            (devTools pkgs) ++
            [
              (python.withPackages (pythonDeps pkgs))
            ];
        };
      });
      packages = forAllSystems
        ({ system, pkgs, python, ... }: {
          default = app {
            name = name;
            pkgs = pkgs;
            python = python;
          };
          docker-image = dockerImage {
            name = name;
            system = system;
            pkgs = pkgs;
            python = python;
          };
        });
    };
}

