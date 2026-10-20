# 重生之我在魔法世界手搓黑科技 · TapTap Game Jam 2026

基于 **Godot 4.7.2 **的肉鸽卡牌游戏。

核心玩法：跑图闯关 + 算式卡牌战斗。在10s限时内，玩家要用卡牌组出变长算式进行攻击。

## 启动

用 Godot 4.7.2 导入根目录 `project.godot`，按 **F5** 运行，进入主菜单
`scenes/menu/main_menu.tscn`，从跑图 `scenes/run/run_shell.tscn` 进入战斗
`scenes/run/run_battle.tscn`。

游戏中各界面统一点击右上角的圆形暂停按钮，或按 **Esc**，可暂停、继续、返回主菜单或退出游戏。背包打开时，第一次 Esc 关闭背包。当前版本尚未接入磁盘存档，返回主菜单或退出会丢失本局进度，离开前会再次确认。

战斗开场有 **5 秒准备期**，显示怪物特性和首回合意图，准备结束才开始回合计时。悬停怪物名称或特性可查看完整说明与当前状态（悬停不会暂停）。获胜后展示 **2 秒「战斗胜利」**，再进入奖励；背包和暂停菜单会暂停这两段倒计时。战斗面板及其背包、暂停菜单沿用灰白纸片按钮风格。

## 结构
=======
## 操作与战斗规则

- 各界面点击右上角圆形暂停按钮或按 **Esc**：暂停、继续、返回主菜单或退出；
  背包打开时第一次 Esc 关闭背包。
- 当前版本未接入磁盘存档，返回主菜单或退出会丢失本局进度，离开前会二次确认。
- 战斗开场有 **5 秒准备期**，展示怪物特性和首回合意图，准备结束才开始回合计时。
- 悬停怪物名称或特性可查看完整说明与当前状态（悬停不暂停）。
- 获胜后展示 **2 秒「战斗胜利」** 再进入奖励；背包和暂停菜单会暂停这两段倒计时。
- 战斗面板、背包、暂停菜单沿用灰白纸片按钮风格。

## 目录结构
>>>>>>> Stashed changes

| 路径 | 用途 |
| --- | --- |
| `scenes/` | 游戏场景（主菜单、卡牌视图、跑图、战斗、背包） |
| `scenes/run/enemies/` | 怪物场景（default、ink、parity、priest） |
| `scripts/cards/` | 卡牌实例、牌库、算式、抽牌、强化、怪物规则 |
| `scripts/run/` | 跑图、战斗会话、事件、奖励入口与界面表现 |
| `scripts/config/` | `jam_1.0.0` 配置加载与启动校验 |
| `data/config/jam_1.0.0/` | 卡牌、强化、起始牌组、战斗规则、收藏品配置 |
| `tests/` | 卡牌规则（C01–C12、E01–E08）、牌面与战斗资源测试 |
| `docs/` | 策划案、配置表、UI 交互等设计文档 |
| `export_presets.cfg` | Windows x86_64 导出预设 |
| `.github/workflows/` | 固定 4.7.2 的检查与 Windows 构建流水线 |

## 构建与检查

本地命令（将 `godot` 替换为你的 Godot 可执行文件路径）：

```powershell
# 编辑器无头检查
godot --headless --path . --editor --quit

# 导出 Windows 版本
New-Item -ItemType Directory -Force build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/emergence.exe
```

本地导出需在 Godot 中安装 **4.7.2 导出模板**。推送到 main 后，GitHub Actions 自动安装
对应模板、跑检查并生成 Windows 游戏，完成后在 Actions 的 Artifacts 下载
`emergence-windows`。

`.godot/` 缓存与 `build/` 导出文件不提交。后续美术、音频、关卡按需加入 `assets/` 和
`scenes/`。

## 测试

```powershell
# 卡牌规则测试（案例 C01–C12、E01–E08）
godot --headless --path . --script tests/card_rules_test.gd

# 牌面绘制测试
godot --headless --path . --script tests/card_art_test.gd

# 战斗资源集成测试
godot --headless --path . --script tests/battle_assets_integration_test.gd
```
