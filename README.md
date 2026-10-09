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
| `scripts/battle/` | 战斗规则：`CombatEngine`、RNG、`BattleCard` |
| `tests/smoke_test.gd` | 移动、碰撞与胜利验证 |
| `tests/combat_engine_test.gd` | 战斗规则验证 |
| `tests/battle_demo_test.gd` | 战斗 Demo 与引擎状态核对 |
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

## 战斗 Demo（v0.3）

在编辑器中打开 `scenes/cards/card_demo.tscn`，按 **F6** 单独运行。**F5** 仍运行 `scenes/main.tscn` 的收集原型，主场景不变。

规则对齐 HTML 对照稿 `temp/` 下的 v0.3 单角色限时版：`temp/` 只作对照，不加入游戏导出。战斗规则在 `scripts/battle/`（`CombatEngine`、`CombatRng`、`BattleCard`），界面由卡牌 Demo 场景驱动。

### 操作

点选 **两张数字 + 一张运算符** 后发射。快捷键：`1–5` 选手牌，`Enter` / `Space` 发射或追击，`E` 结束回合，`B` 烧掉回血，`Esc` 清空选牌，`P` 暂停，`H` 帮助，`A` / `+` 与 `X` / `*` 选符号。界面可缩放：`Ctrl + 滚轮`、`Ctrl +` / `Ctrl -`，`Ctrl + 0` 恢复 100%。拉大窗口会按 1440×900 等比放大。

### 规则摘要

- **牌库**：15 张混合牌。数字 −5…+5 各一张（元素按 `(value+5)%3` 轮换火/冰/雷），`+`、`×` 各两张。无减、无除、无定式、无能量。
- **手牌**：每回合抽 **5 张**。发射消耗三张进弃牌，**当回合不补牌**。
- **算式**：必须两数一符。正值才造成伤害并触发元素/追击；非正结果仍消耗三张牌，伤害为 0。默认打出后才显示结果（帮助里可提前查看，本局不计分）。
- **时限**：玩家回合 **10 秒**；`E` 可提前结束，时间到走敌方。
- **烧掉**：立即回血 `|n|×10`，该牌永久离库。拒绝符号、0、满血，以及会让牌库无法再打出正值攻击的烧掉。
- **追击**：加法追击跨回合累计。连续两次正值加法 → 回合结束后 3 秒追击（每击 2 伤害）。乘法或非正结果打断未完成追击。
- **元素**（仅乘法且 `base > 0`）：火火灼烧 4；冰冰冻结；雷雷 +6；火冰蒸汽 +8；火雷过载 +4 且灼烧 2；冰雷超导易伤 2 次（正值算式伤害 ×1.5 再向上取整）。灼烧在敌方出手前结算后层数减半；冻结使意图伤害减半。
- **双方**：玩家 80/100 HP，敌人「深渊观测者」120 HP。意图伤害 `8/10/12`（第 1–3 回合）之后每回合 +1。洗牌 RNG 默认 seed `20261009`，同 seed 可重开同一顺序。

### 战斗验证

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script tests/smoke_test.gd
godot --headless --path . --script tests/combat_engine_test.gd
godot --headless --path . --script tests/battle_demo_test.gd
```

`combat_engine_test` 无界面，覆盖牌库组成、区不变量、同 seed 抽牌、发射不补牌、非正伤害 0、六种反应、追击、烧掉拒绝、意图与灼烧、超时与暂停取消计分。`battle_demo_test` 实例化 Demo，核对点选发射、烧掉、结束回合和倒计时与引擎状态一致。GitHub Actions 同时运行收集原型 smoke 测试与上述两套战斗测试，再导出 Windows 包。
