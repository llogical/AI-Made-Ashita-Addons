# BLU GUI (blugui)

A graphical front-end for managing Blue Mage spell sets in **Final Fantasy XI** (Ashita v4).  
This addon is designed to complement the official `blusets` addon by atom0s and the Ashita Development Team.

---

## Features

- Full GUI for browsing and building Blue Mage spell sets.
- Displays points used / max (live updating while spells apply).
- Prevents duplicates and automatically filters out Unbridled Learning/Wisdom spells.
- Supports reading and writing `.txt` spell set files from the `blusets` addon.
- Buttons for:
  - **Add Spell** – insert learned spell into the working set.
  - **Remove Spell** – remove the selected slot.
  - **Clear Set** – wipe the entire working set (all slots empty).
  - **Apply Set** – load the working set into the game (packet delay adjustable).
  - **Save/Load Set** – persist sets to disk and recall them later.
  - **Use Equipped** – seed the working set with your currently equipped BLU spells.
  - **Rescan** – refresh the list of available learned spells.

---

## Installation

1. Make sure you have **Ashita v4** installed.
2. Install the official **blusets** addon (ships with Ashita).
3. Copy the `blugui` folder into your `Ashita/addons/` directory:
   ```
   Ashita/
     addons/
       blusets/       ← required (from Ashita)
       blugui/        ← this addon
   ```
   The folder should contain:
   - `blugui.lua`
   - `unbridled.lua`
   - `README.md`
   - `LICENSE`
   - (any future support files)

4. Start the game with Ashita and load the addon:
   ```
   /addon load blugui
   ```

---

## Usage

- The main window opens automatically on load.  
  Toggle it with:
  
  /blugui
  
  or use `/blugui show`, `/blugui hide`.

- Sets are stored under:
  
  Ashita/config/addons/blusets/
  
  using the same format as `blusets`. If you already used `blusets`, your existing `.txt` files will be available in the drop-down menu.

- Saving sets:

  The available spell list is ALL Blue magic spells, the addon disregards if you know the spells. This way you can make any set with anyspells. There will be an error when you try to set them though if you don't actually know a spell.

  To start with a fresh working set, use the Clear Set to remove all spells from the canvas. Alternatively, you can add and remove spells one at a time with the corresponding buttons.

  Once you have your spells set, name it at the bottom and hit Save set. 
  Note: on the to do list is to display points used in the working set canvas.

- Applying Sets:

  After you save the set, you can use the Apply Set button to set the spells on your BLU Mage character. Sometimes there might be lag or what not that a spell will be missed. The display and the chat log in game will notify you. The usual fix is to use the slider to increase the delay between each spell.
  To use an already saved set, select from the dropdown menu then hit Load. This will populate the Working Set canvas. You can verify that the list looks good then use Apply Set. The status of the operation will be displayed at the top and once again when finished you will get a notice in game.


---

## Credits

- **Ashita Development Team** (https://www.ashitaxi.com/)
- **atom0s** – author of the underlying `blusets` addon and the `blu.lua`   helper library.
- Original `blugui` concept by **Ilogical**.
- Current enhancements, tweaks, and maintenance by **Klipsy+MrC**.

---

## License

This project is released under the **MIT License** (see `LICENSE`).
MIT License

Copyright (c) 2025 Ilogical

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

---

## Disclaimer

This addon is provided **as-is**. Use at your own discretion.  
No guarantees are made for functionality, safety, or compatibility with private servers. Part of this disclaimer: I've tested with my own setup and is limited to my character level and knowledge. Much of this addon was created with AI, but I am still learning and welcome comments, critisisms, rants, and bugs. You can reach out to Klipsy in discord or make a ticket in github. Thanks for trying this out!
