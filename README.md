# Get A PowerShell Fish Tank 🐠

<img width="2330" height="1280" alt="image" src="https://github.com/user-attachments/assets/3177de0a-e94f-4f33-8752-1d2afeddd847" />



A terminal-based aquarium simulation built in native PowerShell. Watch colorful fish, seahorses, jellyfish, and a snail move through a changing tank, while seaweed sways and bubbles rise. The tank uses ANSI colors and updates only the parts of the screen that change.


## Features

* **Marine life:** Multiple fish sizes and color palettes, plus seahorses, jellyfish, and a roaming snail. Fish seek food dropped into the tank.
* **Living scenery:** Swaying seaweed, randomly generated anemones, a castle, rising bubbles, and food that stacks on the tank floor.
* **Customizable water:** Cycle through three colored gradients and an uncolored water option.
* **Responsive display:** The tank adapts when the terminal is resized and uses differential rendering to update only changed characters.
* **Interactive controls:** Add food or fish, remove a fish, pause the simulation, change its speed, or generate a new tank.

---

## Controls

| Key | Action |
| :--- | :--- |
| **`N`** | Clear and generate a **N**ew tank environment |
| **`F`** | Drop **F**ood into the tank |
| **`S`** | **S**pawn a new fish at screen center |
| **`K`** | **K**ill/remove a random fish |
| **`P`** | **P**ause or resume the simulation |
| **`W`** | Cycle the water color gradient (including no color) |
| **`PageUp`** | Increase simulation speed (decrease tick delay) |
| **`PageDown`** | Decrease simulation speed (increase tick delay) |
| **`Q`** / **`Esc`** | **Q**uit simulation and clear screen |

---

## Prerequisites & Compatibility

* **PowerShell:** Windows PowerShell 5.1+
* **Terminal:** An interactive, ANSI-compatible terminal such as Windows Terminal or the VS Code integrated terminal. Windows Terminal is recommended.
* **Color support:** 256-color ANSI escape sequences. The `W` control also cycles to uncolored water if you prefer.

---

## Quick Start

1. Clone or download this repository.
2. Open an interactive terminal in the repository folder and expand it for the best experience.
3. Run the script:

```powershell
.\Get-FishTank.ps1
```

Run it in a split terminal to enjoy your tank while you code.

<img width="2142" height="1197" alt="image" src="https://github.com/user-attachments/assets/5b177f3e-f0de-4ee6-a99d-70123373a8e4" />
