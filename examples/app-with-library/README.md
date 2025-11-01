# App + Library (strict mode)

This template shows a small executable that links against a static library and keeps
its dependency manifest checked in for strict (no-IFD) environments.

## Rebuilding

```sh
nix build
./result/bin/simple-strict
```

For the incremental/developer flow you can also use the scanner-based variant:

```sh
nix build .#simple-scanned
./result/bin/simple-scanned
```

## Updating `.clang-deps.nix`

The manifest is generated from the dependency scanner and stored in
`.clang-deps.nix`. Regenerate it after header changes with:

```sh
nix run ../..#cpp-sync-manifest -- .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').simpleScanManifest ./.clang-deps.nix
```

(Adjust the flake path `../..` if you copy this template elsewhere.)
Add the command to CI to ensure the manifest stays up to date; it exits with a
non-zero status if the generated file differs from the checked-in copy.
