{
  description = "Flake templates";
  outputs = { self }: {
    templates = {
      go = {
        path = ./go;
        description = "Go build using gomod2nix, and building Docker container";
      };
    };
    defaultTemplate = self.templates.go;
  };
}
