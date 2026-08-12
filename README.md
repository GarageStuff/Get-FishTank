# Get A PowerShell Fish Tank 🐠

<img width="1768" height="967" alt="image" src="https://github.com/user-attachments/assets/826eed23-9063-4dd5-8e75-b8c4134539d3" />


* **Run as a split terminal to enjoy your tank as you code**

<img width="2142" height="1197" alt="image" src="https://github.com/user-attachments/assets/5b177f3e-f0de-4ee6-a99d-70123373a8e4" />


A terminal-based aquarium simulation built in native PowerShell. It features dynamic marine life, interactive controls, realistic plant physics, depth-based water gradients, and high-performance differential screen rendering using ANSI escape codes for coloring.

## Features

* **Dynamic Aquatic Ecosystem:**
  * **Fish, Seahorses, Jellyfish, Snails:** Multiple sizes and species (Orange Fish and Neon Tetras) with realistic multi-segment movement and targeted food-seeking AI.
  * **Flora:** Swaying seaweed with sinusoidal movement physics and procedural anemones/corals.
  * **Physics and Coloring:** Rising bubble streams, food stacking, per-entity color variants, and depth-based water color shading.
* **Interactive Tank:** Drop food, spawn new fish, remove fish, or reset the tank on demand.
* **High-Performance Rendering:** Uses a differential cell-buffer array to only re-render terminal characters that change.

---

## Controls

| Key | Action |
| :--- | :--- |
| **`N`** | Clear and generate a **N**ew tank environment |
| **`F`** | Drop **F**ood into the tank |
| **`S`** | **S**pawn a new fish at screen center |
| **`K`** | **K**ill/remove a random fish |
| **`PageUp`** | Increase simulation speed (decrease tick delay) |
| **`PageDown`** | Decrease simulation speed (increase tick delay) |
| **`Q`** / **`Esc`** | **Q**uit simulation and clear screen |

---

## Prerequisites & Compatibility

* **PowerShell:** PowerShell 7+  *The Windows Terminal App will provide the best rendering and color performance, but the standard shell will work fine. 
* **Terminal:** Any ANSI-compatible terminal (Windows Terminal, VS Code Terminal, or modern `cmd.exe`/PowerShell console).
* **Color Support:** 256-color ANSI escape sequences enabled in terminal settings.

---

## Quick Start

1. Save the code into a script file (e.g., `FishTank.ps1`).
2. Open your terminal and expand it to full screen for the best experience.
3. Run the script:

```powershell
.\FishTank.ps1
