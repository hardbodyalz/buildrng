--[[
	DefenseSim
	Pure, instance-free tower-defence simulation for ONE plot. The live
	DefenseService drives it at GameConfig.Defense.TickRate and replicates
	snapshots; OfflineService drives the exact same code headlessly with a
	coarse timestep to estimate offline results. Keeping it pure also makes it
	unit-testable outside Roblox (see tests/).

	Every structure behaviour is generic and driven by item data:
	  SingleTarget | Splash | Pierce | Chain | Aura | Trap | Support | Generator | Wall

	Coordinates are cell space (see Grid). Events are appended to self.Events and
	drained by the caller:
	  { k = "fx", kind, s = uid, ... }        visual only (skipped when NoFx)
	  { k = "kill", id, coins, xp, dice, boss, x, z }
	  { k = "coreHit", damage, hp }
	  { k = "coreDestroyed" }
	  { k = "destroyed", uid }
	  { k = "restored" }
	  { k = "bossPhase", name, text }
	  { k = "waveCleared", wave, bonus }
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Enemies = require(Shared.Config.Enemies)
local Waves = require(Shared.Config.Waves)
local Grid = require(Shared.Util.Grid)
local FlowField = require(Shared.Util.FlowField)
local ItemStats = require(Shared.Util.ItemStats)
local WaveGen = require(Shared.Util.WaveGen)

local DCFG = GameConfig.Defense
local ARMOR_MIN = DCFG.ArmorMinDamageFraction

local ATTACKING = {
	SingleTarget = true,
	Splash = true,
	Pierce = true,
	Chain = true,
	Aura = true,
	Trap = true,
}

local FLAG_ATTACKING = 128

local DefenseSim = {}
DefenseSim.__index = DefenseSim

export type Options = {
	Tier: number,
	Structures: { [string]: any },
	CoreMaxHealth: number,
	NoFx: boolean?,
}

function DefenseSim.new(opts: Options)
	local self = setmetatable({}, DefenseSim)
	self.Region = Grid.Region(opts.Tier)
	self.CoreMax = opts.CoreMaxHealth
	self.CoreHp = opts.CoreMaxHealth
	self.NoFx = opts.NoFx == true
	self.Structures = {} -- uid -> runtime structure
	self.StructureList = {} -- stable iteration order
	self.Occupancy = {} -- cellKey -> uid
	self.Enemies = {} -- array of runtime enemies
	self.NextEnemyId = 1
	self.Fields = {} -- costMult -> Field
	self.FieldVersion = 0
	self.Events = {}
	self.WaveActive = false
	self.Failed = false
	self.WaveNumber = 0
	self.Wave = nil
	self.SpawnIndex = 1
	self.WaveTime = 0
	self.Time = 0
	self:SetStructures(opts.Structures)
	return self
end

-- Structures -----------------------------------------------------------------

local function sameLayout(rt, s)
	return rt.Def.Id == s.Id and rt.Level == (s.Lvl or 1) and rt.Mut == (s.Mut or "Normal")
		and rt.X == s.X and rt.Z == s.Z and rt.R == (s.R or 0)
end

function DefenseSim:SetStructures(structures: { [string]: any })
	local newMap = {}
	local list = {}
	for uid, s in structures do
		local def = Items.Get(s.Id)
		if def then
			local old = self.Structures[uid]
			local rt
			if old and sameLayout(old, s) then
				rt = old
			else
				local stats = ItemStats.Compute(def, s.Lvl or 1, s.Mut)
				local w, d = Grid.Footprint(def, s.R or 0)
				local cx, cz = Grid.FootprintCenter(def, s.X, s.Z, s.R or 0)
				local maxHp = stats.Health or 1
				rt = {
					Uid = uid,
					Def = def,
					Level = s.Lvl or 1,
					Mut = s.Mut or "Normal",
					X = s.X,
					Z = s.Z,
					R = s.R or 0,
					W = w,
					D = d,
					Cx = cx,
					Cz = cz,
					Stats = stats,
					MaxHp = maxHp,
					Hp = maxHp,
					Alive = true,
					Blocks = def.Blocks,
					Attacks = ATTACKING[def.Behavior] == true,
					Cooldown = 0,
					BuffDmg = 0,
					BuffRate = 0,
				}
				-- Keep damage state if the same structure was merely upgraded.
				if old and old.Def.Id == s.Id and old.X == s.X and old.Z == s.Z and old.R == (s.R or 0) then
					rt.Alive = old.Alive
					rt.Hp = if old.Alive then math.min(maxHp, old.Hp / old.MaxHp * maxHp) else 0
				end
			end
			newMap[uid] = rt
			table.insert(list, rt)
		end
	end
	table.sort(list, function(a, b)
		return a.Uid < b.Uid
	end)
	self.Structures = newMap
	self.StructureList = list
	self:_rebuildOccupancy()
	self:_recomputeBuffs()
	self:_invalidateFields()
end

function DefenseSim:_rebuildOccupancy()
	local occ = {}
	for _, rt in self.StructureList do
		for dx = 0, rt.W - 1 do
			for dz = 0, rt.D - 1 do
				occ[Grid.Key(rt.X + dx, rt.Z + dz)] = rt.Uid
			end
		end
	end
	self.Occupancy = occ
end

function DefenseSim:_recomputeBuffs()
	local supports = {}
	for _, rt in self.StructureList do
		rt.BuffDmg, rt.BuffRate = 0, 0
		if rt.Def.Behavior == "Support" and rt.Alive then
			table.insert(supports, rt)
		end
	end
	for _, sup in supports do
		local range2 = sup.Stats.Range * sup.Stats.Range
		for _, rt in self.StructureList do
			if rt.Attacks and rt ~= sup then
				local dx, dz = rt.Cx - sup.Cx, rt.Cz - sup.Cz
				if dx * dx + dz * dz <= range2 then
					rt.BuffDmg += sup.Stats.BuffDamage or 0
					rt.BuffRate += sup.Stats.BuffRate or 0
				end
			end
		end
	end
end

function DefenseSim:_invalidateFields()
	self.Fields = {}
	self.FieldVersion += 1
end

function DefenseSim:GetField(costMult: number?)
	local mult = costMult or 1
	local field = self.Fields[mult]
	if not field then
		local blockers = {}
		for key, uid in self.Occupancy do
			local rt = self.Structures[uid]
			if rt.Blocks and rt.Alive then
				blockers[key] = rt.Hp
			end
		end
		field = FlowField.Compute(self.Region, blockers, DCFG.PathCostPerHp, mult)
		self.Fields[mult] = field
	end
	return field
end

function DefenseSim:_blockingAt(x: number, z: number)
	local uid = self.Occupancy[Grid.Key(x, z)]
	if uid then
		local rt = self.Structures[uid]
		if rt.Blocks and rt.Alive then
			return rt
		end
	end
	return nil
end

function DefenseSim:_destroyStructure(rt)
	rt.Alive = false
	rt.Hp = 0
	self:_push({ k = "destroyed", uid = rt.Uid })
	self:_recomputeBuffs()
	self:_invalidateFields()
end

function DefenseSim:RestoreStructures()
	for _, rt in self.StructureList do
		rt.Hp = rt.MaxHp
		rt.Alive = true
		rt.Cooldown = 0
	end
	self:_recomputeBuffs()
	self:_invalidateFields()
	self:_push({ k = "restored" })
end

-- Waves ------------------------------------------------------------------------

function DefenseSim:_push(ev)
	table.insert(self.Events, ev)
end

function DefenseSim:_fx(ev)
	if not self.NoFx then
		ev.k = "fx"
		table.insert(self.Events, ev)
	end
end

function DefenseSim:DrainEvents()
	local ev = self.Events
	self.Events = {}
	return ev
end

function DefenseSim:StartWave(n: number)
	self.WaveNumber = n
	self.Wave = WaveGen.Build(n)
	self.SpawnIndex = 1
	self.WaveTime = 0
	self.WaveActive = true
end

function DefenseSim:_modifierData(mods: number)
	local hpMult, rewardMult, speedMult, regen, armorAdd, structMult, scale = 1, 1, 1, 0, 0, 1, 1
	if mods ~= 0 then
		for _, m in Waves.Modifiers do
			if bit32.band(mods, m.Bit) ~= 0 then
				hpMult *= m.HealthMult or 1
				rewardMult *= m.RewardMult or 1
				speedMult *= m.SpeedMult or 1
				regen += m.Regen or 0
				armorAdd += m.ArmorAdd or 0
				structMult *= m.StructureDamageMult or 1
				scale *= m.Scale or 1
			end
		end
	end
	return hpMult, rewardMult, speedMult, regen, armorAdd, structMult, scale
end

function DefenseSim:SpawnEnemy(enemyId: string, mods: number, healthMult: number, atX: number?, atZ: number?)
	local def = Enemies.Get(enemyId)
	local wave = self.Wave
	local hpScale = if wave then wave.HealthScale else 1
	local rewardScale = if wave then wave.RewardScale else 1
	local hpMult, rewardMult, speedMult, regen, armorAdd, structMult = self:_modifierData(mods)
	local sx, sz = Grid.Entrance(self.Region)
	if atX and atZ then
		sx, sz = atX, atZ
	end
	local maxHp = def.Health * hpScale * healthMult * hpMult
	local e = {
		Id = self.NextEnemyId,
		Def = def,
		TypeIndex = def.Index,
		X = sx,
		Z = sz,
		Cx = sx,
		Cz = sz,
		Tx = nil,
		Tz = nil,
		Dx = 0,
		Dz = 1,
		Hp = maxHp,
		MaxHp = maxHp,
		Armor = def.Armor + armorAdd,
		Speed = def.Speed * speedMult,
		SpeedMult = 1,
		SlowResist = def.SlowResist,
		Regen = def.Regen + regen,
		StructMult = structMult,
		CostMult = def.PathCostMult,
		Reward = def.Reward * rewardScale * rewardMult,
		Xp = def.Xp,
		Dice = def.DiceReward,
		Mods = mods,
		State = "move",
		Target = nil,
		Slow = 0,
		IsBoss = def.IsBoss,
		Phase = 1,
		SummonTimer = 0,
		Summon = nil,
		FieldVersion = -1,
		Dead = false,
	}
	self.NextEnemyId += 1
	table.insert(self.Enemies, e)
	return e
end

function DefenseSim:_spawnDue()
	local wave = self.Wave
	if not wave then
		return
	end
	local spawns = wave.Spawns
	while self.SpawnIndex <= #spawns do
		local s = spawns[self.SpawnIndex]
		if s.T > self.WaveTime or #self.Enemies >= DCFG.MaxAliveEnemies then
			break
		end
		self:SpawnEnemy(s.Enemy, s.Mods, s.HealthMult)
		self.SpawnIndex += 1
	end
end

-- Combat ----------------------------------------------------------------------

function DefenseSim:_kill(e)
	if e.Dead then
		return
	end
	e.Dead = true
	self:_push({
		k = "kill",
		id = e.Id,
		enemy = e.Def.Id,
		coins = e.Reward,
		xp = e.Xp,
		dice = e.Dice,
		boss = e.IsBoss,
		x = e.X,
		z = e.Z,
	})
end

function DefenseSim:_damage(e, amount: number)
	if e.Dead then
		return
	end
	local dealt = math.max(amount - e.Armor, amount * ARMOR_MIN)
	e.Hp -= dealt
	if e.Hp <= 0 then
		self:_kill(e)
	end
end

-- Remaining path cost for "First" targeting.
function DefenseSim:_remaining(e, field)
	local d = field.Dist[Grid.Key(e.Cx, e.Cz)] or 9999
	return d
end

function DefenseSim:_selectTarget(rt, range: number, minRange: number?)
	local best, bestScore = nil, math.huge
	local r2 = range * range
	local min2 = if minRange then minRange * minRange else -1
	local mode = rt.Def.Targeting
	local field = if mode == "First" then self:GetField(1) else nil
	for _, e in self.Enemies do
		if not e.Dead then
			local dx, dz = e.X - rt.Cx, e.Z - rt.Cz
			local d2 = dx * dx + dz * dz
			if d2 <= r2 and d2 >= min2 then
				local score
				if mode == "Strongest" then
					score = -e.Hp
				elseif mode == "Closest" then
					score = d2
				else
					score = self:_remaining(e, field)
				end
				if score < bestScore then
					best, bestScore = e, score
				end
			end
		end
	end
	return best
end

function DefenseSim:_act(rt): boolean
	local stats = rt.Stats
	local behavior = rt.Def.Behavior
	local dmg = (stats.Damage or 0) * (1 + rt.BuffDmg)

	if behavior == "SingleTarget" then
		local t = self:_selectTarget(rt, stats.Range)
		if not t then
			return false
		end
		self:_fx({ kind = "shot", s = rt.Uid, x = t.X, z = t.Z })
		self:_damage(t, dmg)
		return true
	elseif behavior == "Splash" then
		local t = self:_selectTarget(rt, stats.Range, stats.MinRange)
		if not t then
			return false
		end
		local tx, tz = t.X, t.Z
		local r2 = stats.SplashRadius * stats.SplashRadius
		self:_fx({ kind = "splash", s = rt.Uid, x = tx, z = tz, r = stats.SplashRadius })
		for _, e in self.Enemies do
			if not e.Dead then
				local dx, dz = e.X - tx, e.Z - tz
				if dx * dx + dz * dz <= r2 then
					self:_damage(e, dmg)
				end
			end
		end
		return true
	elseif behavior == "Pierce" then
		local t = self:_selectTarget(rt, stats.Range)
		if not t then
			return false
		end
		local dx, dz = t.X - rt.Cx, t.Z - rt.Cz
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 then
			dx, dz, len = 0, 1, 1
		end
		dx, dz = dx / len, dz / len
		local width = stats.PierceWidth or 0.4
		for _, e in self.Enemies do
			if not e.Dead then
				local ex, ez = e.X - rt.Cx, e.Z - rt.Cz
				local along = ex * dx + ez * dz
				if along >= 0 and along <= stats.Range then
					local perp = math.abs(ex * dz - ez * dx)
					if perp <= width then
						self:_damage(e, dmg)
					end
				end
			end
		end
		self:_fx({ kind = "beam", s = rt.Uid, x = rt.Cx + dx * stats.Range, z = rt.Cz + dz * stats.Range })
		return true
	elseif behavior == "Chain" then
		local t = self:_selectTarget(rt, stats.Range)
		if not t then
			return false
		end
		local hit = { [t] = true }
		local points = { t.X, t.Z }
		local current = t
		local amount = dmg
		local chainR2 = (stats.ChainRange or 2) ^ 2
		for i = 1, stats.Chains or 1 do
			local cx, cz = current.X, current.Z
			self:_damage(current, amount)
			if i == (stats.Chains or 1) then
				break
			end
			amount *= stats.ChainFalloff or 1
			local nextE, bestD = nil, chainR2
			for _, e in self.Enemies do
				if not e.Dead and not hit[e] then
					local dx, dz = e.X - cx, e.Z - cz
					local d2 = dx * dx + dz * dz
					if d2 <= bestD then
						nextE, bestD = e, d2
					end
				end
			end
			if not nextE then
				break
			end
			hit[nextE] = true
			table.insert(points, nextE.X)
			table.insert(points, nextE.Z)
			current = nextE
		end
		self:_fx({ kind = "chain", s = rt.Uid, pts = points })
		return true
	elseif behavior == "Aura" then
		local r2 = stats.Range * stats.Range
		local any = false
		for _, e in self.Enemies do
			if not e.Dead then
				local dx, dz = e.X - rt.Cx, e.Z - rt.Cz
				if dx * dx + dz * dz <= r2 then
					any = true
					self:_damage(e, dmg)
				end
			end
		end
		if any then
			self:_fx({ kind = "pulse", s = rt.Uid, r = stats.Range })
		end
		return any
	elseif behavior == "Trap" then
		local hx, hz = rt.W / 2 + 0.1, rt.D / 2 + 0.1
		local any = false
		for _, e in self.Enemies do
			if not e.Dead and math.abs(e.X - rt.Cx) <= hx and math.abs(e.Z - rt.Cz) <= hz then
				any = true
				self:_damage(e, dmg)
			end
		end
		if any then
			self:_fx({ kind = "trap", s = rt.Uid })
		end
		return any
	end
	return false
end

function DefenseSim:_applyAuras()
	for _, e in self.Enemies do
		e.Slow = 0
	end
	for _, rt in self.StructureList do
		local slow = rt.Stats.Slow
		if slow and rt.Alive then
			local r2 = rt.Stats.Range * rt.Stats.Range
			for _, e in self.Enemies do
				local dx, dz = e.X - rt.Cx, e.Z - rt.Cz
				if dx * dx + dz * dz <= r2 then
					local s = slow * (1 - e.SlowResist)
					if s > e.Slow then
						e.Slow = s
					end
				end
			end
		end
	end
end

function DefenseSim:_structuresAct(dt: number)
	for _, rt in self.StructureList do
		if rt.Alive and rt.Attacks then
			local rate = (rt.Stats.Rate or 1) * (1 + rt.BuffRate)
			rt.Cooldown -= dt
			if rt.Cooldown <= 0 then
				if self:_act(rt) then
					rt.Cooldown += 1 / rate
					if rt.Cooldown < 0 then
						rt.Cooldown = 0
					end
				else
					rt.Cooldown = 0
				end
			end
		end
	end
end

-- Enemies ---------------------------------------------------------------------

function DefenseSim:_updateBoss(e, dt: number)
	local phases = e.Def.Phases
	if not phases then
		return
	end
	local frac = e.Hp / e.MaxHp
	local target = e.Phase
	for i = e.Phase + 1, #phases do
		if frac <= phases[i].HpBelow then
			target = i
		end
	end
	if target ~= e.Phase then
		e.Phase = target
		local p = phases[target]
		e.SpeedMult = p.SpeedMult or 1
		e.StructMult = p.StructureDamageMult or 1
		e.CostMult = p.PathCostMult or e.Def.PathCostMult
		e.Summon = p.Summon
		e.SummonTimer = 0
		e.FieldVersion = -1
		self:_push({ k = "bossPhase", name = p.Name, text = p.Announce, phase = target })
	end
	local summon = e.Summon
	if summon then
		e.SummonTimer -= dt
		if e.SummonTimer <= 0 then
			e.SummonTimer = summon.Interval
			for _ = 1, summon.Count do
				if #self.Enemies < DCFG.MaxAliveEnemies then
					self:SpawnEnemy(summon.Enemy, 0, 1, e.Cx, e.Cz)
				end
			end
		end
	end
end

function DefenseSim:_chooseNext(e)
	local field = self:GetField(e.CostMult)
	e.FieldVersion = self.FieldVersion
	local nx, nz = FlowField.NextCell(field, e.Cx, e.Cz, e.Dx, e.Dz)
	e.Tx, e.Tz = nx, nz
	if nx and nz then
		e.Dx, e.Dz = nx - e.Cx, nz - e.Cz
	end
end

function DefenseSim:_coreHit(e)
	e.Dead = true
	self.CoreHp = math.max(0, self.CoreHp - e.Def.CoreDamage)
	self:_push({ k = "coreHit", damage = e.Def.CoreDamage, hp = self.CoreHp })
	if self.CoreHp <= 0 and not self.Failed then
		self.Failed = true
		self.WaveActive = false
		self:_push({ k = "coreDestroyed" })
	end
end

function DefenseSim:_updateEnemy(e, dt: number)
	if e.Regen > 0 then
		e.Hp = math.min(e.MaxHp, e.Hp + e.MaxHp * e.Regen * dt)
	end
	if e.IsBoss then
		self:_updateBoss(e, dt)
	end

	if e.State == "attack" then
		local rt = self.Structures[e.Target]
		if not rt or not rt.Alive then
			e.State, e.Target = "move", nil
			self:_chooseNext(e)
		elseif e.FieldVersion ~= self.FieldVersion then
			-- The map changed (a wall fell elsewhere, player built something): maybe a detour is now cheaper.
			self:_chooseNext(e)
			if e.Tx and self.Occupancy[Grid.Key(e.Tx, e.Tz)] ~= rt.Uid then
				e.State, e.Target = "move", nil
			end
		end
		if e.State == "attack" then
			rt.Hp -= e.Def.StructureDps * e.StructMult * dt
			if rt.Hp <= 0 then
				self:_destroyStructure(rt)
				e.State, e.Target = "move", nil
			end
			return
		end
	end

	if not e.Tx then
		self:_chooseNext(e)
		if not e.Tx then
			return -- nowhere to go (shouldn't happen: Core is always reachable)
		end
	end

	local blocker = self:_blockingAt(e.Tx, e.Tz)
	if blocker then
		e.State, e.Target = "attack", blocker.Uid
		e.FieldVersion = self.FieldVersion
		return
	end

	local speed = e.Speed * e.SpeedMult * (1 - e.Slow)
	local step = speed * dt
	while step > 0 and e.Tx do
		local dx, dz = e.Tx - e.X, e.Tz - e.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		if step < dist then
			e.X += dx / dist * step
			e.Z += dz / dist * step
			step = 0
		else
			step -= dist
			e.X, e.Z = e.Tx, e.Tz
			e.Cx, e.Cz = e.Tx, e.Tz
			if Grid.IsCore(e.Cx, e.Cz) then
				self:_coreHit(e)
				return
			end
			self:_chooseNext(e)
			if e.Tx and self:_blockingAt(e.Tx, e.Tz) then
				break -- next tick switches to attacking
			end
		end
	end
end

-- Main step -------------------------------------------------------------------

function DefenseSim:Step(dt: number)
	self.Time += dt
	if self.WaveActive then
		self.WaveTime += dt
		self:_spawnDue()
	end

	self:_applyAuras()
	self:_structuresAct(dt)

	for _, e in self.Enemies do
		if not e.Dead then
			self:_updateEnemy(e, dt)
		end
		if self.Failed then
			break
		end
	end

	-- Compact dead enemies.
	local alive = {}
	for _, e in self.Enemies do
		if not e.Dead then
			table.insert(alive, e)
		end
	end
	self.Enemies = alive

	if self.WaveActive and not self.Failed and self.Wave and self.SpawnIndex > #self.Wave.Spawns and #alive == 0 then
		self:_waveCleared()
	end
end

function DefenseSim:_waveCleared()
	self.WaveActive = false
	local w = self.WaveNumber
	local bonus = Waves.ClearBonus(w)
	for _, rt in self.StructureList do
		if rt.Stats.CoinsPerWave then
			bonus += rt.Stats.CoinsPerWave
		end
	end
	self.CoreHp = math.min(self.CoreMax, self.CoreHp + self.CoreMax * DCFG.CoreRegenPerWave)
	self:RestoreStructures()
	self:_push({ k = "waveCleared", wave = w, bonus = math.floor(bonus) })
end

-- Clear all enemies, heal everything (end of a defence run).
function DefenseSim:Reset()
	self.Enemies = {}
	self.WaveActive = false
	self.Failed = false
	self.Wave = nil
	self.CoreHp = self.CoreMax
	self:RestoreStructures()
end

function DefenseSim:SetCoreMax(maxHp: number)
	local frac = self.CoreHp / self.CoreMax
	self.CoreMax = maxHp
	self.CoreHp = maxHp * frac
end

-- Flat snapshot for replication: per enemy {id, type, x*100, z*100, hp%, flags}.
DefenseSim.SnapshotStride = 6

function DefenseSim:Snapshot(): { number }
	local out = table.create(#self.Enemies * DefenseSim.SnapshotStride)
	for _, e in self.Enemies do
		local flags = e.Mods
		if e.State == "attack" then
			flags = bit32.bor(flags, FLAG_ATTACKING)
		end
		table.insert(out, e.Id)
		table.insert(out, e.TypeIndex)
		table.insert(out, math.floor(e.X * 100 + 0.5))
		table.insert(out, math.floor(e.Z * 100 + 0.5))
		table.insert(out, math.clamp(math.ceil(e.Hp / e.MaxHp * 100), 0, 100))
		table.insert(out, flags)
	end
	return out
end

function DefenseSim:BossInfo()
	for _, e in self.Enemies do
		if e.IsBoss then
			local phase = e.Def.Phases and e.Def.Phases[e.Phase]
			return {
				Id = e.Def.Id,
				Name = e.Def.DisplayName,
				Hp = e.Hp,
				MaxHp = e.MaxHp,
				Phase = e.Phase,
				PhaseName = phase and phase.Name or "",
			}
		end
	end
	return nil
end

DefenseSim.FLAG_ATTACKING = FLAG_ATTACKING

return DefenseSim
