{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
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

      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        system = system;
        pkgs = import nixpkgs {
          inherit system;
        };
      });

      d2-filter = pkgs: (pkgs.buildNpmPackage rec {
        pname = "d2-filter";
        version = "1.4.1";

        src = pkgs.fetchFromGitHub {
          # https://github.com/ram02z/d2-filter
          owner = "ram02z";
          repo = pname;
          rev = "e0ec202cda8b284f2e25cb9ecd75161ff3bd74a6";
          hash = "sha256-Oy2vQ/Ua87Fd0pFJ+SLe0EGYvKRbXhi6jM2rYmLNI6M=";
        };

        npmDepsHash = "sha256-2R5i6xf+71Zl9uxDbtRKj36HTolnj9gsmps/uxF5o+4=";

        buildInputs = [ pkgs.d2 pkgs.makeWrapper pkgs.librsvg ];

        buildPhase = ''
          runHook preBuild

          npm ci

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp -r . $out/bin
          cp ./filter-shim.js $out/bin/d2-filter
          chmod +x $out/bin/d2-filter

          wrapProgram $out/bin/d2-filter \
            --set PATH ${pkgs.lib.makeBinPath buildInputs}

          runHook postInstall
        '';
      });


      pdf = { name, pkgs, system }:
        pkgs.stdenvNoCC.mkDerivation rec {
          inherit name;

          src = ./.;

          buildInputs = [
            pkgs.findutils
            pkgs.coreutils
            pkgs.pandoc
            pkgs.tectonic
            pkgs.librsvg
            (d2-filter pkgs)
          ];

          buildPhase = ''
            export PATH="${pkgs.lib.makeBinPath buildInputs}";
            export HOME="$TMP" ;
            mkdir -p $out
            ${pkgs.pandoc}/bin/pandoc -F d2-filter $src/${name}.md --pdf-engine tectonic \
              -V geometry:a4paper -V geometry:margin=2cm \
              -o $out/${name}.pdf \
              --toc=true
          '';

          installPhase = ''
        '';
        };

      # Development tools used.
      devTools = { system, pkgs }: [
        xc.packages.${system}.xc
        pkgs.d2
        pkgs.pandoc
        pkgs.tectonic
        pkgs.librsvg
        (d2-filter pkgs)
      ];
      name = "doc";
    in
    {
      # `nix build` builds the PDF.
      packages = forAllSystems ({ system, pkgs }: {
        default = pdf { name = name; pkgs = pkgs; system = system; };
      });
      # `nix develop` provides a shell containing required tools.
      devShells = forAllSystems ({ system, pkgs }: {
        default = pkgs.mkShell {
          buildInputs = (devTools { system = system; pkgs = pkgs; });
        };
      });
    };
}

