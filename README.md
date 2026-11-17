# Brainrot Tsunami Heist

[![make.fun bounty — Make the best AI Roblox brainrot game](https://make.fun/bounty/roblox-brainrot-01/badge.svg?repo=hajilok%2Fbrainrot-tsunami-heist)](https://make.fun/bounty/roblox-brainrot-01?ref=41fw6r6c)

[![make.fun bounty](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?ref=41fw6r6c)
[![make.fun rank](https://make.fun/badge/roblox-brainrot-01/hajilok/brainrot-tsunami-heist/rank.svg)](https://make.fun/bounty/roblox-brainrot-01?ref=41fw6r6c)
[![make.fun reward](https://make.fun/badge/roblox-brainrot-01/hajilok/brainrot-tsunami-heist/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?ref=41fw6r6c)

**Play it on Roblox:** <https://www.roblox.com/games/139064958220502>
**Place ID:** `139064958220502` · **Universe ID:** `10777389854`

Join with a referral link: <https://make.fun/r/41fw6r6c>

---

**Brainrot Tsunami Heist** is a 3D Roblox brainrot game built with a coding agent for make.fun's
"Make the best AI Roblox brainrot game" bounty (`roblox-brainrot-01`). A player's character runs a
real 3D world under a 3D camera: grab absurd meme-born brainrots off a heist conveyor, dash them
home before the tsunami sweeps the lane, stack them on vault pedestals for passive income, and
climb rarities, mutations and rebirths while a rival thief raids your base.

The game is played in Roblox's 3D space — the interface is a `ScreenGui` laid over a world of
`Part`s and `Model`s — not drawn on the screen.

## 3D Gameplay Loop

1. **Spawn in the plaza.** The server calls `LoadCharacter()` (the place has
   `CharacterAutoLoads = false`), and the client drives the character with WASD/arrow keys while a
   Scriptable camera frames the action.
2. **Grab a brainrot.** Brainrots ride the heist conveyor lane (`HeistConveyorLane`). Press **E**
   near one to pick it up (`HeistAndTsunamiService.tryPickupNearestConveyorBrainrot`).
3. **Dash home.** A carried brainrot earns nothing. Cross the `LaserBarrierGate` and reach a vault
   pedestal, then press **E** again to deposit it.
4. **Earn passively.** Eight `VaultPedestals` each hold one brainrot and pay income every second.
   A 1-second server tick adds the cash and pushes a fresh snapshot to the HUD.
5. **Upgrade and rebirth.** Press **U** to buy `SpeedBoots`, `MutationLuck` or `ExtraPedestals`,
   and **R** at the `RebirthAltarShrine` to reset the vault for a permanent income multiplier and
   new rarity/mutation unlocks.
6. **Defend.** Press **F** to arm the laser gate, and hide under a safe-zone shelter when the
   tsunami warning sounds.

| Key | Action |
| --- | --- |
| `W A S D` / Arrow keys | Move the character |
| `E` | Grab a conveyor brainrot, or deposit the carried one |
| `F` | Lock / arm the laser gate |
| `U` | Cycle and purchase shop upgrades |
| `R` | Attempt a rebirth at the altar |
| `I` | Toggle the 16-Brainrot Cast Index & Rebirth IV/V Shop |
| `1` / `2` / `3` | Switch camera preset (Vault Cover / Heist Lane / Rebirth Altar) and its tour preset |

## 16-Brainrot Cast & 5 Mutations

Every brainrot (see `src/shared/BrainrotCatalog.luau`) has a rarity, a base income per second, a
steal cost, a rig style and its own colours and flavour text. The 3D sculpture is built per
`rigStyle` by `WorldAndRigBuilder.buildBrainrotRigModel`, with an overhead card reading
`[RARITY • MUTATION]`, the name and its `+$/s`.

| # | Brainrot | Rarity | Base income | Rig style |
| --- | --- | --- | --- | --- |
| 1 | Lirili Larila | Common | $1.5/s | Biped |
| 2 | Boneca Ambalabu | Common | $2/s | Quadruped |
| 3 | Frigo Camelo | Common | $2.5/s | Quadruped |
| 4 | Burbaloni Luliloli | Rare | $8/s | Biped |
| 5 | Chimpanzini Bananini | Rare | $9.5/s | Biped |
| 6 | Trippi Troppi | Rare | $11/s | Avian |
| 7 | Glorbo Fruttodrillo | Rare | $12.5/s | Serpentine |
| 8 | Brr Brr Patapim | Epic | $26/s | Amorphous |
| 9 | Ballerina Cappuccina | Epic | $30/s | Biped |
| 10 | Orangutini Ananasini | Epic | $34/s | Biped |
| 11 | Capuccino Assassino | Epic | $38/s | Flying |
| 12 | Tralalero Tralala | Legendary | $85/s | Biped |
| 13 | Tung Tung Sahur | Legendary | $95/s | Titan |
| 14 | Bombardiro Crocodilo | Legendary | $120/s | Flying |
| 15 | La Vaca Saturno Saturnita | Mythic | $320/s | Titan |
| 16 | Garama Madundung | Celestial | $900/s | Amorphous |

**Rarity tiers:** Common → Rare → Epic → Legendary → Mythic → Celestial.

**Mutations** multiply a brainrot's income and are rolled by `rollMutationForLuck`, which bends the
odds toward rarer rolls as the `MutationLuck` upgrade grows:

| Mutation | Multiplier |
| --- | --- |
| Normal | ×1 |
| Golden | ×2 |
| Diamond | ×3.5 |
| Galaxy | ×6 |
| Rainbow | ×10 |

## Tsunami Hazard & Laser Lock Defense

`HeistAndTsunamiService` runs the hazard loop on `RunService.Heartbeat`, cycling three phases:

- **Calm** — the `TsunamiHazardWall` waits at the far end of the heist lane.
- **Warning** — the HUD raises the red tsunami banner: get to a shelter.
- **Sweeping** — the wave and its foam crests cross the lane
  (`WorldAndRigBuilder.updateTsunamiWavePosition`). Any player carrying a brainrot outside the
  `ShelterNorth` / `ShelterSouth` safe zones is **washed away** — their carried brainrot is dropped
  by `BaseStateStore.dropCarriedBrainrot`.

The `LaserBarrierGate` is the second defense. Its four beams sit **armed neon cyan** when locked and
fade to a **dim teal** when unlocked (`updateLaserGateVisuals`); the laser lock is a timed state in
`BaseStateStore` (`activateLaserLock` / `isLaserLocked`). A rival thief bot also races the conveyor,
snatching brainrots before the player does.

## Module Architecture

The game is a Rojo 7.7 project (`default.project.json`) built into `game.rbxl`.

```
ReplicatedStorage.Shared        (src/shared/)
  BrainrotCatalog.luau          rarities, mutations, 16 characters, upgrades, rebirths + pure maths
  BaseStateStore.luau           the single source of truth for every player's live state

ServerScriptService.Server      (src/server/)
  init.server.luau              bootstrap: remotes, lifecycle, action routing, 1s passive tick
  WorldAndRigBuilder.luau       builds/syncs the 3D world: vault rigs, gate look, tsunami position
  HeistAndTsunamiService.luau   heist lane, conveyor + thief AI, hazard loop, tour presets

StarterPlayer.StarterPlayerScripts.Client   (src/client/)
  Game.client.luau              Scriptable 3D camera, input bindings, ScreenGui HUD
```

**Data flow.** The server owns all state in `BaseStateStore`. Clients never mutate it; they fire
`BrainrotAction` RemoteEvents (`HeistAction`, `LockLaser`, `BuyUpgrade`, `AttemptRebirth`,
`SellPedestal`, `ApplyPreset`) and read `BrainrotStateSync` snapshots built by
`BaseStateStore.buildClientSnapshot`. `WorldAndRigBuilder` repaints the shared world from whichever
state is featured.

**Tour presets.** `HeistAndTsunamiService.applyTourPreset(preset, player?)` supports `cover`,
`heist` and `rebirth`: it writes a canonical state through `BaseStateStore.applyPresetState`, then
refreshes the vault pedestals, the carried item, the laser gate and the tsunami wave — matching the
three screenshots and the optional `TOUR.json`.

## Build & entry

```sh
# Build the place from src/ and default.project.json
rojo build default.project.json --output game.rbxl

# Pack the entry (writes out/dossier.json, game.rbxl, src/, screenshots/, PLAY.json)
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```

- `main.ts` (Node 22, standard library only) copies the entry into `MAKEFUN_OUTPUT_DIR` (or
  `/output`), skipping dot-files, and writes `dossier.json` via `vendor/makefun-roblox.ts`. Its
  `verifyEntryManifest` helper checks `PLAY.json`'s `place_id` and `universe_id` before the dossier
  is built.
- `game.rbxl` is the built place; `screenshots/` holds the three captures (the first is the cover,
  and the same picture is this experience's Roblox thumbnail); `PLAY.json` names the published
  place.

## Screenshots

| Cover | Heist & tsunami | Rebirth & shop |
| --- | --- | --- |
| `screenshots/1-cover-thumbnail.jpg` | `screenshots/2-heist-tsunami-chase.jpg` | `screenshots/3-rebirth-mutation-shop.jpg` |

## License

MIT — see `LICENSE`.
