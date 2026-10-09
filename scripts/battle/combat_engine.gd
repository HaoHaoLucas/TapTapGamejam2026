class_name CombatEngine
extends RefCounted
## Deterministic combat rules ported from HTML v0.3 CombatEngine.
## Every physical card has one ID and belongs to exactly one zone.
## A cast moves TWO numbers and ONE physical operator to discard.
## Drawing happens only at the beginning of a turn, never after casting/burning.

const DEFAULT_SEED := 20261009
const CFG := {
	"turnSeconds": 10,
	"handSize": 5,
	"deckSize": 15,
	"maxHp": 100,
	"initialHp": 80,
	"enemyHp": 120,
	"healPerValue": 10,
	"burstSeconds": 3,
	"burstDamage": 2,
	"defaultSeed": DEFAULT_SEED,
	"enemyWindup": 0.24,
	"enemyRecover": 0.28,
}
const ELEMENTS := {
	"fire": {"name": "火", "label": "余烬", "color": "#f6a66d"},
	"ice": {"name": "冰", "label": "霜晶", "color": "#85d8e6"},
	"spark": {"name": "雷", "label": "电荷", "color": "#c4a1fa"},
}

signal state_changed(state: Dictionary)
signal effect_emitted(effect: Dictionary)
signal ticked(state: Dictionary)

var on_change: Callable = Callable()
var on_effect: Callable = Callable()
var on_tick: Callable = Callable()
var seed: int = DEFAULT_SEED
var clock: float = 0.0
var s: Dictionary = {}

var _rng: CombatRng
var effects: Array = []
var log_seq: int = 0


func _init(options: Dictionary = {}) -> void:
	on_change = options.get("on_change", options.get("onChange", Callable()))
	on_effect = options.get("on_effect", options.get("onEffect", Callable()))
	on_tick = options.get("on_tick", options.get("onTick", Callable()))
	seed = int(options.get("seed", CFG.defaultSeed)) & CombatRng.UINT32
	reset(false)


func reset(notify: bool = true) -> void:
	_rng = CombatRng.new(seed)
	clock = 0.0
	effects = []
	log_seq = 0
	var deck: Array = CombatRng.create_deck()
	var all_ids: Array = []
	for card in deck:
		all_ids.append(card.id)
	s = {
		"phase": "intro",
		"paused": false,
		"ranked": true,
		"showPreview": false,
		"seed": seed,
		"round": 1,
		"hp": CFG.initialHp,
		"maxHp": CFG.maxHp,
		"draw": _rng.shuffle(deck),
		"discard": [],
		"hand": [],
		"burned": [],
		"allIds": all_ids,
		"selected": [],
		"operatorId": null,
		"burnMode": false,
		"target": 0,
		"enemies": [{
			"id": 0,
			"kind": "watcher",
			"name": "深渊观测者",
			"hp": CFG.enemyHp,
			"maxHp": CFG.enemyHp,
			"burn": 0,
			"chill": false,
			"vulnerable": 0,
		}],
		"remaining": CFG.turnSeconds,
		"streak": 0,
		"windows": 0,
		"burstRemaining": 0.0,
		"burstDuration": 0.0,
		"burstHits": 0,
		"lastBurstHit": -100.0,
		"enemyStage": null,
		"enemyRemaining": 0.0,
		"lastEquation": "",
		"reaction": "",
		"lastDecision": null,
		"stats": {
			"equations": 0,
			"positiveEquations": 0,
			"addition": 0,
			"multiplication": 0,
			"damage": 0,
			"healing": 0,
			"burned": 0,
			"hits": 0,
			"windows": 0,
			"time": 0.0,
			"rounds": 1,
			"skips": 0,
		},
		"log": [],
	}
	if notify:
		self.notify()


func notify() -> void:
	if on_change.is_valid():
		on_change.call(s)
	state_changed.emit(s)
	var events: Array = effects.duplicate()
	effects.clear()
	for event in events:
		if on_effect.is_valid():
			on_effect.call(event)
		effect_emitted.emit(event)


func fx(type: String, data: Dictionary = {}) -> void:
	var event := {"type": type}
	for key in data:
		event[key] = data[key]
	effects.append(event)


func note(text: String, type: String = "info", data: Dictionary = {}) -> void:
	log_seq += 1
	var entry := {
		"seq": log_seq,
		"at": _fixed(clock, 3),
		"round": s.round,
		"type": type,
		"text": text,
	}
	for key in data:
		entry[key] = data[key]
	s.log.append(entry)
	if s.log.size() > 1500:
		s.log.pop_front()


