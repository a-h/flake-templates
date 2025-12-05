{
  description = "Flake templates";
  outputs = { self }: {
    templates = {
      doc = {
        path = ./doc;
        description = "Markdown to PDF pipeline, using pandoc";
      };
      typst = {
        path = ./typst;
        description = "Typst document";
      };
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
