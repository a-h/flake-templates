{ name, pkgs, config, dream2nix, ... }: {
  imports = [
    dream2nix.modules.dream2nix.nodejs-package-lock-v3
    dream2nix.modules.dream2nix.nodejs-granular-v3
  ];

  mkDerivation = {
    src = ./.;
  };

  nodejs-package-lock-v3 = {
    packageLockFile = "${config.mkDerivation.src}/package-lock.json";
  };

  nodejs-granular-v3 = {
    buildScript = ''
      ${pkgs.esbuild}/bin/esbuild --platform=node --bundle src/app.ts --minify --sourcemap --outfile=app.js
      mv app.js app.js.tmp
      echo "#!${config.deps.nodejs}/bin/node" > app.js
      cat app.js.tmp >> app.js
      chmod +x ./app.js
      patchShebangs .
    '';
  };

  name = name;
  version = "1.0.0";
}