func message(text: String) -> bool:
	fx("message", {"text": text})
	notify()
	return false


func active() -> bool:
	return s.phase == "player" and not s.paused


func start(p_seed: Variant = null) -> void:
	if p_seed == null:
		p_seed = seed
	seed = int(p_seed) & CombatRng.UINT32
	reset(false)
	s.phase = "player"
	fill_hand()
	note("本局 %s 开始：15 张牌，每回合抽 5 张。" % seed)
	fx("phase", {"text": "你的回合", "sub": "10 秒倒计时"})
	notify()


func set_paused(value: bool) -> void:
	s.paused = value
	if value and s.phase in ["player", "burst", "enemy"]:
		s.ranked = false
	notify()


func set_preview(value: bool) -> void:
	s.showPreview = value
	if value and s.phase != "intro":
		s.ranked = false
	notify()


func take_card() -> Variant:
	if s.draw.is_empty() and not s.discard.is_empty():
		s.draw = _rng.shuffle(s.discard)
		s.discard = []
		note("弃牌洗回抽牌堆。", "shuffle")
	if s.draw.is_empty():
		return null
	return s.draw.pop_back()


func fill_hand() -> void:
	s.hand = []
	for _i in range(int(CFG.handSize)):
		var card = take_card()
		if card != null:
			s.hand.append(card)


func cards_selected() -> Array:
	var chosen: Array = []
	for id in s.selected:
		var card := _hand_card(id)
		if card != null:
			chosen.append(card)
	return chosen


func selected_operator() -> BattleCard:
	if s.operatorId == null:
		return null
	var card := _hand_card(str(s.operatorId))
	if card != null and card.type == "operator":
		return card
	return null


func choose_card(id: String) -> bool:
	if not active():
		return false
	var card := _hand_card(id)
	if card == null:
		return false
	if s.burnMode:
		return burn(id)
	if card.type == "operator":
		s.operatorId = null if s.operatorId == id else id
	else:
		var selected: Array = s.selected
		var index: int = selected.find(id)
		if index >= 0:
			selected.remove_at(index)
		elif selected.size() < 2:
			selected.append(id)
		else:
			selected[1] = id
	fx("select")
	notify()
	return true


func choose_operator(op: String) -> bool:
	if not active():
		return false
	var card: BattleCard = null
	for item in s.hand:
		if item != null and item.type == "operator" and item.op == op:
			card = item
			break
	if card == null:
		return message("手里没有「%s」。" % op)
	s.burnMode = false
	return choose_card(card.id)


func clear() -> bool:
	if not active():
		return false
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	notify()
	return true


func toggle_burn() -> bool:
	if not active():
		return false
	s.burnMode = not s.burnMode
	s.selected = []
	s.operatorId = null
	notify()
	return true


func has_combo() -> bool:
	var live: Array = _live_hand()
	var numbers := 0
	var has_op := false
	for card in live:
		if card.type == "number":
			numbers += 1
		elif card.type == "operator":
			has_op = true
	return numbers >= 2 and has_op


func preview() -> Variant:
	var nums: Array = cards_selected()
	var operator := selected_operator()
	if nums.size() != 2 or operator == null or s.enemies[0].hp <= 0:
		return null
	var a: BattleCard = nums[0]
	var b: BattleCard = nums[1]
	var op: String = operator.op
	var enemy: Dictionary = s.enemies[0]
	var base: int = (a.value + b.value) if op == "+" else (a.value * b.value)
	var p := {
		"base": base,
		"op": op,
		"operatorId": operator.id,
		"damage": maxi(0, base),
		"bonus": 0,
		"burn": 0,
		"chill": false,
		"vulnerable": 0,
		"name": "加法" if op == "+" else "元素反应",
		"description": "",
		"color": "gold" if op == "+" else "ice",
		"factor": 1.5 if enemy.vulnerable > 0 else 1.0,
	}
	if base <= 0:
		p.name = "未形成攻击"
		p.description = "结果不大于 0：造成 0 伤害，不触发元素或追击。"
		p.damage = 0
		return p
	if op == "×":
		var pair_elems: Array = [a.elem, b.elem]
		pair_elems.sort()
		var pair: String = "%s-%s" % [pair_elems[0], pair_elems[1]]
		match pair:
			"fire-fire":
				p.name = "余烬叠燃"
				p.burn = 4
				p.description = "施加 4 层灼烧"
				p.color = "fire"
			"ice-ice":
				p.name = "冻结"
				p.chill = true
				p.description = "敌人下一次攻击减半"
				p.color = "ice"
			"spark-spark":
				p.name = "电弧穿刺"
				p.bonus = 6
				p.description = "额外造成 6 伤害"
				p.color = "spark"
			"fire-ice":
				p.name = "蒸汽爆破"
				p.bonus = 8
				p.description = "额外造成 8 伤害"
				p.color = "steam"
			"fire-spark":
				p.name = "过载"
				p.bonus = 4
				p.burn = 2
				p.description = "额外造成 4 伤害，施加 2 层灼烧"
				p.color = "fire"
			"ice-spark":
				p.name = "超导"
				p.vulnerable = 2
				p.description = "后续两次正值算式伤害 +50%"
				p.color = "spark"
	else:
		p.description = "再打一次正数加法可追击" if s.streak == 1 else "连续两次正数加法可追击"
	p.damage = ceili(float(base + int(p.bonus)) * float(p.factor))
	return p


