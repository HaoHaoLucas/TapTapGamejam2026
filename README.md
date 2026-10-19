# emergence · TapTap Game Jam 2026

基于 **Godot 4.7.2 stable / GDScript / 2D Compatibility** 的游戏开发起点。

## 启动

用 Godot 4.7.2 导入根目录 `project.godot`，按 **F5** 运行项目。
**F5** 打开主菜单 `scenes/menu/main_menu.tscn`。

## 结构

| 路径 | 用途 |
| --- | --- |
| `scenes/` | 游戏场景 |
| `scripts/cards/` | jam 卡牌实例、算式、抽牌与牌面 |
| `scripts/config/` | `jam_1.0.0` 配置加载与启动校验 |
| `data/config/jam_1.0.0/` | 牌、强化、起始牌组、战斗规则、收藏品 |
| `tests/card_rules_test.gd` | jam 卡牌案例 C01–C12、E01–E08 |
| `export_presets.cfg` | Windows x86_64 导出 |
| `.github/workflows/build.yml` | 固定 4.7.2 的检查与 Windows 构建 |

## 构建与检查

本地命令（将 godot 替换为你的 Godot 可执行文件路径）：

```powershell
godot --headless --path . --editor --quit
New-Item -ItemType Directory -Force build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/emergence.exe
```

本地导出需要在 Godot 中安装 **4.7.2 导出模板**。推送到 main 后，GitHub Actions 自动安装对应模板、跑检查并生成 Windows 游戏，完成后在 Actions 的 Artifacts 下载 `emergence-windows`。

`.godot/` 缓存与 `build/` 导出文件不提交。后续美术、音频、关卡可按需要加入 `assets/` 和 `scenes/`。

## 卡牌实例（jam_1.0.0）

跑图战斗使用这套规则。配置在 `data/config/jam_1.0.0/`，牌库与算式在 `scripts/cards/`，启动校验在 `scripts/config/config_catalog.gd`。F5 进入主菜单，从跑图 `scenes/run/run_shell.tscn` 进入战斗 `scenes/run/run_battle.tscn`。牌面是 `scenes/cards/card_view.tscn`。战斗里可以组变长算式、烧牌，并走 10 秒回合和加法连击窗口。

```powershell
godot --headless --path . --script tests/card_rules_test.gd
```
