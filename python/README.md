# github.com/a-h/flake-templates/python

## Tasks

### build

```bash
nix build
```

### run

```bash
nix run
```

### run-local

```bash
python3 ./src/app/app.py
```

### develop

```bash
nix develop
```

### requirements-add

After adding new requirements, you will need to reload the Nix shell, e.g. by running `nix develop` again, or exiting the current directory and re-entering it so that direnv can pick up the changes.

```bash
uv add fastapi uvicorn
```

### docker-build

```bash
nix build .#docker-image
```

### docker-load

Once you've built the image, you can load it into a local Docker daemon with `docker load`.

```bash
docker load < result
```

### docker-run

```bash
docker run -p 8080:8080 app:latest
```
