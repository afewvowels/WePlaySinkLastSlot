<p align="center">
  <img src="thumbnail.png" alt="WePlay: Sink Last Slot" width="144">
</p>

# WePlay: Sink Last Slot

**Turn any chest or storage tank into a void: overflow items and fluids vanish so your factory never backs up.**

The factory must grow. The factory must never stop. 🌀

Every chest and storage tank in your factory can open a tiny door to the **void**. Flip a switch and it fills up like normal, but the overflow is swallowed into nothingness. No backed-up belts, no clogged pipes, no stalled assemblers. Just the endless appetite of the factory, fed forever.

Think of it as a sink chest, a void chest and a void tank in one, with no new buildings to craft.

[**Download on the Factorio mod portal →**](https://mods.factorio.com/mod/WePlaySinkLastSlot)

---

## Features

- **Full capacity, all the time.** Overflow never backs up your lines, so every machine keeps running flat out.
- **Keep a buffer, lose the excess.** Chests and tanks still hold a full stock. Only the overflow goes to the void.
- **No new buildings.** Unlike flare stacks or incinerators, there's nothing to craft, place or route. Just flip the toggle on the chests and tanks you already have.
- **Works with modded entities.** Regular chests, logistic chests, storage tanks, and chests and tanks from other mods.
- **Light on UPS.** Only chests and tanks that are switched on are checked, spread evenly across ticks.

## How it works

Open any chest or storage tank and a **Sink last slot** panel appears beside its window.

### 📦 Chests: *Sink last slot*

When on, the chest fills normally, and anything that reaches the **last slot** is voided.

It respects the **red limit bar**: if you limit a chest, the slot just before the bar becomes the doorway to the void, so you decide exactly how much it keeps.

### 💧 Storage tanks: *Void excess fluid*

When on, the tank keeps its top layer of space free by voiding any fluid above the headroom line (1000 units by default), so there's always room for more. Tanks smaller than the headroom keep 10% of their capacity free instead.

### Copy and paste

**Shift + right-click** a chest or tank, then **Shift + left-click** another of the same kind to copy the toggle across.

## Settings

All settings are map settings (**Settings → Mod settings → Map**) and can be changed mid-game.

| Setting | Default | What it does |
|---|---|---|
| **Sink chests by default** | Off | Whether chests you haven't toggled yourself feed the void. Hand-toggled chests keep their own choice. |
| **Void tanks by default** | Off | Whether storage tanks you haven't toggled yourself feed the void. Hand-toggled tanks keep their own choice. |
| **Tank headroom (fluid units)** | 1000 | How much empty space a voiding tank keeps at the top. |
| **Sink check interval (ticks)** | 5 | How often each sinking chest or tank is checked. Lower is faster; higher saves a little UPS in huge factories. |

## Installation

The easiest way is from inside Factorio: **Main menu → Mods → Install**, search for **Sink Last Slot**, and install.

You can also download it from the [mod portal](https://mods.factorio.com/mod/WePlaySinkLastSlot), or download a release zip from this repo and drop it, unextracted, into your Factorio `mods` folder.

## Compatibility

- Requires **Factorio 2.1**.
- **Space Age is optional.** It works with or without it, including on space platforms.
- Works alongside overhaul mods; any entity of type `container`, `logistic-container` or `storage-tank` gets the toggle.
- Infinity chests and infinity pipes are left alone.

## Known limits

- Blueprints don't remember the toggle yet. Newly placed chests and tanks follow the default settings.
- In modded tanks with more than one fluid slot, excess is voided starting from the first slot.

Ideas and bug reports are welcome on the mod portal's **Discussion** tab or in this repo's issues.

## License

Released under [the Unlicense](LICENSE): public domain, so do whatever you like with it.

*Feed the void. Feed the factory.* 🖤
