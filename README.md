# homebrew-qemu-virgl-kosmickrisp

[![Build Status](https://img.shields.io/github/actions/workflow/status/mikeeq/homebrew-qemu-virgl-kosmickrisp/bottle.yml?branch=master&label=bottle%20build&logo=github&style=flat-square)](https://github.com/mikeeq/homebrew-qemu-virgl-kosmickrisp/actions/workflows/bottle.yml)

Homebrew tap for [QEMU](https://www.qemu.org/) - A generic and open source machine emulator and virtualizer, built for macOS with virglrenderer, ANGLE, and KosmicKrisp support for GPU acceleration.

> Fork of [startergo/homebrew-qemu-virgl-kosmickrisp](https://github.com/startergo/homebrew-qemu-virgl-kosmickrisp) that additionally builds QEMU with **libslirp** so rootless user-mode networking (`-netdev user`) is available. Bottles are published to this fork's releases; the GPU dependency taps (`angle`, `libepoxy`, `virglrenderer`) are reused from `startergo`.

## What is QEMU?

QEMU is a free and open-source emulator and virtualizer that can perform hardware virtualization. When combined with virglrenderer and KosmicKrisp, it provides accelerated 3D graphics and Vulkan support for guest operating systems.

## Installation

### From Bottle (Recommended - Pre-built Binary)

```bash
# Tap the repository
brew tap mikeeq/qemu-virgl-kosmickrisp

# Install qemu (downloads pre-built bottle)
brew install mikeeq/qemu-virgl-kosmickrisp/qemu
```

### From Source

Build from source if you need to modify the formula, apply custom patches, or the bottle is unavailable for your macOS version:

```bash
# Tap the repository
brew tap mikeeq/qemu-virgl-kosmickrisp

# Install and build from source
brew install --build-from-source mikeeq/qemu-virgl-kosmickrisp/qemu

# Or use the shorthand
brew install -s mikeeq/qemu-virgl-kosmickrisp/qemu
```

**Build from source notes:**
- Build time: ~30-60 minutes on Apple Silicon M1/M2/M3 (depending on CPU cores)
- Disk space required: ~4GB for build artifacts
- Requires Xcode Command Line Tools: `xcode-select --install`
- The formula will download and build:
  - QEMU from upstream GitLab master
  - Vulkan SDK with KosmicKrisp component
  - Apply all patches automatically

**Troubleshooting build failures:**

If the build fails, you can inspect the build logs:

```bash
# Show build logs
brew config
brew install --verbose --build-from-source mikeeq/qemu-virgl-kosmickrisp/qemu

# Or access logs after failed build
cat ~/Library/Logs/Homebrew/qemu/*.log
```

## Dependencies

This tap requires the following taps:
- [startergo/virglrenderer](https://github.com/startergo/homebrew-virglrenderer) - Virtual 3D GPU renderer
- [startergo/libepoxy](https://github.com/startergo/homebrew-libepoxy) - OpenGL function pointer management
- [startergo/angle](https://github.com/startergo/homebrew-angle) - OpenGL ES implementation for macOS

## Usage

### Display Options

The `-display cocoa` backend supports OpenGL rendering modes via the `gl=` option:

- `gl=on` - Enable OpenGL rendering with compatibility profile
- `gl=off` - Disable OpenGL rendering (default)
- `gl=core` - Use OpenGL Core profile (recommended for modern OpenGL)
- `gl=es` - Use OpenGL ES via ANGLE (for ES 2.0/3.0 support)

### Basic VM with virtio-gpu

```bash
qemu-system-x86_64 \
  -display cocoa,gl=core \
  -device virtio-gpu-pci \
  ...
```

### With Vulkan (Venus) support

Venus is a modern virtio-gpu Vulkan transport available in QEMU v9.2.0 and later. The Vulkan runtime (loader, driver, ICD) is installed with QEMU at:
```
$(brew --prefix qemu)/lib/libvulkan.dylib
$(brew --prefix qemu)/lib/libvulkan_kosmickrisp.dylib
$(brew --prefix qemu)/share/vulkan/icd.d/libkosmickrisp_icd.json
```

**Requirements:**
- macOS 15+ (Sequoia) on Apple Silicon for full Vulkan 1.3 conformance
- LunarG Vulkan SDK 1.4.335.1 (KosmicKrisp bundled with QEMU)

```bash
export VK_DRIVER_FILES=$(brew --prefix qemu)/share/vulkan/icd.d/libkosmickrisp_icd.json
export VK_ICD_FILENAMES=$(brew --prefix qemu)/share/vulkan/icd.d/libkosmickrisp_icd.json

qemu-system-x86_64 \
  -accel hvf \
  -display cocoa,gl=core \
  -device virtio-gpu-pci,vulkan=on,hostmem=4G \
  ...
```

**Guest OS requirements:** Linux guest with Mesa 25.1+ for Venus support. Verify inside guest:
```bash
vulkaninfo | grep "device name"
```
Should report virtio-gpu device powered by host's KosmicKrisp.

Note: The KosmicKrisp driver (ICD file + dylib) is bundled with QEMU. No separate Vulkan SDK installation is required.

### Networking (rootless)

This fork compiles QEMU with **libslirp**, so user-mode networking works without
root:

```bash
qemu-system-aarch64 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  ...
```

The guest gets a NAT address (`10.0.2.15`, gateway `10.0.2.2`, DNS `10.0.2.3`)
and you can reach it from the host via the forwarded port
(`ssh -p 2222 <user>@localhost`).

> A real LAN IP (bridged) requires the `vmnet-bridged` backend, which needs
> **root** on macOS and cannot bridge over Wi-Fi. User-mode NAT is the only
> rootless option.

## What's Included

- **QEMU system binaries**: qemu-system-x86_64, qemu-system-aarch64, qemu-system-i386
- **QEMU tools**: qemu-img, qemu-nbd, qemu-keymap, etc.
- **virtio-gpu-gl support**: Enabled with virglrenderer integration
- **OpenGL ES support**: Via ANGLE through virglrenderer
- **Venus support**: Modern virtio-gpu Vulkan transport via LunarG Vulkan SDK (includes KosmicKrisp, a Vulkan-to-Metal layered driver for Apple Silicon)
- **UI backends**: Cocoa, SDL (GTK disabled to avoid dependency conflicts)

## Build Configuration

This build is configured for macOS with GPU acceleration support:
- **virglrenderer support**: Uses [startergo/virglrenderer](https://github.com/startergo/homebrew-virglrenderer) for GPU acceleration
- **OpenGL ES support via ANGLE**: Through virglrenderer dependency
- **OpenGL support via libepoxy**: Through virglrenderer dependency
- **Venus support**: Modern virtio-gpu Vulkan transport via LunarG Vulkan SDK (includes KosmicKrisp, a Vulkan-to-Metal layered driver for Apple Silicon)
- **Target architectures**: x86_64, aarch64, arm, and more
- Builds against upstream QEMU master

## Patches

This tap applies the following patches to upstream QEMU:
- **[qemu-virgl3d-macos.patch](patches/qemu-virgl3d-macos.patch)**: @akihikodaki's VirGL 3D macOS support with ANGLE Metal backend ([upstream PR](https://patchew.org/search?q=project%3AQEMU+from%3Aakihiko.odaki%40gmail.com))
- **[qemu-audio-coreaudio.patch](patches/qemu-audio-coreaudio.patch)**: Audio/coreaudio improvements for macOS

These patches enable:
- `-display cocoa,gl=core` - OpenGL Core profile via OpenGL.framework
- `-display cocoa,gl=es` - OpenGL ES via ANGLE with Metal backend

## Development

This repo uses [pre-commit](https://pre-commit.com/) to validate changes to the
formula and the CI workflow.

```bash
# Install pre-commit (pick one)
brew install pre-commit
pipx install pre-commit

# Enable the git hook and run against everything
pre-commit install
pre-commit run --all-files
```

Hooks run:
- generic hygiene (trailing whitespace, EOF, merge markers, LF endings, large files, YAML parse)
- `actionlint` - lints `.github/workflows/*.yml` (and shellchecks inline `run:` scripts)
- `shellcheck` - lints standalone shell scripts (e.g. [scripts/build.sh](scripts/build.sh))
- `yamllint` - YAML style (see [.yamllint.yml](.yamllint.yml))
- `brew style` + `ruby -c` - Homebrew formula lint and syntax check

### Building locally

To build from this checkout instead of CI, use [scripts/build.sh](scripts/build.sh).
It links this working copy as a local tap and builds the formula:

```bash
scripts/build.sh                 # build from source and install
BOTTLE=1 scripts/build.sh        # build a redistributable bottle
SIGN=1 scripts/build.sh          # also re-sign + add the HVF entitlement
```

Behind a corporate TLS proxy, point it at your root CA (it wires the cert into
Homebrew's curl, pip, git and meson):

```bash
SRC_CERT=/path/to/ca.pem scripts/build.sh
```

### Building bottles on CI

Bottles are built by [.github/workflows/bottle.yml](.github/workflows/bottle.yml)
on GitHub-hosted macOS runners (which have clean internet, avoiding local
corporate-proxy TLS issues). Trigger a release build manually from the Actions
tab (**Build Bottles > Run workflow**, `release: true`), or wait for the weekly
schedule. The workflow is fork-agnostic - it derives the owner/repo from
`github.repository`, so no hardcoded account names need editing.

## License

GPL-2.0-or-later

## Upstream

- **[QEMU](https://www.qemu.org/)**: Generic and open source machine emulator and virtualizer
- **[virglrenderer](https://gitlab.freedesktop.org/virgl/virglrenderer)**: Virtual 3D GPU renderer (via [startergo/homebrew-virglrenderer](https://github.com/startergo/homebrew-virglrenderer))
- **[ANGLE](https://chromium.googlesource.com/angle/angle)**: OpenGL ES implementation for macOS (via [startergo/homebrew-angle](https://github.com/startergo/homebrew-angle))
- **[libepoxy](https://github.com/anholt/libepoxy)**: OpenGL function pointer management (via [startergo/homebrew-libepoxy](https://github.com/startergo/homebrew-libepoxy))
- **[LunarG Vulkan SDK](https://vulkan.lunarg.com/doc/sdk/1.4.335.1/mac/release_notes.html)**: Vulkan SDK for macOS (includes KosmicKrisp, a Vulkan-to-Metal layered driver for Apple Silicon, currently in alpha)

This tap builds against the latest upstream QEMU with macOS-specific optimizations for graphics acceleration.
