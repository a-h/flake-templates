{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xc = {
      url = "github:joerdav/xc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, gitignore, xc, ... }:
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

      app = { name, pkgs, system, ... }: pkgs.buildNpmPackage {
        pname = name;
        version = "1.0.0";

        src = gitignore.lib.gitignoreSource ./.;

        npmDeps = pkgs.importNpmLock {
          npmRoot = gitignore.lib.gitignoreSource ./.;
        };

        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
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
        pkgs.esbuild
        pkgs.gh
        pkgs.git
        pkgs.nodejs
        pkgs.typescript
        xc.packages.${system}.xc
      ];

      name = "app";
    in
    {
      packages = forAllSystems ({ system, pkgs }: {
        default = app {
          name = name;
          pkgs = pkgs;
          system = system;
        };
        docker-image = dockerImage { name = name; pkgs = pkgs; system = system; };
      });

      # `nix develop` provides a shell containing required tools.
      devShells = forAllSystems ({ system, pkgs }: {
        default = pkgs.mkShell {
          buildInputs = (devTools { system = system; pkgs = pkgs; });
        };
      });
    };
}
