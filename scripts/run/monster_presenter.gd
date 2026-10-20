extends RefCounted
## Read-only descriptions of MonsterRules. No combat mutations here.


static func describe(battle: CardBattle) -> Dictionary:
	var summary := ""
	var detail := ""
	var state := ""
	match battle.monster_id:
		MonsterRules.MON_RUST:
			summary = "长算式增伤"
			detail = "使用至少 5 个算式元素时，伤害 ×%.1f。" % MonsterRules.RUST_COEFF
		MonsterRules.MON_PARITY:
			summary = "奇偶交替"
			detail = "奇数回合要求奇数结果，偶数回合要求偶数结果。\n结果奇偶不符时，伤害 ×%.1f。" % MonsterRules.PARITY_COEFF
			state = "本回合：结果须为%s数" % ("奇" if battle.turn_index % 2 == 1 else "偶")
		MonsterRules.MON_INK:
			summary = "墨印交替"
			detail = "奇数回合：首个合法算式结果 ÷2，向零取整。\n偶数回合：首个乘法算式结果减 %d。\n结果为零或负数也会触发；每回合仅生效一次。" % MonsterRules.INK_TAX
			state = "本回合%s · %s" % ["结果 ÷2" if battle.turn_index % 2 == 1 else "乘法减 2", "已消耗" if battle.ink_tax_used else "未触发"]
		MonsterRules.MON_PRIEST:
			summary = "负数阻止治疗"
			detail = "行动后治疗自己，治疗量随楼层与房间成长。\n本回合用含负数牌的算式造成伤害，可阻止治疗。"
			state = "治疗已阻止" if battle.priest_heal_cancelled else "本回合将治疗 %d" % int(battle.intent.get("heal", 0))
		MonsterRules.MON_THIEF:
			summary = "伤害夺回扣牌"
			detail = "开场可能扣押一张牌。\n累计造成其最大生命 30% 的伤害后归还，战斗结束也会归还。"
			var ctx: RunContext = battle._ctx()
			var held: CardInstance = ctx.library.get_card(battle.stolen_card_uid) if ctx != null else null
			var threshold := ceili(battle.enemy_max_hp * 0.3)
			state = "夺回进度 %d / %d" % [mini(battle.thief_progress, threshold), threshold] if held != null and held.zone == CardInstance.STOLEN else "当前无扣押牌"
		MonsterRules.MON_SWORD:
			summary = "三回合循环 · 半血强化"
			detail = "每三回合循环：首回合加法伤害 ×%.1f；次回合乘法伤害 ×%.1f；第三回合蓄力。\n蓄力攻击 ×%.2f；当回合分别以加法、乘法造成伤害可降至 ×%.2f。\n半血后，下次行动结束进入强化阶段。" % [MonsterRules.SWORD_OP_COEFF, MonsterRules.SWORD_OP_COEFF, MonsterRules.SWORD_CHARGE_MUL, MonsterRules.SWORD_INTERRUPT_MUL]
			var beat := ((battle.turn_index - 1) % 3) + 1
			state = "第 %d 阶段 · 循环 %d / 3" % [battle.sword_phase, beat]
			if battle.sword_phase_pending:
				state += " · 强化待生效"
			if beat == 3:
				state += "\n蓄力已打断" if battle.sword_positive_add and battle.sword_positive_mul else "\n加法 %s · 乘法 %s" % ["已命中" if battle.sword_positive_add else "未命中", "已命中" if battle.sword_positive_mul else "未命中"]
		_:
			summary = "普通攻击"
			detail = "回合结束后按已公布的意图行动。"
	return {"summary": summary, "detail": detail, "state": state, "tooltip": detail + ("\n\n" + state if state != "" else "")}
