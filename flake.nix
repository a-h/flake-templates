{
  description = "Flake templates";
  outputs = { self }: {
    templates = {
      go = {
        path = ./go;
        description = "Go build using gomod2nix, and building Docker container";
      };
      js = {
        path = ./js;
        description = "JavaScript build using dream2nix, and building Docker container";
      };
      python = {
        path = ./python;
        description = "Python build using poetry2nix, and building Docker container";
      };
    };
    defaultTemplate = self.templates.go;
  };
}
