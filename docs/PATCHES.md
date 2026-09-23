# QEMU downstream patches & upstream-rebase notes

This tap builds QEMU from source and applies a small set of downstream patches
on top of upstream QEMU. This document explains **what each patch does**, **why
the audio changes existed**, and the **status/'how-to' of rebasing onto the
latest QEMU stable release (v11.1.1)**.

---

## 1. The patches

Applied by `Formula/qemu.rb` (in order):

| Patch | Scope | Purpose |
| --- | --- | --- |
| `patches/qemu-texture-borrowing.patch` | 135 hunks / 29 files | @akihikodaki's VirGL 3D macOS support (the core feature) |
| `patches/gpu-spike-resolution-fix.patch` | 2 hunks / `ui/cocoa.m` | Fixes a GPU-usage spike and a resolution/scaling glitch in the Cocoa GL path |

Other patches in `patches/` (`qemu-audio-coreaudio.patch`, `qemu-opengl41.patch`,
`qemu-virgl3d-macos*.patch`) are **not applied** by the formula — they are
earlier/alternative variants kept for reference. The audio changes were folded
into `qemu-texture-borrowing.patch`.

### What `qemu-texture-borrowing.patch` actually does

It ports @akihikodaki's upstream-in-progress work that makes `virtio-gpu-gl`
render on macOS through ANGLE/Metal. The central mechanism is **"texture
borrowing"**: instead of QEMU passing a raw GL/D3D texture handle to the display
backend, the GPU device hands the display a **callback**
(`DisplayGLTextureBorrower`) that lends the current scanout texture on demand.
This is what lets the Cocoa UI composite the guest's GPU output via an EGL/ANGLE
surface. It touches the console/display API (`ui/console.c`, `include/ui/console.h`),
the EGL helpers, the SDL/GTK/DBus/egl-headless listeners, `ui/cocoa.m` (the whole
Cocoa GL render path), and `hw/display/virtio-gpu-virgl.c`.

---

## 2. Why the audio patch was in place

The patch series bundled a **CoreAudio rework** (`audio/audio.c`,
`audio/audio_int.h`, `audio/coreaudio.m`). Two reasons it existed:

1. **Microphone / audio *input* support on macOS.** Upstream QEMU's CoreAudio
   backend was historically **playback-only**. The patch generalises the
   output-only plumbing to add capture: it renames `coreaudioVoiceOut` →
   `CoreaudioVoiceOut`, `voice_addr` → `voice_out_addr`,
   `coreaudio_get_voice` → `coreaudio_get_voice_out`,
   `coreaudio_get_framesize` → `coreaudio_get_out_framesize`, etc., so an
   equivalent **input** voice path can exist alongside. This gives a macOS guest
   a working line-in/microphone via `-audiodev coreaudio`.

2. **Dynamic buffer re-initialisation.** It adds
   `audio_generic_initialize_buffer_in()` / `audio_generic_initialize_buffer_out()`
   so the emulated audio buffer can be **rebuilt when the format changes at
   runtime** (e.g. the host default audio device / sample rate changes), instead
   of being allocated lazily exactly once. This makes CoreAudio more robust when
   devices are switched.

It is part of the same @akihikodaki macOS series as the GPU work, which is why it
rode along in the same patch — but it is **independent of GPU/Vulkan/Metal**.

### Why we dropped it when moving to v11.1.1

Between the patch's base and v11.1.1, upstream **rewrote the audio subsystem to a
QOM `AudioBackend` architecture**. `audio/audio.c` no longer aligns with the
patch at all — the 3-way merge produced a conflict spanning essentially the whole
file (`~1600` lines), and `audio/coreaudio.m` had 24 rejected hunks. That is a
**from-scratch re-port against a new architecture**, not a patch refresh.

Because the audio changes are **not required for the Vulkan/Metal goal** and
upstream `-audiodev coreaudio` playback already works without them, we reverted
`audio/` to pristine v11.1.1 (`git checkout v11.1.1 -- audio/`). The only thing
lost for now is the downstream **microphone-input** addition and the buffer
re-init robustness tweak.

---

## 3. Upstream pinning strategy

Historically the formula tracked upstream **`master`**, so the patches broke
whenever `master` drifted (that is the CI failure that prompted this work).

**Current approach: pin to the exact working commit.** `Formula/qemu.rb`
downloads a fixed upstream commit:

```
cf3e71d8fc8ba681266759bb6cb2e45a45983e3e   (QEMU master, 2026-01-13)
```

This is the commit the downstream patches were authored against and the one
`startergo`'s last known-good bottle (v1.0.27, Jan 2026) was built from. The
original patches apply to it with **zero rejects**, so no rebase is needed.

### Why not a release tag?

No QEMU **release tag** is compatible with the *original* patches. `cf3e71d8`
sits between v10.2 (Dec 2025) and v11.0 (Apr 2026), and the patches reject on
every release we tested (original `qemu-texture-borrowing.patch`):

| Ref | texture-borrowing result |
| --- | --- |
| `cf3e71d8` (pinned) | applies clean (0 rejects) |
| v10.2.0 / v10.2.4 | reject: audio.c, coreaudio.m, sdl2.h, cocoa.m |
| v11.0.0 | reject: audio.c (3/3), coreaudio.m (24/24), sdl2.h (1/3), cocoa.m (2/33) |
| v11.0.4 | rejects (more than v11.0.0) |
| v11.1.1 | reject: 8 files / 37 hunks (adds the `dpy_gl_*`→`qemu_console_gl_*` rename) |