func damage(amount: float, kind: String = "gold") -> int:
	if not is_finite(amount) or amount < 0.0:
		push_error("Damage must be nonnegative and finite")
		return 0
	var enemy: Dictionary = s.enemies[0]
	var floored := floori(amount)
	var actual: int = mini(int(enemy.hp), floored)
	enemy.hp = int(enemy.hp) - actual
	s.stats.damage = int(s.stats.damage) + actual
	fx("damage", {"target": 0, "amount": floored, "actual": actual, "kind": kind, "killed": int(enemy.hp) <= 0})
	return actual


func fire() -> bool:
	if not active():
		return false
	var p = preview()
	if p == null:
		return message("先点两张数字和一张符号。")
	var nums: Array = cards_selected()
	var a: BattleCard = nums[0]
	var b: BattleCard = nums[1]
	var enemy: Dictionary = s.enemies[0]
	s.stats.equations = int(s.stats.equations) + 1
	if p.op == "+":
		s.stats.addition = int(s.stats.addition) + 1
	else:
		s.stats.multiplication = int(s.stats.multiplication) + 1
	if int(p.base) > 0:
		s.stats.positiveEquations = int(s.stats.positiveEquations) + 1
	if p.op == "+" and int(p.base) > 0:
		s.streak = int(s.streak) + 1
		if int(s.streak) == 2:
			s.streak = 0
			s.windows = int(s.windows) + 1
			s.stats.windows = int(s.stats.windows) + 1
			fx("window")
	else:
		s.streak = 0
	damage(float(p.damage), p.color)
	if int(p.base) > 0:
		if int(enemy.vulnerable) > 0:
			enemy.vulnerable = int(enemy.vulnerable) - 1
		if int(enemy.hp) > 0:
			enemy.burn = int(enemy.burn) + int(p.burn)
			if p.chill:
				enemy.chill = true
			if int(p.vulnerable) > 0:
				enemy.vulnerable = int(p.vulnerable)
	s.lastEquation = "%s %s %s = %s" % [_fmt_term(a.value), p.op, _fmt_term(b.value), _fmt(int(p.base))]
	s.reaction = p.name
	s.lastDecision = _fixed(float(CFG.turnSeconds) - float(s.remaining), 2)
	note(
		"%s → %s 伤害 · %s。三张牌进入弃牌堆。" % [s.lastEquation, p.damage, p.name],
		"addition" if p.op == "+" else "multiplication",
		{"formula": s.lastEquation, "damage": p.damage, "consumed": [a.id, p.operatorId, b.id], "decision": s.lastDecision}
	)
	var used := {a.id: true, str(p.operatorId): true, b.id: true}
	for i in s.hand.size():
		var card = s.hand[i]
		if card != null and used.has(card.id):
			s.discard.append(card)
			s.hand[i] = null
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	fx("shot", {"target": 0, "op": p.op, "color": p.color, "name": p.name, "formula": s.lastEquation, "amount": p.damage})
	if int(enemy.hp) <= 0:
		finish("victory")
	notify()
	return true


