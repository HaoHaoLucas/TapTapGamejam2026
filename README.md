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

## 卡牌最小原型

在编辑器中打开 `scenes/cards/card_demo.tscn`，按 **F6** 单独运行。F5 仍运行原有收集原型。

测试手牌固定为 `3、5、2、4、×、+、-、÷`，外加一张牌面为“定式”的特殊牌。特殊牌的模板是 `□ ÷ □ - □ × □`。自由组式时，把 `3 × 5` 拖入表达式显示 15，再追加 `+ 2` 显示 17。

`×` 和 `÷` 优先于 `+` 和 `-`，同一级从左到右。因此 `3 + 5 × 2` 为 13，`3 × 5 + 2` 为 17，`8 ÷ 4 × 2` 为 4，`8 ÷ 2 - 3 × 4` 为 -8。末尾还没补上数字的运算符不参与计算，`3 + 5 ×` 的结果是 8。除法按精确分数计算，所以 `10 ÷ 3 × 3` 回到 10，`8 ÷ 3 × 3` 回到 8。单独的 `8 ÷ 3` 是 8/3，界面写成 `2.666…`；`-7 ÷ 2` 写成 `-3.5`。小数由分数直接展开，不会出现二进制浮点尾巴。实际执行到的除法只要除数为 0，预览和结算都是 0，并显示“除以零”。结构不完整时结果为 0，显示“未完成”，并且不会进入运算。

- 将表达式中的任意牌拖回手牌区，该牌回到手牌末尾，其余牌自动挤紧。手牌区为空时也可投放。
- 拖手牌到表达式卡牌的左半侧可插在它前面，右半侧可插在它后面；两牌之间的间隙可插牌，其他空白处追加到末尾。绿色竖线显示插入位置，换行后仍按目标牌的位置插入。
- 拖回中间的 `5` 后，`3 × 5 + 2` 变成 `3 × + 2`，显示“未完成”，当前结果及回合结算为 0；把 `5` 插回 `×` 和 `+` 之间后恢复 17。
- 允许暂时出现开头为运算符、相邻数字或相邻运算符的无效算式，方便自由编辑。区域外投放取消操作；表达式内部直接拖动排序不生效，需要先拖回手牌再插入。

把特殊牌拖到表达式区即打出：已经放入的实体牌退回手牌末尾，表达式换成模板格子。特殊牌本回合离开手牌，不烧毁；下一回合由调用方把原数组再传给 `start_player_turn` 时它会回来。“怪物定式”按钮调用同一接口，锁上 `-1 □ 2 □ 6 □ -3`，玩家只能把符号牌放进空格。

定式的每一格单独锁定或开放。锁定格是暗金色，不是实体牌，不能拖走、退回或烧毁。空格显示 `□`，只接受相同种类的手牌；空白处和错误种类会被拒绝。玩家放进空格的牌可以拖回手牌。空格没填满时结果为 0，例如 `定式 -1 □ 2 □ 6 □ -3 · 结果 0 · 未完成`。再次打出特殊牌或再次调用接口时，先退回已放入的实体牌，再换成新定式。`start_player_turn` 和 `reset_battle` 都会清掉定式。

界面保留 HP、倒计时、结果、手牌、烧牌、回合按钮和“怪物定式”。拖数字手牌到烧牌区后，该牌本场移除，累加 `|数值| × 10` 的待结算回血；符号牌和特殊牌不能烧，表达式里的牌需先拖回手牌。定式期间仍可烧毁数字手牌。烧牌不可撤销。

每回合默认 30 秒，手动结束或倒计时归零均锁定操作并结算一次。“下一回合”清空表达式、待回血和计时，恢复测试手牌池中未烧毁的牌。空表达式返回 0，末尾待补数字的运算符忽略，例如 `3 ×` 返回 3。独立 Demo 以 70/100 HP 演示回合结束回血并限制到最大 HP，尚无怪物攻击、牌库和随机抽牌。