Pinning to the commit keeps the build reproducible and lets us use the original
patches unmodified. Moving to a release **requires rebasing the patches** (see
below), which for v11.1.1 also means dropping audio (the QOM `AudioBackend`
rewrite) and reworking `ui/cocoa.m` for the new DCL-registration API.

## 3b. (Optional) Rebasing onto a QEMU stable release

If you later want a release instead of a pinned commit, rebase the patches.

### Method — git 3-way (do NOT hand-edit `.rej` files)

The patches carry `index` blob lines, so let git do the merge:

```bash
CA=$HOME/.config/homebrew-certs/ca.pem   # corporate proxy CA, if needed
export GIT_SSL_CAINFO=$CA CURL_CA_BUNDLE=$CA

cd /tmp && rm -rf qemu-rebase && mkdir qemu-rebase && cd qemu-rebase
git init -q && git remote add origin https://gitlab.com/qemu-project/qemu.git
# base = the commit the patches were authored against:
git fetch -q --depth 1 origin cf3e71d8fc8ba681266759bb6cb2e45a45983e3e
git tag base cf3e71d8fc8ba681266759bb6cb2e45a45983e3e
git fetch -q --depth 1 origin refs/tags/v11.1.1:refs/tags/v11.1.1

# apply the patches on their own base (they apply cleanly there) and commit each
git checkout -q base
patch -p1 --batch -i <tap>/patches/qemu-texture-borrowing.patch && git add -A && git commit -qm tb
patch -p1 --batch -i <tap>/patches/gpu-spike-resolution-fix.patch && git add -A && git commit -qm gs
git branch work

# replay onto stable with 3-way merge
git rebase --onto v11.1.1 base work
# ...resolve conflicts, git add, git rebase --continue...
```

When finished, regenerate the two patches and point the formula at the release:

```bash
git format-patch v11.1.1..work -o /tmp/out      # 2 patches
# copy back to patches/, then in Formula/qemu.rb change the source download
# from .../archive/master/qemu-master.tar.gz to the v11.1.1 archive, and bump version.
```

### Status of the current rebase attempt

Base commit the patches were written for: `cf3e71d8` (a QEMU master snapshot,
~Jan 2026). Every upstream `startergo` release also pinned to this commit.

- `gpu-spike-resolution-fix.patch` — **applies cleanly** to v11.1.1.
- `qemu-texture-borrowing.patch` — 8 files conflicted:
  - **Resolved cleanly (display/GPU):** `include/ui/console.h`, `ui/console.c`,
    `include/ui/sdl2.h`, `ui/egl-helpers.c`, `hw/display/virtio-gpu-virgl.c`.
  - **Dropped:** `audio/audio.c`, `audio/coreaudio.m` (see §2).
  - **Still to finish:** `ui/cocoa.m` (see §4).

> The rebase lives in the throwaway `/tmp/qemu-rebase`. Nothing in this repo has
> been modified yet — the patches here are still the originals.

### Upstream API changes encountered (reference for the resolver)

1. **Console GL helpers renamed:** public `dpy_gl_scanout_*()` →
   `qemu_console_gl_scanout_*()`. The `DisplayChangeListener` **ops member** is
   still `.dpy_gl_scanout_texture` (unchanged). Resolution kept upstream names.
2. **`dpy_gl_scanout_texture` signature:** old
   `(con, id, bool y_0_top, w, h, x, y, w, h, void *d3d_tex2d)` →
   new `(con, id, DisplayGLTextureBorrower backing_borrow, x, y, w, h)`.
3. **`qemu_egl_get_display()`** stays public (used by `ui/sdl2.c`); the patch's
   `qemu_egl_init_dpy_platform()` was reimplemented on top of it (kept both).
4. **DCL registration:** `register_displaychangelistener(&dcl)` was **removed** →
   `qemu_console_register_listener(con, &dcl, &ops)`. Struct members `.ops` and
   `.con` still exist, so runtime ops-swapping still compiles.
5. **Audio:** rewritten to QOM `AudioBackend` (`default_audio_be`) — the reason
   the audio hunks no longer rebase.

---

## 4. Finishing `ui/cocoa.m` (remaining work)

`ui/cocoa.m` has three conflict regions caused by the DCL-registration refactor:

- **Declarations block (~line 87):** take the patch side
  (`static DisplayChangeListener dcl; static DisplaySurface *surface;`). Do **not**
  keep upstream's top `dcl_ops` here — the patch defines its own richer `dcl_ops`
  (with GL scanout callbacks) later in the file; keeping both duplicates the
  symbol. Verify the upstream call site that references `dcl_ops` still has one in
  scope.
- **Keycode map (~line 295):** take **upstream** (`cocoa_keycode_to_linux` /
  `qemu_input_map_osx_to_linux`); the patch's `*_to_qcode` names don't exist in
  v11.1.1.
- **Registration (~line 2571):** replace every
  `register_displaychangelistener(&dcl)` with
  `qemu_console_register_listener(qemu_console_lookup_default(), &dcl, dcl.ops)`
  and check `unregister_displaychangelistener()` still exists.

This must be **compile-verified via CI** (the ~1h GitHub Actions build) — there is
no local build because of the corporate proxy.

## 5. Re-enabling audio later (optional)

To restore microphone input, the CoreAudio input work must be **re-ported against
the new QOM `AudioBackend`** in `audio/`. Alternatively, track upstream QEMU —
akihikodaki's CoreAudio input support may land upstream, at which point no
downstream patch is needed.