func burn(id: String) -> bool:
	if not active():
		return false
	var index := _hand_index(id)
	if index < 0:
		return false
	var card: BattleCard = s.hand[index]
	if card.type != "number":
		return message("符号牌不能烧掉。")
	if card.value == 0:
		return message("0 不能回血，这张牌还在。")
	if int(s.hp) >= int(s.maxHp):
		return message("生命已满，没有烧掉。")
	var nums: Array = []
	for item in _live_hand() + s.draw + s.discard:
		if item.type == "number" and item.id != id:
			nums.append(item)
	var viable := false
	for i in nums.size():
		for j in range(i + 1, nums.size()):
			if nums[i].value + nums[j].value > 0 or nums[i].value * nums[j].value > 0:
				viable = true
				break
		if viable:
			break
	if nums.size() < 2 or not viable:
		return message("再烧就凑不出正数攻击了，这张牌还在。")
	var heal: int = mini(int(s.maxHp) - int(s.hp), absi(card.value) * int(CFG.healPerValue))
	s.hp = int(s.hp) + heal
	s.burned.append(card)
	s.hand[index] = null
	s.stats.burned = int(s.stats.burned) + 1
	s.stats.healing = int(s.stats.healing) + heal
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	note(
		"烧掉数字 %s，回复 %s 生命。本局少 1 张牌，本回合不补。" % [_fmt(card.value), heal],
		"burn",
		{"card": card.to_dict(), "healing": heal}
	)
	fx("heal", {"amount": heal, "card": card})
	notify()
	return true


func intent() -> Dictionary:
	var enemy: Dictionary = s.enemies[0]
	var r: int = int(s.round)
	var dmg: int = [8, 10, 12][mini(r - 1, 2)] + maxi(0, r - 3)
	if enemy.chill:
		dmg = floori(float(dmg) / 2.0)
	return {"damage": dmg, "verb": "裂隙冲击" if r < 3 else "深渊崩解", "chilled": enemy.chill}


func end_turn() -> bool:
	if not active():
		return false
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	var acted := false
	for entry in s.log:
		if int(entry.round) == int(s.round) and entry.type in ["addition", "multiplication"]:
			acted = true
			break
	if not acted:
		s.stats.skips = int(s.stats.skips) + 1
	if int(s.windows) > 0:
		s.phase = "burst"
		s.burstDuration = float(s.windows) * float(CFG.burstSeconds)
		s.burstRemaining = s.burstDuration
		s.burstHits = 0
		s.lastBurstHit = -100.0
		s.windows = 0
		note("回合后的追击开始。", "burst")
		fx("phase", {"text": "追击时刻", "sub": "连点空格或追击按钮"})
	else:
		begin_enemy()
	notify()
	return true


func burst_hit() -> bool:
	if s.phase != "burst" or s.paused or clock - float(s.lastBurstHit) < 0.055:
		return false
	s.lastBurstHit = clock
	s.burstHits = int(s.burstHits) + 1
	s.stats.hits = int(s.stats.hits) + 1
	damage(float(CFG.burstDamage), "burst")
	fx("punch", {"target": 0, "count": s.burstHits})
	if int(s.enemies[0].hp) <= 0:
		finish("victory")
	notify()
	return true


func begin_enemy() -> void:
	s.phase = "enemy"
	s.enemyStage = "windup"
	s.enemyRemaining = CFG.enemyWindup
	note("敌方即将行动。", "phase")


func enemy_attack() -> void:
	var enemy: Dictionary = s.enemies[0]
	if int(enemy.burn) > 0:
		var amount: int = int(enemy.burn)
		enemy.burn = floori(float(enemy.burn) / 2.0)
		damage(float(amount), "fire")
		note("灼烧造成 %s 伤害。" % amount, "dot")
		if int(enemy.hp) <= 0:
			finish("victory")
			return
	var next_intent := intent()
	enemy.chill = false
	var actual: int = mini(int(s.hp), int(next_intent.damage))
	s.hp = int(s.hp) - actual
	note("%s造成 %s 伤害。" % [enemy.name, actual], "enemy")
	fx("enemyAttack", {"target": 0, "amount": actual})
	if int(s.hp) <= 0:
		finish("defeat")
		return
	s.enemyStage = "recover"
	s.enemyRemaining = CFG.enemyRecover


func new_round() -> void:
	for card in _live_hand():
		s.discard.append(card)
	s.hand = []
	s.round = int(s.round) + 1
	s.stats.rounds = s.round
	fill_hand()
	s.phase = "player"
	s.remaining = CFG.turnSeconds
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	note("第 %s 回合开始，抽取 %s 张牌。" % [s.round, _live_hand().size()], "phase")
	fx("round", {"round": s.round})