### 战斗模块接入

将 `scenes/cards/card_panel.tscn` 实例化为战斗 UI 的子节点，交由父容器控制尺寸。`CardPanel` 管理牌与待回血；独立的 `BattleHUD` 显示血量与时间，并提供可选倒计时。正式接入时由战斗模块统一拥有 HP 和回合状态，不需要使用独立测试场景的按钮。

```gdscript
const CardPanelScene = preload("res://scenes/cards/card_panel.tscn")
var cards_ui: CardPanel

func _ready() -> void:
    cards_ui = CardPanelScene.instantiate()
    $BattleUI.add_child(cards_ui)
    cards_ui.preview_changed.connect(_on_preview_changed)
    var hand: Array[CardData] = [
        CardData.number_card(3),
        CardData.operator_card("×"),
        CardData.number_card(5),
    ]
    cards_ui.start_player_turn(hand)

func _on_preview_changed(result: float) -> void:
    print("当前结果：", result)

func settle_player_turn() -> void:
    var result: float = cards_ui.finish_player_turn()
    print("本回合结果：", result) # 战斗模块自行换算伤害、更新 HP。
```

- `start_player_turn(cards: Array[CardData]) -> void`：开启操作并重置表达式，初始触发 `preview_changed(0)`。传入数组不会被面板修改；每张实体牌必须是独立 `CardData`，回合中不要修改其内容。
- `finish_player_turn() -> float`：锁定操作并返回整式约分后的浮点值，重复调用返回相同结果。`10 ÷ 3 × 3` 返回的是整数 10 转成的浮点，不是先把 `10 ÷ 3` 变成浮点再乘。需要避免这一次转换时，用 `get_exact_result()` 读取分数。战斗模块仍需保证伤害结算只执行一次；开始下一回合应再次调用 `start_player_turn`。
- `get_exact_result() -> Rational`：当前精确分数。整数时分母为 1。回合结束后仍返回本次结算的分数。
- `preview_changed(result: float)`：成功插入、填格、退回或套用定式后通知约分后的浮点值。无效算式、未填满的定式和除以零都通知 0；取消投放不触发。界面文字使用分数展开的小数，不使用这个浮点值来排版。
- `CardData.number_card(value)` 支持整数。`CardData.operator_card(symbol)` 支持 `+`、`-`、`×`、`÷`。`CardData.special_card(slots)` 创建特殊牌，并保存模板的副本。每张牌自动获得独立 `instance_id`，同值牌可以分别使用。
- `FormulaSlot.open_number()`、`open_operator()`、`locked_number(value)`、`locked_operator(symbol)` 描述定式的一格。模板必须从数字开始、数字与运算符交替、并以数字结束。
- `apply_formula_constraint(slots) -> bool`：仅操作期有效。先把表达式中的实体牌退回手牌末尾，再安装模板的副本；填格不会改到调用方或特殊牌上的模板。模板不合法时保持原样并返回 `false`。
- `has_formula_constraint() -> bool`：当前回合是否套着定式。下一回合 `start_player_turn` 或 `reset_battle` 后为 `false`。
- `get_pending_heal() -> int`：本回合累计回血，结束回合后仍可读取，下一回合清零。战斗模块在同一次回合结算中应用它，不要在烧牌信号回调中再重复回血。
- `card_burned(instance_id: int, heal: int)`：成功烧牌时通知移除的实体牌及新增待回血。队友的牌库模块据此移除本场对应实体牌；`CardPanel` 同时会过滤后续传入的相同 ID。不要以新 ID 重建已烧毁的实体牌。
- `burn_card(instance_id: int) -> bool`：仅能在操作期烧毁数字手牌；倍率由 `burn_heal_multiplier` 配置，默认 10。
- `reset_battle()`：复用面板进入新战斗时调用，清空手牌、表达式、已烧毁 ID 和待回血，然后调用 `start_player_turn`。普通下一回合不调用它。

