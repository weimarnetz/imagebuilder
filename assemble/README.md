# Weimarnetz Firmware Assembly

This directory contains scripts for assembling OpenWrt firmware images.

## ImageBuilder Download Configuration

The scripts use a fallback mechanism for downloading OpenWrt ImageBuilders. If the primary source (builds.weimarnetz.de) is unavailable, the system will try alternative sources defined in `ib_sources.conf`.

### How it works

1. The script first attempts to download the ImageBuilder from the primary URL.
2. If that fails, it searches for matching entries in `ib_sources.conf`.
3. The file contains entries in the format: `OPENWRT_VERSION|TARGET|URL`
4. Wildcard patterns (e.g., `23.05.*`) are supported for version and target matching.
5. URLs can contain placeholders like `%OPENWRT%`, `%MAINTARGET%`, `%SUBTARGET%`, and `%EXTENSION%`.

### Customizing ImageBuilder Sources

You can add or modify alternative ImageBuilder download sources by editing `ib_sources.conf`. Example entries:

```
# Specific version and target
23.05.5|ath79_generic|https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-imagebuilder-23.05.5-ath79-generic.Linux-x86_64.tar.xz

# All 23.05.x versions for a specific target
23.05.*|ramips_mt7621|https://downloads.openwrt.org/releases/23.05.5/targets/ramips/mt7621/openwrt-imagebuilder-23.05.5-ramips-mt7621.Linux-x86_64.tar.xz
```

### Important Notes

- While wildcards (`*`) can be used in version and target patterns, they cannot be used within URLs.
- Always specify complete URLs with exact filenames - wildcards in URLs will not be expanded by the web server.
- Each URL should point to a specific ImageBuilder version in the filename.

### Placeholders in URLs

The following placeholders can be used in URLs and will be replaced with actual values:

- `%OPENWRT%`: The OpenWrt version (e.g., `23.05.5`)
- `%MAINTARGET%`: The main target architecture (e.g., `ath79`)
- `%SUBTARGET%`: The subtarget (e.g., `generic`)
- `%EXTENSION%`: The file extension (`xz` or `zst`) 

## Usage

The firmware assembly process consists of two main steps:

1. Configure the ImageBuilder:
   ```
   ./configure_imagebuilder.sh -t <target> -o <openwrt_version>
   ```

2. Build firmware images:
   ```
   ./assemble_firmware.sh -t <target> -i "ib/" -u weimarnetz -o <openwrt_version> -e "EMBEDDED_FILES/"
   ```

Where:
- `<target>` is the hardware target (e.g., ath79_generic)
- `<openwrt_version>` is the OpenWrt version (e.g., 23.05.5) 

