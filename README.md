# Terminal Slideshow Apps

Collection of terminal-native media viewers that render images and short videos through different terminal graphics backends.

## Overview

This repo does not present one single slideshow implementation. It groups several distinct viewers that use different rendering paths and produce different terminal experiences.

Included tools:

- `image-slideshow-chafa.sh`
  - `chafa`-based
  - slideshow mode and feed mode
  - image and video handling
  - rotation, width control, saved settings

- `image-slideshow.sh`
  - Kitty `icat` based
  - requires Kitty terminal
  - slideshow mode and feed mode
  - direct image/video display for supported formats

- `minicatimgslideshow`
  - smaller `catimg` slideshow
  - simpler keyboard-driven image/video viewer
  - no machine-specific default media path in the public copy

- `scrolling-feed-catimg.sh`
  - scrolling feed style viewer
  - `catimg` based
  - continuous feed rather than a strict one-image-per-screen slideshow

## Why They Are In One Repo

These scripts overlap in purpose but not in runtime behavior.

- different terminal graphics engines
- different interaction models
- different tradeoffs for image quality, speed, and portability

The repo keeps them together because they are part of the same terminal-media exploration, but they should be treated as separate tools.

## Dependencies

Depending on the script:

- `catimg`
- `chafa`
- `kitty`
- `ffmpeg`
- `imagemagick` (`convert`)

## Quick Start

Run any script directly with a media directory:

```bash
./image-slideshow-chafa.sh /path/to/media 10
./image-slideshow.sh /path/to/media 10
./minicatimgslideshow /path/to/media 10
./scrolling-feed-catimg.sh /path/to/media 10
```

Scripts that do not receive a path will prompt for one or reuse a saved setting, depending on the viewer.

## Notes

- The public repo copy removes hard-coded personal media paths.
- User-level settings files under `$HOME` are kept because they are generic per-user cache/config behavior, not personal source-tree leaks.
- `scrolling-feed-catimg.sh` and `minicatimgslideshow` are both `catimg` based, but they are not the same UX.

## License

MIT