面板随父容器宽度换行；拖拽仅能操作本面板、本回合且仍在来源区域中的牌。结束回合后双向拖拽都被锁定。战斗模块负责处理负结果的伤害规则。卡牌模块先按优先级把算式约成精确分数，再转成浮点返回；除以零时返回 0。

```gdscript
var locked: Array[FormulaSlot] = [
    FormulaSlot.locked_number(-1),
    FormulaSlot.open_operator(),
    FormulaSlot.locked_number(2),
    FormulaSlot.open_operator(),
    FormulaSlot.locked_number(6),
    FormulaSlot.open_operator(),
    FormulaSlot.locked_number(-3),
]
cards_ui.apply_formula_constraint(locked)
```

卡牌交互层可调用 `insert_card(instance_id: int, insertion_index: int) -> bool`。没有定式时，索引是自由插入位置（从 0 开始，可等于当前长度）。定式生效时，索引是格子序号，只能填入开放、为空且种类相符的格子。`return_card(instance_id: int) -> bool` 把表达式中的指定实体牌退回手牌末尾；锁定格没有实体牌，不能退回。成功返回 `true` 并发出预览信号；回合已结束、牌不在来源区域、插入位置越界或格子不接受该牌时返回 `false`。拖拽入口额外校验来源区域、面板及回合，阻止重复投放和跨回合旧拖拽。特殊牌拖到表达式区会打出定式，不会插入算式。

### 血量与倒计时接口

在战斗 UI 中实例化 `BattleHUD.new()` 并添加到场景树，脚本为 `scripts/cards/battle_hud.gd`：

| 接口 | 用法 |
| --- | --- |
| `set_health(current, maximum)` | 战斗模块在扣血/回血后同步显示；HUD 不自行修改游戏 HP。 |
| `start_countdown(seconds = 30.0)` | 使用 HUD 自带倒计时，归零触发一次 `time_expired`。添加到场景树后调用。 |
| `stop_countdown()` | 手动结束或战斗结束时停止，保留当前剩余时间显示。 |
| `get_time_remaining()` | 读取剩余秒数。 |
| `set_time_remaining(seconds)` | 队友已有计时器时使用；停止 HUD 自带计时，只更新显示，显示 0 不自动触发结算。 |
| `time_expired` 信号 | 使用自带计时时连接到战斗模块的统一回合结束方法。 |

使用自带计时器时，手动结束按钮与 `time_expired` 应连接到同一结算方法。先用 `cards_ui.is_turn_active()` 防止重复结算，再调用 `finish_player_turn()` 锁定出牌，`hud.stop_countdown()` 停止计时，读取 `get_pending_heal()` 处理回血并调用 `hud.set_health(...)`。队友已有计时器时仅调用 `set_time_remaining(...)`，并由自己的计时器负责结算。

### 卡牌验证

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script tests/card_test.gd
godot --headless --path . --script tests/card_ui_test.gd
godot --headless --path . --script tests/battle_hud_test.gd
# 有界面运行同一测试，额外生成 build/card_demo*.png 用于检查实际渲染。
godot --path . --script tests/card_ui_test.gd
```

逻辑测试覆盖优先级、整数除法与除以零、定式的符号锁/数字锁/混锁、模板复制、非法模板、特殊牌打出与回手、回合清除，以及任意位置退回和插入、烧牌绝对值回血、符号牌与特殊牌拒绝、已烧牌跨回合移除及新战斗重置。UI 测试通过原生鼠标输入覆盖自由组式拖拽、中间/换行插入、烧牌投放、回血上限、定式格子投放和操作锁定；HUD 测试覆盖倒计时自动结算、手动结束取消计时、避免重复结算和外部计时接管。截图包括烧牌、移除中间牌后的状态、插入提示和换行布局。GitHub Actions 同时运行原有玩法、卡牌和 HUD 测试。
