--[[
	Remotes
	Single source of truth for remote names. The server creates them under
	ReplicatedStorage.Remotes; the client waits for them. Every client->server
	call is a RemoteFunction returning { ok = bool, err = string?, ... } and is
	rate-limited + validated server-side (see server/Util/Net).
]]

return {
	-- client -> server requests (RemoteFunction). Value = rate-limit bucket.
	Functions = {
		GetInitialState = "Default",
		Roll = "Roll",
		PlaceStructure = "Place",
		MoveStructure = "Place",
		StoreStructure = "Place",
		UpgradeStructure = "Purchase",
		SetItemFlag = "Default",
		SellItems = "Sell",
		MassSell = "Sell",
		StartDefense = "Defense",
		StopDefense = "Defense",
		BuyUpgrade = "Purchase",
		BuyExpansion = "Purchase",
		TutorialAdvance = "Default",
	},
	-- server -> client pushes (RemoteEvent)
	Events = {
		"Sync", -- partial profile/derived state
		"Notify", -- toast { Text, Kind }
		"Announce", -- server-wide rare roll banner
		"DefenseState", -- per-plot defence status
		"DefenseEvents", -- batched combat events (fx, kills, phases)
		"EnemySnapshot", -- per-plot enemy positions (10 Hz)
		"OfflineReport",
	},
}
