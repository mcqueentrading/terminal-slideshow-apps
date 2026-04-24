# Terminal Slideshow Apps

Collection of terminal-native media viewers that render images and short videos through different terminal graphics backends.

## Project Page

Portfolio page:

https://tonimcqueen.com/project_slideshowapps.html

## Overview

This repo is not one slideshow program with a few flags bolted on. It is a grouped set of terminal media viewers that explore different rendering paths and different interaction styles:

- `chafa` for broad terminal compatibility and mixed slideshow/feed behavior
- Kitty `icat` for a richer image/video path inside Kitty
- `catimg` for lighter ASCII-style image viewing
- a scrolling feed mode for a more continuous wall-of-media effect

The point of the collection is that different terminals and different viewing moods need different tools.

## Viewer Matrix

| Tool | Renderer | Best For | Notes |
| --- | --- | --- | --- |
| `image-slideshow-chafa.sh` | `chafa` | General-purpose terminal slideshow | Most feature-rich mixed viewer in the repo |
| `image-slideshow.sh` | Kitty `icat` | Best visual quality inside Kitty | Requires Kitty terminal |
| `minicatimgslideshow` | `catimg` | Lightweight keyboard slideshow | Simpler and more direct |
| `scrolling-feed-catimg.sh` | `catimg` | Continuous scrolling media feed | Different UX from a slideshow |

## Quick Comparison

```text
image-slideshow-chafa.sh
  -> broadest terminal strategy
  -> slideshow + feed
  -> rotation + width tuning
  -> images + converted videos

image-slideshow.sh
  -> Kitty-only
  -> slideshow + feed
  -> native icat media path
  -> strongest terminal-image presentation when Kitty is available

minicatimgslideshow
  -> simpler catimg slideshow
  -> direct keyboard control
  -> lower conceptual overhead

scrolling-feed-catimg.sh
  -> feed-style wall of media
  -> better for passive scrolling mood than discrete slide stepping
```

## Visual Model

```text
Media Directory
  -> image-slideshow-chafa.sh
     -> chafa render
     -> slideshow mode or feed mode

Media Directory
  -> image-slideshow.sh
     -> kitty +kitten icat
     -> slideshow mode or feed mode

Media Directory
  -> minicatimgslideshow
     -> catimg render
     -> compact slideshow flow

Media Directory
  -> scrolling-feed-catimg.sh
     -> catimg render
     -> continuous scrolling feed
```

## Included Tools

### `image-slideshow-chafa.sh`

The `chafa` viewer is the broadest and most flexible script in the repo.

What it does:
- prompts for or remembers a media directory
- supports both slideshow mode and feed mode
- handles images directly
- converts videos in the background through `ffmpeg`
- supports rotation
- supports dynamic width control
- stores user-level settings in `$HOME`

Why it matters:
- it is the best “general terminal media viewer” in the collection
- it does not require Kitty
- it balances portability with a stronger feature set than the smaller viewers

### `image-slideshow.sh`

This is the Kitty-native path.

What it does:
- uses `kitty +kitten icat`
- supports slideshow mode and feed mode
- handles direct terminal image/video presentation for supported formats
- supports rotation and upscale behavior
- stores user-level settings in `$HOME`

Why it matters:
- if the user is already inside Kitty, this is the richer visual option
- it is less universal than `chafa`, but stronger when the runtime fits

### `minicatimgslideshow`

This is the smaller `catimg` slideshow path.

What it does:
- prompts for a media directory when none is given
- renders through `catimg`
- supports keyboard stepping and pause behavior
- supports width and upscale controls
- can convert video sources to GIF when needed

Why it matters:
- lower overhead
- simpler mental model
- useful when the user wants a straightforward slideshow without the bigger mixed-mode interface

### `scrolling-feed-catimg.sh`

This is the generic public version of the scrolling feed viewer.

What it does:
- prompts for or remembers a media directory
- uses `catimg`
- keeps moving through media in a feed-like pattern rather than clean slide separation
- supports dynamic delay changes and width changes
- can convert videos in the background

Why it matters:
- it is a different viewing style, not just a different renderer
- better for ambient scrolling or a terminal art-wall effect than for deliberate slide-by-slide review

## Dependency Table

| Dependency | Used By | Purpose |
| --- | --- | --- |
| `catimg` | `minicatimgslideshow`, `scrolling-feed-catimg.sh` | Terminal image rendering |
| `chafa` | `image-slideshow-chafa.sh` | Terminal graphics rendering |
| `kitty` | `image-slideshow.sh` | Kitty-native media display |
| `ffmpeg` | all viewers with video support | Convert unsupported video into displayable formats |
| `imagemagick` / `convert` | `image-slideshow-chafa.sh`, `image-slideshow.sh` | Rotation support |

## Runtime Notes

- The public repo copy removes hard-coded personal media paths.
- User-level settings files under `$HOME` are intentionally kept because they are generic cache/config behavior, not source-tree leaks.
- The tools overlap, but they are not redundant. The repo is better understood as a small terminal-media toolkit.

## Recommended Starting Order

If someone opens the repo and does not know where to start:

1. Try `image-slideshow-chafa.sh` first.
2. If they are a Kitty user and want richer rendering, try `image-slideshow.sh`.
3. If they want something smaller and more direct, use `minicatimgslideshow`.
4. If they want a flowing terminal media wall instead of discrete slides, use `scrolling-feed-catimg.sh`.

## Quick Start

```bash
./image-slideshow-chafa.sh /path/to/media 10
./image-slideshow.sh /path/to/media 10
./minicatimgslideshow /path/to/media 10
./scrolling-feed-catimg.sh /path/to/media 10
```

If a path is not passed, the script will either prompt for one or reuse saved settings, depending on the viewer.

## License

MIT