func finish(phase: String) -> void:
	s.phase = phase
	s.selected = []
	s.operatorId = null
	s.burnMode = false
	note("观测者已击败。" if phase == "victory" else "实验员倒下。", phase)
	fx("outcome", {"outcome": phase})


func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0 or s.paused:
		return
	var left := seconds
	var changed := false
	var guard := 0
	while left > 1e-8 and s.phase in ["player", "burst", "enemy"] and guard < 10000:
		guard += 1
		var phase: String = s.phase
		var limit: float = float(s.remaining)
		if phase == "burst":
			limit = float(s.burstRemaining)
		elif phase == "enemy":
			limit = float(s.enemyRemaining)
		var step: float = minf(left, maxf(0.0, limit))
		clock += step
		left -= step
		if phase != "enemy":
			s.stats.time = float(s.stats.time) + step
		if phase == "player":
			s.remaining = maxf(0.0, float(s.remaining) - step)
			if float(s.remaining) <= 1e-8:
				s.remaining = 0.0
				end_turn()
				changed = true
		elif phase == "burst":
			s.burstRemaining = maxf(0.0, float(s.burstRemaining) - step)
			if float(s.burstRemaining) <= 1e-8:
				begin_enemy()
				changed = true
		else:
			s.enemyRemaining = maxf(0.0, float(s.enemyRemaining) - step)
			if float(s.enemyRemaining) <= 1e-8:
				if s.enemyStage == "windup":
					enemy_attack()
				else:
					new_round()
				changed = true
	if changed:
		notify()
	if on_tick.is_valid():
		on_tick.call(s)
	ticked.emit(s)


func score() -> int:
	if s.phase != "victory":
		return floori(float(s.stats.damage) * 10.0)
	return maxi(0, floori(1200.0 + 6000.0 / (float(s.stats.time) + 10.0) + float(s.hp) * 5.0 - float(int(s.round) - 1) * 15.0))


func invariant() -> bool:
	var cards: Array = _live_hand() + s.draw + s.discard + s.burned
	var ids: Array = []
	for card in cards:
		ids.append(card.id)
	if ids.size() != int(CFG.deckSize):
		return false
	var unique := {}
	for id in ids:
		unique[id] = true
	if unique.size() != int(CFG.deckSize):
		return false
	for id in s.allIds:
		if not ids.has(id):
			return false
	if _live_hand().size() > int(CFG.handSize):
		return false
	for card in cards:
		if card.type == "operator":
			if card.op not in ["+", "×"]:
				return false
		elif not (card.value >= -5 and card.value <= 5):
			return false
	if int(s.hp) < 0 or int(s.hp) > int(s.maxHp):
		return false
	for enemy in s.enemies:
		if int(enemy.hp) < 0 or int(enemy.hp) > int(enemy.maxHp):
			return false
	if s.selected.size() > 2:
		return false
	for id in s.selected:
		if not _hand_has(id, "number"):
			return false
	if s.operatorId != null and not _hand_has(str(s.operatorId), "operator"):
		return false
	return true


func export_state() -> Dictionary:
	var stats: Dictionary = s.stats.duplicate()
	stats.time = _fixed(float(stats.time), 3)
	return {
		"prototype": "涌现 v0.3",
		"seed": seed,
		"rules": CFG.duplicate(),
		"composition": CombatRng.create_deck(),
		"outcome": s.phase,
		"ranked": s.ranked,
		"score": score(),
		"stats": stats,
		"burned": s.burned.duplicate(),
		"log": s.log.duplicate(),
	}


func _hand_card(id: String) -> BattleCard:
	for card in s.hand:
		if card != null and card.id == id:
			return card
	return null


func _hand_index(id: String) -> int:
	for i in s.hand.size():
		var card = s.hand[i]
		if card != null and card.id == id:
			return i
	return -1


func _hand_has(id: String, type: String) -> bool:
	for card in s.hand:
		if card != null and card.id == id and card.type == type:
			return true
	return false


func _live_hand() -> Array:
	var live: Array = []
	for card in s.hand:
		if card != null:
			live.append(card)
	return live


static func _fmt(n: int) -> String:
	return "−%s" % absi(n) if n < 0 else str(n)


static func _fmt_term(n: int) -> String:
	return "(%s)" % _fmt(n) if n < 0 else str(n)


static func _fixed(value: float, digits: int) -> float:
	var scale := pow(10.0, digits)
	return round(value * scale) / scale
