# emergence · TapTap Game Jam 2026

基于 **Godot 4.7.2 stable / GDScript / 2D Compatibility** 的游戏开发起点。

## 启动

用 Godot 4.7.2 导入根目录 `project.godot`，按 **F6** 运行当前场景或 **F5** 运行项目。
主场景为 `scenes/main.tscn`。目前提供一个可玩的俯视角收集原型，无第三方美术依赖。

- WASD / 方向键：移动，墙体阻挡玩家。
- 收集全部 5 个金色能量点即可完成关卡。
- Esc：暂停 / 继续；R：重新开始。

## 结构

| 路径 | 用途 |
| --- | --- |
| `scenes/` | 游戏场景 |
| `scripts/player.gd` | 玩家移动与碰撞 |
| `scripts/main.gd` | 关卡、收集、HUD 与流程 |
| `tests/smoke_test.gd` | 移动、碰撞与胜利验证 |
| `export_presets.cfg` | Windows x86_64 导出 |
| `.github/workflows/build.yml` | 固定 4.7.2 的检查与 Windows 构建 |

## 构建与检查

本地命令（将 godot 替换为你的 Godot 可执行文件路径）：

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script tests/smoke_test.gd
New-Item -ItemType Directory -Force build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/emergence.exe
```

本地导出需要在 Godot 中安装 **4.7.2 导出模板**。推送到 main 后，GitHub Actions 自动安装对应模板、验证原型并生成 Windows 游戏，完成后在 Actions 的 Artifacts 下载 `emergence-windows`。

`.godot/` 缓存与 `build/` 导出文件不提交。后续美术、音频、关卡可按需要加入 `assets/` 和 `scenes/`；当前原型玩法可直接替换。
