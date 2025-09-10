# ToM Tracker (Ashita v4 Addon)

**Author:** Ilogical  
**Version:** 1.0.0  
**License:** MIT

Trial of the Magians progress tracker for Final Fantasy XI (Ashita v4). It listens to your chat log for the standard Trial lines, shows a tiny HUD with your Trial Number / Description / Remaining, and can automatically announce progress milestones to Party / Linkshell / Linkshell2. If you’re in an Abyssea zone, it appends your Visitant time remaining.

> **Disclaimer:** This is a third‑party addon not affiliated with or endorsed by Square Enix. Use at your own risk. Playing with third‑party tools may violate the game’s Terms of Service depending on how they are used. This addon is designed to read chat logs and post chat messages only; you are responsible for complying with all applicable rules and laws.

---

## Features

- Parses chat lines like:
  - `Trial 1234: 57 objectives remain.`
  - `You have completed Trial 1234.`
- HUD displays:
  - **Trial Number**, **Desc**, **Remaining**, and an optional **Path tag** if known
- Milestone announcements:
  - Configurable round sizes: **100, 50, 25, 10, 1**
  - Modes: **Every N** or **When N remain**
  - Channels: **Party (/p)**, **Linkshell (/l)**, **Linkshell 2 (/l2)**
- Abyssea integration:
  - Appends `| Abyssea: M:SS left` to progress announcements when in Abyssea
  - Pulls time from the game API when available; otherwise, it learns from “Visitant time will wear off in …” chat lines
- Autolabel trial description from `trials_map.lua` (if provided)
- Manual inputs for Trial Number and Desc (so you can label anything quickly)
- `/tom progress` on demand

> **Out of scope for this release:** auto-detecting the trial from equipped items (removed for now), automation of gameplay actions, or armor trials listing.

---

## Installation

```
Ashita 4\
  addons\
    tomtracker\
      tomtracker.lua
      trials_map.lua           (optional, see below)
```

1. Copy `tomtracker.lua` into `Ashita 4\addons\tomtracker\`.
2. (Optional) Create `trials_map.lua` in the same folder. It should return a Lua table of Trial IDs to descriptions:
   ```lua
   return {
     [1019] = "Burtgang (Mythic): Atonement KB vs Dragons x200",
     [1024] = "Ragnarok (Relic): Scourge vs Birds x200",
     -- ...
   }
   ```
3. In-game, load the addon:  
   `/load tomtracker`

---

## Usage

Toggle HUD:
```
/tom
```

Help & commands:
```
/tom help
```

### Announcements
```
/tom announce on|off           -- enable or disable milestone announcements
/tom round 100|50|25|10|1      -- milestone size
/tom mode step|final           -- 'step' = every N, 'final' = when N remain
/tom chan party|ls|ls2         -- choose channel
```

### Trial labeling
```
/tom trial <number>            -- set current trial number
/tom desc <text>               -- set/override description (alias: /tom type <text>)
/tom autolabel on|off          -- auto-fill desc from trials_map.lua if known
/tom loadmap                   -- reload trials_map.lua
```

### Progress & Abyssea
```
/tom progress                  -- announce current progress (includes Abyssea time if in Abyssea)
/tom aby                       -- print Abyssea time left
```

### Misc
```
/tom reset                     -- clear remaining/last-announced
/tom debug on|off              -- toggle debug logging (no HUD checkbox)
/tom mapinfo                   -- shows path where trials_map.lua is expected
/tom sim <trial> <remain>      -- simulate a progress line (for testing)
```

---

## How it works

- **Parsing:** The addon listens for FFXI chat lines that Magian moogles emit:
  - `Trial <id>: <N> objectives remain.`
  - `You have completed Trial <id>.`
- **Abyssea time:** It first asks the client for Visitant time. If unavailable, it parses the usual “Visitant status will wear off in …” messages and keeps an internal countdown.
- **trials_map.lua:** If present, it merges a user-provided map of Trial IDs → human-readable descriptions. This is handy for seeing “Desc” without memorizing Trial IDs.
- **No gameplay automation:** Only reads the log and posts chat messages per your settings.

---

## Troubleshooting

- **No announcements show up in Linkshell:**  
  Ensure the channel is set to `ls` or `ls2`. This addon uses `/l` and `/l2` (not `/ls1`).  
  ` /tom chan ls`
- **Not picking up progress lines:**  
  Turn on debug and watch the log:
  ` /tom debug on`  
  You should see `[chat_in/progress]` or `[text_in/progress]` messages when the moogle lines appear.
- **Abyssea time not appended:**  
  Use `/tom aby` to see the timer directly. If it’s `unknown`, wait for a “Visitant … wear off in …” line or re-enter the zone to refresh.
- **Map not loaded:**  
  ` /tom mapinfo` then ensure `trials_map.lua` exists at that path. Use ` /tom loadmap` after adding it.

---


## Credits


- Community resources: **BG‑Wiki** for trial data and terminology

---

## Legal / Risk Notice

Final Fantasy XI is owned by Square Enix Co., Ltd. This project is a **third‑party** addon for the **Ashita** injector and is not affiliated with or endorsed by Square Enix. Use of third‑party tools **may** violate the game’s Terms of Service. You assume all risk by using this software. The authors provide this project “as is” without warranties of any kind.

---

## License

This project is licensed under the **MIT License**. See [LICENSE](./LICENSE) for details.
