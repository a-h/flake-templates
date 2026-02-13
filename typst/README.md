# Document

## Tasks

### watch

Interactive: true

```bash
watchexec -e mermaid -- '
  for f in *.mermaid; do
    [ -f "$f" ] && mmdc -i "$f"
  done
  typst compile doc.typ
' &
watchexec -e d2 -- '
  for f in *.d2; do
    [ -f "$f" ] && d2 "$f" "$f.svg"
  done
  typst compile doc.typ
' &
watchexec -e typ -- typst compile doc.typ
wait
```

### build

```bash
# Run mmdc -i for all .mermaid files in the current directory.
for file in *.mermaid; do mmdc -i "$file"; done
# Run d2 for all .d2 files in the current directory.
for file in *.d2; do d2 "$file" "$file.svg"; done
typst compile doc.typ
```

### develop

```bash
nix develop
```
