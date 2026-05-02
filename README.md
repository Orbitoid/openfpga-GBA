# GBA for Analogue Pocket

[![Latest Release](https://img.shields.io/github/v/tag/Orbitoid/openfpga-GBA?label=latest)](https://github.com/Orbitoid/openfpga-GBA/releases/latest) [![Downloads](https://img.shields.io/github/downloads/Orbitoid/openfpga-GBA/total)](https://github.com/Orbitoid/openfpga-GBA/releases) [![Platform](https://img.shields.io/badge/platform-Analogue%20Pocket-blue)](https://openfpga-library.github.io/analogue-pocket/)

Analogizer-maintained fork by Orbitoid, based on [mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA), an LLM-assisted port of [MiSTer GBA core](https://github.com/MiSTer-devel/GBA_MiSTer).

## Features

- **Cart Saves**
- **Filters**
- **Save States**
- **Fast Forward (Bound to Y button)**
- **RTC**
- **Analogizer Build** — Separate `GBA_Analogizer` core package with cartridge adapter support for Analogizer-FPGA analog video output.
- **FORCE RTC** — Manually enables RTC for ROMs that aren't in the database. This is useful for ROM hacks that add RTC support to games that don't normally use it (like a certain "unbound" hack). Make sure to enable this on first load of the hack, ideally as soon as possible during the bios display to avoid any issues with initializing the save. **USE WITH CAUTION:** enabling this on a game that doesn't actually use RTC can cause crashes or glitches.
### **⚠️WARNING: Forced RTC setting persists across games! Remember to turn it off before loading a game that doesn't need it⚠️**

##  Currently Not Included

- **Link Cable** - working on it
- **Gyroscope**
- **Solar Sensor**
- **Cheats**
- **Rewind**
- **Color correction outside default pocket filters**

The original MiSTer core was built for an FPGA chip roughly twice the size of the one inside the Analogue Pocket. Some extras had to go to make it all fit. The original Pocket port prioritized things that could be fixed with romhacks, for example there is a solar patch that fixes these issues without the core needing to do anything.

## RTC and Save Compatibility

When a game uses RTC (either detected automatically or forced on), the core appends RTC data to the end of the save file. This makes the save file larger than a standard GBA save. If you then try to load that save on a GBA core that doesn't support RTC, it will fail with an error because the save file size doesn't match what the core expects. To use the save on a non-RTC core, you would need to trim the extra RTC bytes from the end of the file to restore it to its original size.

The following tools can strip RTC data from a save file:
- [mGBA](https://mgba.io/) — The built-in Save Converter tool (Tools → Save Converter) can export saves with RTC data stripped. Requires mGBA v0.10.3 or later.
- [save-file-converter](https://github.com/euan-forrester/save-file-converter) — A web-based tool that can convert and resize save files across many retro formats.

## Accuracy

This core more or less replicates the current accuracy of the MiSTer GBA core. The features that were cut to fit the smaller FPGA were convenience features, not accuracy-related logic. It scores similarly to the MiSTer core in the mGBA test suite. If you encounter an Analogizer-specific issue, please open it on this fork.

note: MiSTer core has an accuracy branch. A few of those changes have made it into this core but the bulk is still wip on a different branch.

## Installation

The Analogizer core should be available from this fork's releases, or you can install manually:

1. Download the latest release
2. Copy the 3 folders `Cores/`, `Platforms/`, `Assets/` to your SD card
   - **macOS users:** Finder replaces folders instead of merging them, so copy folder contents carefully.
3. Place your ROMs and `gba_bios.bin` in `/Assets/gba/common/`
4. Launch `GBA_Analogizer` on the Pocket when using the Analogizer-FPGA adapter

## Analogizer Support

This branch also builds a separate core named `GBA_Analogizer` in `Cores/Orbitoid.GBA_Analogizer/`. It enables the Pocket cartridge adapter pins for Analogizer-FPGA and uses a dedicated CRT raster path instead of sending the Pocket scaler output to the adapter.

The Analogizer build currently supports:

- **RGBS**
- **RGsB**
- **Y/C NTSC**
- **Y/C PAL**
- **Pocket OFF** variants for the same video outputs

The `CRT Scale` core setting controls how the 240x160 GBA framebuffer is mapped to the 15 kHz Analogizer output:

- **Aspect / Blend +12.5%** — Default larger blended mode, 360x180 output clocks.
- **Aspect / Blend** — 320-wide output with horizontal interpolation.
- **No Scale / Square** — 240-wide output with square source pixels.
- **Small / Stretch** — 320-wide nearest-neighbor output.
- **Wide / Overscan** — 448-wide output for wider CRT fill.

The Analogizer video path uses `clk_vid` timing at about 15.65 kHz / 59.7 Hz, prefetches each GBA line through a small line buffer, and shares the existing framebuffer read port with the Pocket video adapter. Pocket screen output remains available unless a `Pocket OFF` Analogizer mode is selected.

## Known Issues

- **Fast forward speed varies by game** — Games that make heavy use of the GBA's slower external RAM will not fast-forward as quickly as games that primarily use internal RAM. This is most noticeable with the Classic NES Series titles.
- **Analogizer support is a separate core** — Use `GBA_Analogizer`, not the normal `GBA` core, when using the Analogizer adapter.
- **Analogizer output depends on CRT/display tolerance** — The CRT path targets about 15.65 kHz / 59.7 Hz. Some displays or scalers may need a different scale mode or video output type.

## Building from Source

The Analogizer build is self-contained in this repo. A fresh clone plus Docker is enough to build the Quartus bitstream and generate a ready-to-copy SD card package.

### Prerequisites

- Docker
- `raetro/quartus:21.1` Docker image
- Python 3 on the host, used after Quartus to reverse the generated bitstream
- `zip` is optional; when present, the build script also creates a local SD card package archive

### Build Analogizer

```bash
docker pull raetro/quartus:21.1
./scripts/build_analogizer.sh
```

The script runs Quartus inside Docker, reverses the generated `.rbf`, writes the Pocket bitstream to `pkg/Cores/Orbitoid.GBA_Analogizer/bitstream.rbf_r`, and prints the timing summary. If `zip` is installed, it also creates `build_output/Orbitoid.GBA_Analogizer-dev.zip` with the same SD card layout used by releases.

### Install A Local Build

After a successful build, either unzip `build_output/Orbitoid.GBA_Analogizer-dev.zip` to the root of your Pocket SD card, or manually copy these folders from `pkg/` to the SD card root:

```bash
Cores/
Platforms/
Assets/
```

Place ROMs and `gba_bios.bin` in `/Assets/gba/common/` on the SD card. Use the `GBA_Analogizer` core, not the normal `GBA` core, when connecting the Analogizer-FPGA adapter.

### Build Normal Pocket Core

The original non-Analogizer Pocket build is still available for comparison:

```bash
./scripts/build.sh
```

### Background Build

To run Quartus in the background:

```bash
./scripts/quartus-build-bg.sh start
./scripts/quartus-build-bg.sh status
./scripts/quartus-build-bg.sh wait
```

For the Analogizer build:

```bash
./scripts/quartus-build-bg.sh --analogizer start
./scripts/quartus-build-bg.sh --analogizer status
./scripts/quartus-build-bg.sh --analogizer wait
```


## Credits

- **[MiSTer GBA core](https://github.com/MiSTer-devel/GBA_MiSTer)** — original FPGA GBA implementation
- **[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)** — original Analogue Pocket port this Analogizer fork is based on
- **[Analogue openFPGA](https://www.analogue.co/developer)** — platform framework and core template
- **[budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC)** — reference for MiSTer-to-Pocket porting patterns
- **[agg23](https://github.com/agg23)** — analogue-pocket-utils and reference SNES/NES Pocket cores
- **[RndMnkIII Analogizer](https://github.com/RndMnkIII/Analogizer)** — Analogizer-FPGA adapter and openFPGA interface modules

## License

GPL-2.0 — see [GBA_MiSTer LICENSE](https://github.com/MiSTer-devel/GBA_MiSTer/blob/master/LICENSE) for details.
