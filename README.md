# Cobalt Download

Unofficial Omarchy bar widget. Paste a public media link, save the file. The panel drops under the bar icon like Wi-Fi or audio.

This is **not** [cobalt.tools](https://cobalt.tools) and is **not** made by [imput](https://github.com/imputnet/cobalt). It talks to a community [cobalt](https://github.com/imputnet/cobalt) API when that works, and falls back to [yt-dlp](https://github.com/yt-dlp/yt-dlp) when the instance cannot fetch the link (YouTube, flaky TikTok, etc.).

## Install

```sh
omarchy plugin add https://github.com/CloudDown/omarchy-cobalt.git --enable
```

Optional: move the icon.

```sh
omarchy bar move clouddown.cobalt --section right
```

## Usage

- Click the bar icon to open or close the panel
- Paste a URL (or use **paste**), pick **auto** / **audio** / **mute**, then **download**
- **cancel** stops the current job; **open** opens the last saved file
- Escape closes; Tab switches to the neighbouring bar panel
- Settings (gear): max quality, audio format, download folder — saved as you change them

Command: `omarchy-shell shell toggle clouddown.cobalt`

## How a download works

1. The plugin POSTs the URL to a cobalt API instance (`https://cobaltapi.cjs.nz` by default).
2. If the instance returns a tunnel, redirect, or picker, the file is saved from there.
3. If the instance errors (YouTube login, `fetch.fail`, timeout, unreachable), **yt-dlp** downloads the original URL instead. The panel shows `Trying yt-dlp…` and a progress bar.

Official `api.cobalt.tools` uses bot protection (Turnstile) and is not used. Community instances can block YouTube/TikTok at any time; that is why yt-dlp is there.

Settings live in `~/.config/omarchy/cobalt.json` (created on first save). Empty `downloadDir` means `~/Downloads`.

## Dependencies

Must already be on the machine (the plugin does not install packages or use sudo):

- `python3` (stdlib only for the helper)
- `yt-dlp`
- `ffmpeg` (yt-dlp merge / audio extract)
- `wl-paste`
- `xdg-open`
- network access to the cobalt instance and to the media site

## What it does not do

- No sudo, no extra Quickshell process, no notifications after save
- Does not log into YouTube / Reddit / Vimeo; those sites may still fail even with yt-dlp if they want cookies
- Does not ship your Hyprland keybinding or Omarchy menu row — add those yourself if you want them
- Not affiliated with imput / cobalt.tools. Mascot and chevron mark in the UI are used as a tribute to cobalt; they are **not** licensed for reuse. See [cobalt credits](https://cobalt.tools/about/credits). Do not treat this plugin as official cobalt branding.

## Remove

```sh
omarchy plugin remove clouddown.cobalt
```

This does not delete `~/.config/omarchy/cobalt.json`.

## License

MIT. See `LICENSE`.

Cobalt API: [AGPL-3.0](https://github.com/imputnet/cobalt). yt-dlp: [Unlicense](https://github.com/yt-dlp/yt-dlp). You are responsible for what you download.
