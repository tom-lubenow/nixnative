# pkg-config Integration Example

This example demonstrates integrating system libraries using pkg-config and macOS frameworks.

## What This Demonstrates

- Using `native.pkgConfig.makeLibrary` to wrap pkg-config libraries
- Using `native.pkgConfig.mkFrameworkLibrary` for macOS frameworks
- Combining multiple system libraries in one executable

## Project Structure

```
pkg-config/
├── flake.nix    # Build definitions with pkg-config libraries
├── main.cc      # Demo using zlib and curl
└── README.md
```

## Build and Run

```sh
nix build
./result/bin/pkgconfig-demo
```

Expected output:
```
pkg-config integration demo

=== zlib demo ===
zlib version: 1.3.1
Original size: 46 bytes
Compressed size: 52 bytes
Compression ratio: 113.043%

=== curl demo ===
curl version: 8.x.x
SSL version: OpenSSL/x.x.x
curl initialized successfully

All libraries working correctly!
```

## How It Works

### Wrapping pkg-config Libraries

```nix
# Simple case: module name matches library name
zlibLib = native.pkgConfig.makeLibrary {
  name = "zlib";
  packages = [ pkgs.zlib ];
};

# When module name differs from library name
curlLib = native.pkgConfig.makeLibrary {
  name = "curl";
  packages = [ pkgs.curl ];
  modules = [ "libcurl" ];  # pkg-config module name
};
```

This runs `pkg-config --cflags` and `pkg-config --libs` to extract:
- Include paths (`-I` flags)
- Preprocessor defines (`-D` flags)
- Link flags (`-l` and `-L` flags)

### macOS Framework Libraries

```nix
CoreFoundation = native.pkgConfig.mkFrameworkLibrary {
  name = "CoreFoundation";
  # framework defaults to name
  # sdk auto-detected from apple-sdk
};
```

This generates the proper `-framework` flags and SDK paths for macOS.

### Using in Executables

```nix
native.executable {
  name = "my-app";
  sources = [ "main.cc" ];
  libraries = [ zlibLib curlLib ];  # Just like any other library
};
```

## API Reference

### `native.pkgConfig.makeLibrary`

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Library name (for identification) |
| `packages` | Yes | - | Nix packages providing the library |
| `modules` | No | `[name]` | pkg-config module names |

### `native.pkgConfig.mkFrameworkLibrary`

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Library name |
| `framework` | No | `name` | Framework name |
| `sdk` | No | auto-detect | SDK root path |

## Common pkg-config Libraries

| Library | Package | Module |
|---------|---------|--------|
| zlib | `pkgs.zlib` | `zlib` |
| curl | `pkgs.curl` | `libcurl` |
| OpenSSL | `pkgs.openssl` | `openssl` |
| SQLite | `pkgs.sqlite` | `sqlite3` |
| libpng | `pkgs.libpng` | `libpng` |
| libjpeg | `pkgs.libjpeg` | `libjpeg` |

## Common macOS Frameworks

```nix
# Core frameworks
CoreFoundation = native.pkgConfig.mkFrameworkLibrary { name = "CoreFoundation"; };
Foundation = native.pkgConfig.mkFrameworkLibrary { name = "Foundation"; };
Security = native.pkgConfig.mkFrameworkLibrary { name = "Security"; };

# Graphics
Metal = native.pkgConfig.mkFrameworkLibrary { name = "Metal"; };
QuartzCore = native.pkgConfig.mkFrameworkLibrary { name = "QuartzCore"; };
Cocoa = native.pkgConfig.mkFrameworkLibrary { name = "Cocoa"; };

# Audio/Video
AVFoundation = native.pkgConfig.mkFrameworkLibrary { name = "AVFoundation"; };
AudioToolbox = native.pkgConfig.mkFrameworkLibrary { name = "AudioToolbox"; };
```

## Next Steps

- See `app-with-library/` for combining pkg-config with custom libraries
- See `protobuf/` for another pkg-config usage example
- See `library/` for creating your own libraries
