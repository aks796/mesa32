# mesa32

**Mesa and libdrm_nouveau for 32-bit (AArch32) Nintendo Switch programs**

OpenGL ES and EGL for 32-bit Switch programs, on the Tegra X1 GPU through
Mesa's Nouveau driver.

This is a fork of [devkitPro's Switch Mesa](https://github.com/devkitPro/mesa)
(Mesa 20.1.0-rc3, the same Mesa as their `switch-mesa` package) with fixes for
building and running it as AArch32. devkitPro only ships Mesa for 64-bit
programs. It builds with [libnx32](https://github.com/aks796/libnx32) in
vita2hos's AArch32 toolchain image.

It runs on hardware in several 32-bit ports of Android games, for GLES 1, 2
and 3.

---

## What you get

Static libraries for AArch32 (ARMv8-A, softfp, NEON), with headers and
pkg-config files:

* `libEGL.a`: EGL with the Switch platform (NWindow surfaces) and the Nouveau
  Gallium driver
* `libGLESv2.a`: OpenGL ES 2.0 and 3.x (up to 3.2)
* `libGLESv1_CM.a`: OpenGL ES 1.1
* `libglapi.a`
* `libdrm_nouveau.a`: devkitPro's libdrm_nouveau 1.0.1, the glue between
  Nouveau and the Switch's nvgpu/nvmap services. The build downloads it from
  devkitPro's repository and checks the commit.

Link them into your program. There are no shared libraries on the Switch.

---

## How this differs from devkitPro's Mesa

The changes are the commits on top of devkitPro's `switch-20.1.0-rc3` branch:

* **Python 3.9+**: Mesa's code generators used `getchildren()`, which newer
  Python removed. The same fix as devkitPro's `switch-mesa` package.
* **Short enums**: values that do not fit a short enum (below).
* **ETC2 and ASTC in hardware**: the Switch's libdrm reports the GPU as
  chipset 0x120, so they were decoded in software.
* **Textures without storage**: one attached to a framebuffer is incomplete,
  not a NULL dereference.
* **glthread** on the Switch, opt-in per context (below).
* **`eglQuerySurface(EGL_WIDTH / EGL_HEIGHT)`** returned 0 for window surfaces.
* **`thrd_success`**: newlib defines it as 4, not 0, so Mesa took running
  threads for failures.
* The build scripts and this README.

**Short enums.** devkitARM makes enums as small as their values
(`-fshort-enums`), and libnx32 is built that way, so Mesa is too, to keep
struct layouts the same. Mesa kept a few values in enum types that do not fit:
`mesa_format` is 16 bits here but holds `MESA_ARRAY_FORMAT` values such as
`0x80068890`. The format code in `st_format.c`, `glformats.c` and `formats.c`
uses `uint32_t` for those values, `tgsi_info.h`'s opcode bitfield is
`unsigned`, and one prototype in `tgsi_ureg.c` is fixed. Do not widen
`enum pipe_format` instead: that changes bitfield layouts.

**glthread.** Mesa's glthread runs a context's GL calls on a worker thread. To
use it, call this before the context is first made current, from the thread
that will use it:

```c
EGLBoolean switch_egl_start_glthread(EGLDisplay dpy, EGLContext ctx);
```

The worker calls `void switch_egl_glthread_hook(void)` once when it starts, if
the program defines it, for example to set the thread's priority and cores.

---

## Requirements

* Docker
* The AArch32 toolchain image `ghcr.io/vita2hos/devcontainer/vita2hos`, which
  has devkitArm, Meson and Ninja
* [libnx32](https://github.com/aks796/libnx32), built

---

## Building

Build libnx32 first. With a libnx32 checkout next to this one:

```text
libnx32/
mesa32/
```

```bash
(cd libnx32 && ./build.sh)
(cd mesa32 && ./build.sh)
```

`build.sh` builds in the toolchain image, with libnx32's files mounted over
the image's stock ones. To use a libnx32 installed somewhere else:

```bash
LIBNX32=/path/to/libnx32/prefix ./build.sh
```

The libraries are installed into `prefix/`:

```text
prefix/
├── include/
│   ├── EGL/  GLES/  GLES2/  GLES3/  KHR/  GL/
│   └── nouveau.h, nouveau_drm.h, nvif/
└── lib/
    ├── libEGL.a
    ├── libGLESv1_CM.a
    ├── libGLESv2.a
    ├── libglapi.a
    ├── libdrm_nouveau.a
    └── pkgconfig/
```

A full build takes a while under Docker's x86 emulation. `build.sh` also takes
a step: `drm`, `mesa-setup`, `mesa` or `install`. Build files go into
`build/`, with libdrm_nouveau's source and the Meson cross file
(`build/switch32_cross.txt`).

---

## Using it

Compile with the same flags as libnx32:

```text
-march=armv8-a+crc+crypto -mtune=cortex-a57 -mfloat-abi=softfp
-mfpu=neon-fp-armv8 -mtp=soft -fPIE -ftls-model=local-exec
```

and link with, in this order:

```text
-lEGL -lGLESv2 -lglapi -ldrm_nouveau -lstdc++ -lnx -lm
```

For GLES 1, use `-lGLESv1_CM` in place of `-lGLESv2`. The two define some of
the same functions, so link one of them. Create the EGL window surface on
libnx's default window (`nwindowGetDefault()`).

Things to know:

* The GPU's memory comes from the process heap: libdrm_nouveau allocates its
  buffers there and hands them to nvmap. Leave free heap for it.
* The EGL platform has window surfaces only. `eglCreatePbufferSurface` returns
  `EGL_NO_SURFACE`. Contexts can be made current without a surface
  (`EGL_KHR_surfaceless_context`). There are no MSAA configs, and unknown
  config attributes are rejected.
* Mesa registers 3 buffer slots on the window, and libnx's console uses 2.
  Giving the window back to the console after EGL used it fails on the
  console's third frame (`BadGfxDequeueBuffer`). Close the console for good
  before EGL takes the window.

---

## Upstream

* Mesa: [gitlab.freedesktop.org/mesa/mesa](https://gitlab.freedesktop.org/mesa/mesa)
* devkitPro's Switch Mesa: [github.com/devkitPro/mesa](https://github.com/devkitPro/mesa)
* libdrm_nouveau: [github.com/devkitPro/libdrm_nouveau](https://github.com/devkitPro/libdrm_nouveau)

Problems that are not specific to the Switch or to AArch32 belong upstream.
Mesa's own README is kept as `README.mesa.rst`.

---

## Credits

**AArch32 build and fixes**: aks796

Mesa is by the Mesa developers. The Switch port of Mesa and libdrm_nouveau are
by devkitPro. libdrm_nouveau derives from libdrm by Red Hat and others.

The AArch32 toolchain and libnx port are by [xerpi](https://github.com/xerpi),
from [vita2hos](https://github.com/xerpi/vita2hos).

---

## License

MIT, like upstream Mesa and libdrm_nouveau. Individual files carry their own
license headers. See [docs/license.html](docs/license.html).
