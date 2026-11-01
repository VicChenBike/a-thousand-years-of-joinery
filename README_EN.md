# A Thousand Years of Joinery (千年一榫)

English | [中文](README.md)

A cultural experience + casual puzzle game themed on **sunmao** (榫卯) — the traditional Chinese art of **mortise-tenon** joinery, inscribed on China's national intangible cultural heritage list.

You play an **amnesiac craftsman** who, accompanied by the Witness **"Gui"** (晷), travels across **five eras** — Hemudu, the Song dynasty, the Yuan dynasty, the Ming dynasty, and the modern day — carving surplus voxels out of raw timber blocks, recreating classic mortise-tenon members, and fitting them onto their fixed counterparts, one joint at a time, to recover a lost craft.

> Godot 4.7 (gl_compatibility renderer) · Windows · Input: webcam hand gestures (any ordinary single camera + MediaPipe) + keyboard & mouse · **[📥 Download the installer](https://github.com/VicChenBike/a-thousand-years-of-joinery/releases/latest)**

## Five eras, five artifacts

| Era | Artifact | Highlight |
|---|---|---|
| Hemudu (Neolithic) | Mortise-tenon wooden member | Recreate the earliest known Chinese mortise-tenon forms inside a 7,000-year-old stilt house |
| Song dynasty | Baoguo Temple melon-ribbed column & dougong brackets | Take apart a Song-era hall's column and bracket set and feel the precision of great timberwork |
| Yuan dynasty | Zhenru Temple beam-frame joinery | Step into a Yuan-era roof frame and experience the structural wisdom of beam-and-purlin joinery |
| Ming dynasty | Ming-style huanghuali round-backed armchair | Rejoin the sweeping backrest of a classic armchair and savor the minimal beauty of Ming furniture |
| Modern day | Parametric timber joint | Reinterpret sunmao through parametric design, where tradition meets computation |

## Core loop

Story dialogue → **three-view inspection** (workpiece in the center, target artifact top-left, fixed counterpart top-right; synchronized orthographic views) → **carve voxels** (box-select / click / delete, with undo & redo) → **join check** (the carved shape must match the target **exactly, zero tolerance**: after translation normalization, **48 equivalence transforms** — 24 rotations + 24 mirrors — are tested, with equivalence checked before interference) → **scoring** (Perfect / Good / Pass + a Talent reward) → **gallery unlock** (point-cloud renders of the artifacts, rotatable, with four-point background notes).

## Features

- **Three synchronized views**: central main view + target artifact + fixed counterpart, all orthographic, with bounded-drag rotation, two-hand push/pull zoom and a focus mode.
- **The Witness "Gui"**: a companion character who changes outfits with each era (skin system) and offers guidance bubbles and story dialogue.
- **Keen Eye (锐眼)**: a Talent-funded hint tool that highlights the difference between your shape and the target as a red/green diff.
- **Gallery**: clearing levels unlocks point-cloud models of the artifacts (true MultiMesh point clouds) with four-point notes.
- **Shop**: spend Talent on outfits for Gui (including original designs).
- **Level editor**: a mortise-tenon level editor as a standalone Godot project (see `关卡编辑器/`), with a level-data interface spec (see `技术文档/`).

## Gestures at a glance (optional; any ordinary webcam)

- Extend an index finger (or two fingertips) to move the cursor
- Hover and tap with the middle finger to click buttons
- Left hand, three fingers: delete selected voxels; right hand, two fingers: stroke to deselect
- Both fists: clear the selection
- One-hand flip: undo / redo
- Two-hand push / pull: zoom the views
- Bounded drag: rotate the views
- Flip both hands 4 times: bring up the exit countdown

> The game is fully playable without a camera (gesture UI is greyed out).

## In-game languages

The game supports a **Simplified Chinese / English** interface and story text (Settings → Language). Simplified Chinese is the default on first launch.

## Project layout

```
游戏项目/千年一榫/                Game itself (Godot 4.7 project)
  ├── scenes/  autoload/  scripts/   Game code
  ├── assets/                     Art / audio / point clouds / models
  ├── levels_data/                Level data (JSON, 5 levels)
  ├── 剧情对话/                    Story dialogue & bubble text (JSON)
  ├── gesture_runtime/            Gesture-recognition Python runtime (MediaPipe)
  └── tests/                      Headless test suite (run via Godot --script)
关卡编辑器/voxel_level_editor/    Mortise-tenon level editor (standalone Godot 4.7 project)
技术文档/                        Level-data / dialogue interface specs
licenses/                        Third-party license full texts (OFL x2 / Apache-2.0 / MIT)
```

## 🎮 Download & Play (zero setup)

1. Grab **千年一榫_安装包_v1.0.0_20261101.exe** (~299 MB) from [**Releases**](https://github.com/VicChenBike/a-thousand-years-of-joinery/releases/latest).
2. Double-click to install (Inno Setup; the **complete Python runtime for gesture recognition is embedded** — no Godot, no Python setup needed).
3. Launch from the desktop or Start menu; the game is fully playable with keyboard & mouse.

> Requirements: Windows 10/11 (64-bit). Optional gesture control only needs a regular webcam — every dependency ships inside the installer.

## 🛠 Run from Source (developers)

1. Install [Godot 4.7](https://godotengine.org/download/archive/) (standard build; no .NET needed).
2. Open `游戏项目/千年一榫/project.godot` in Godot and press F5.

### Gesture control (optional, source runs only — already embedded in the installer)

When running from source, gesture recognition runs as a separate Python process (`游戏项目/千年一榫/gesture_runtime/`) talking to the game over local UDP:

1. Install **Python 3.13** (mediapipe 0.10.x verified lock; see `gesture_runtime/requirements.txt`).
2. `pip install -r 游戏项目/千年一榫/gesture_runtime/requirements.txt` (MediaPipe / OpenCV / NumPy).
3. Enable gestures & the camera under Settings → Gesture; any ordinary single webcam works (built-in or USB).

> The gesture process and the game communicate over local UDP (default ports 9876/9877/9878). With the camera off, the gesture subsystem stays idle and keyboard & mouse play is unaffected.

## Headless tests

The project ships 165 headless Godot test files (`游戏项目/千年一榫/tests/test_*.gd`):

```bash
godot --headless --path 游戏项目/千年一榫 --script res://tests/test_main_menu.gd
```

The level-editor project works the same way (`关卡编辑器/voxel_level_editor/tests/`).

## Level editor & data specs

- The editor supports per-domain resizing, five level slots, live autosave and playtesting; it produces five-file level data.
- Contracts: `技术文档/接口规范_关卡数据.md` (level data) and `技术文档/接口规范_剧情对话.md` (dialogue & bubbles).

## Contributing

Issues for bug reports and suggestions are always welcome. To contribute code, four steps:

1. **Fork** the repository (`your-username/your-repo`);
2. **Create a branch**: `git checkout -b feature/your-feature`;
3. **Commit your changes**: `git commit -m "Describe your change"`;
4. **Open a Pull Request**.

Please run the headless tests before submitting (pick any test file — a few more won't hurt):

```bash
godot --headless --path 游戏项目/千年一榫 --script res://tests/test_main_menu.gd
```

## License

[MIT](./LICENSE)

For third-party assets and components, see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Full license texts are bundled under [licenses/](./licenses/).
