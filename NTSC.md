# RAD-Doom for NTSC machines

This is a fork of [frntc/RAD-Doom](https://github.com/frntc/RAD-Doom) (release v01). It adapts RAD-Doom's screen transfer timing to NTSC C64s. The original is set up for PAL machines only. All credit for RAD-Doom goes to its author; this fork only changes the raster timing and documents how to rebuild the kernels.

**Tested on:** an NTSC C64 with a Commodore 1702 monitor, with a RAD Expansion Unit on a Raspberry Pi Zero 2 W, using SID audio. `kernel_doom_ntsc.img` booted and ran reliably (6 of 6 boots). The MIDI and Digimax variants are built the same way but have not been tested on hardware.

## Installation

1. Set up the SD card as described in the [original README](README.md#quickstartsetup): the official v01 release archive, `doom1.wad` and `soundfont.sf2`.
2. Download the kernels from this repository's [releases](../../releases) and copy them to the root of the SD card, next to the official kernels.
3. In `config.txt`, enable exactly one `kernel=` line, for example:

   ```
   kernel=kernel_doom_ntsc.img
   ```

| kernel | sound |
|---|---|
| `kernel_doom_ntsc.img` | SID (sound effects and music) |
| `kernel_doom_midi_sequential_ntsc.img` | SID effects, music via Sequential MIDI interface (or SIDKick) |
| `kernel_doom_midi_datel_ntsc.img` | SID effects, music via Datel MIDI interface |
| `kernel_doom_digimax_ntsc.img` | Digimax on the user port |

On PAL machines these kernels behave exactly like the official ones: the PAL timing values are unchanged.

## What was changed

`blitScreenDOOM()` in `Source/rad_doom_hijack.cpp` schedules the transfer of each frame to the C64 so that it ends in the border area. The official code hard-codes PAL timing: 312 raster lines of 63 cycles. The patch takes the timing from the VIC-II type detected by RAD-Doom's `checkForNTSC()`:

| VIC-II | raster lines | cycles per line |
|---|---|---|
| PAL 6569 | 312 | 63 |
| NTSC 6567R56A | 262 | 64 |
| NTSC 6567R8 | 263 | 65 |

The patch uses these values to compute the cycles per 8 raster lines (7 normal lines plus 1 badline), the raster line wrap-around, and the longest transfer that still fits into the border.

The patch also adds five `nop`s. They keep the inner blit loop at the same cache line offset as in the official kernel, so the loop's C64 bus timing is not affected by the added code.

## Building

RAD drives the C64 bus with cycle-exact timing from the Raspberry Pi, and it turned out to be sensitive to how the kernel is built. Kernels built with the Circle version and `sysconfig.h` from the [RAD repository](https://github.com/frntc/RAD) failed on real hardware: they showed a garbled blue screen or froze at the title screen. A Circle Step45 build with RAD's settings booted at first, then failed repeatedly.

The build below reproduces the official v01 kernels. The unpatched build has exactly the same size as the official kernel, and all RAD-Doom code and data sit at the same addresses. It uses:

- **gcc 10.3-2021.07** (`aarch64-none-elf`)
- **circle-stdlib v15.14** with **Circle Step45** (`6a6e3758`) and **circle-newlib** `343aa586`
- **`ntsc/circle45-raddoom.patch`** applied to Circle. This is the configuration found in the official kernel binary:
  - `KERNEL_MAX_SIZE` of 256 MB
  - `REALTIME`, `NO_USB_SOF_INTR`, `NO_CALIBRATE_DELAY` and `NO_SD_HIGH_SPEED`
  - `NO_BUSY_WAIT` *not* set
  - a `free()` that does nothing, as in the official kernel
- **a build tree path exactly 30 characters long**, like the author's `/mnt/c/Work/Code/circle-stdlib`. newlib embeds its source paths, so the path length shifts data in the kernel.

### Which of these matter

Boot tests on the NTSC C64 (5 cold boots per kernel, all successful) narrowed this down:

- **The disabled `free()` is not needed.** A kernel with Circle's normal `free()` worked reliably. The patch keeps it disabled only so that the build matches the official kernel.
- **The memory layout is not critical.** In a test kernel, extra code and data were inserted into the Doom part, the way a different game would change it. That moved everything after RAD's code, including RAD's own data, to new addresses and new positions within cache lines. The kernel worked reliably. The 30-character path only matters for a byte-identical rebuild.

So the earlier failures most likely came from the Circle settings: RAD's `sysconfig.h` sets `NO_BUSY_WAIT`, a 64 MB `KERNEL_MAX_SIZE` and delay calibration. Which of the three causes the failures has not been narrowed down further, so keep the compiler, Circle version and `sysconfig.h` as listed above.

`ntsc/build.sh` does all of this. It downloads the pieces, builds Circle and newlib, and builds the four kernels into `ntsc/out/`:

```
ntsc/build.sh            # build tree in $HOME, or: ntsc/build.sh /tmp
```

A clean run takes about a minute on a modern PC. The kernels it produces are byte-for-byte identical to the release kernels, except for the embedded build path string. It needs `curl`, `make`, `patch` and a Linux x86-64 host. It downloads gcc 10.3 if that compiler is not on the `PATH` or in `/opt`.

To build a single variant by hand, edit `Source/rad_doom_defs.h` in the build tree:

- **MIDI:** enable `USE_MIDI`. For Datel, also set `MIDI_ADDRESS` to `0xDE04`.
- **Digimax:** enable `USE_DIGIMAX`.

Then run `make` in `RAD-Doom/Source`.

## License

GPL-3.0, like RAD-Doom (see [LICENSE](LICENSE)).
