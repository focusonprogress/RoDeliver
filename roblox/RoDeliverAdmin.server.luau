-- RoDeliver Admin
-- Script em ServerScriptService. O ModuleScript "Config" fica dentro dele.
-- Os ranks vêm do Discord (bot RoDeliver) via DataStore + MessagingService.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local Debris = game:GetService("Debris")

local Config = require(script:WaitForChild("Config"))

local rankStore = DataStoreService:GetDataStore(Config.DataStoreName)
local banStore = DataStoreService:GetDataStore(Config.BanDataStoreName)

local discordLevels = {} -- [userId] = nível vindo do Discord
local baseLevels = {} -- [userId] = nível fixo (dono do jogo / ManualRanks)
local shuttingDown = false

----------------------------------------------------------------------
-- Ranks
----------------------------------------------------------------------

local function rankName(level)
	return Config.Ranks[level] or ("Nível " .. tostring(level))
end

local function getLevel(player)
	return math.max(baseLevels[player.UserId] or 0, discordLevels[player.UserId] or 0)
end

local function applyAttributes(player)
	-- Outros scripts do jogo podem ler: player:GetAttribute("AdminLevel")
	local level = getLevel(player)
	player:SetAttribute("AdminLevel", level)
	player:SetAttribute("AdminRank", rankName(level))
end

local function computeBaseLevel(player)
	local level = Config.ManualRanks[player.UserId] or 0
	if Config.GiveCreatorOwner then
		if game.CreatorType == Enum.CreatorType.User then
			if player.UserId == game.CreatorId then
				level = math.max(level, Config.OwnerLevel)
			end
		elseif game.CreatorType == Enum.CreatorType.Group then
			local ok, groupRank = pcall(player.GetRankInGroup, player, game.CreatorId)
			if ok and groupRank == 255 then
				level = math.max(level, Config.OwnerLevel)
			end
		end
	end
	return level
end

local function retry(fn, attempts)
	attempts = attempts or 3
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(i)
	end
	return false, lastErr
end

----------------------------------------------------------------------
-- Interface (aviso na tela, criado pelo servidor)
----------------------------------------------------------------------

local function notify(player, text, duration, richText)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local old = playerGui:FindFirstChild("RoDeliverNotice")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoDeliverNotice"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 70)
	label.Size = UDim2.new(0.6, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextWrapped = true
	label.RichText = richText == true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = label

	label.Parent = gui
	gui.Parent = playerGui
	Debris:AddItem(gui, duration or 5)
end

-- Todo texto digitado por alguém e mostrado para outros precisa passar no filtro
local function filterBroadcast(text, fromUserId)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	return nil
end

----------------------------------------------------------------------
-- Jogadores e alvos
----------------------------------------------------------------------

local function getHumanoid(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- "me"/"eu", "all"/"todos", "others"/"outros" ou começo do nome / display name
local function findTargets(caller, arg)
	if not arg or arg == "" then
		return nil, "Diga em quem usar o comando."
	end
	arg = string.lower(arg)

	if arg == "me" or arg == "eu" then
		return { caller }
	elseif arg == "all" or arg == "todos" then
		return Players:GetPlayers()
	elseif arg == "others" or arg == "outros" then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= caller then
				table.insert(list, p)
			end
		end
		return list
	end

	local matches = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local name = string.lower(p.Name)
		local display = string.lower(p.DisplayName)
		if name == arg or display == arg then
			return { p }
		end
		if string.sub(name, 1, #arg) == arg or string.sub(display, 1, #arg) == arg then
			table.insert(matches, p)
		end
	end

	if #matches == 1 then
		return matches
	elseif #matches > 1 then
		return nil, "Mais de um jogador com esse nome, escreva mais letras."
	end
	return nil, "Nenhum jogador encontrado com \"" .. arg .. "\"."
end

local function findOne(caller, arg)
	local list, err = findTargets(caller, arg)
	if not list then
		return nil, err
	end
	if #list ~= 1 then
		return nil, "Escolha só um jogador."
	end
	return list[1]
end

-- Só pode agir em si mesmo ou em quem tem rank menor
local function resolveTargets(caller, arg)
	local list, err = findTargets(caller, arg)
	if not list then
		return nil, err
	end
	local allowed, blocked = {}, 0
	local callerLevel = getLevel(caller)
	for _, target in ipairs(list) do
		if target == caller or callerLevel > getLevel(target) then
			table.insert(allowed, target)
		else
			blocked += 1
		end
	end
	if #allowed == 0 then
		if blocked > 0 then
			return nil, "Você não pode usar isso em alguém com rank igual ou maior que o seu."
		end
		return nil, "Nenhum jogador encontrado."
	end
	return allowed
end

local function names(list)
	local out = {}
	for _, p in ipairs(list) do
		table.insert(out, p.Name)
	end
	return table.concat(out, ", ")
end

local function rest(args, from)
	return table.concat(args, " ", from)
end

----------------------------------------------------------------------
-- Comandos
----------------------------------------------------------------------

local Commands = {}
local Aliases = {}

local function register(def)
	def.level = Config.CommandLevels[def.names[1]] or def.level or 1
	table.insert(Commands, def)
	for _, name in ipairs(def.names) do
		Aliases[name] = def
	end
end

-- Aplica uma ação em cada alvo permitido
local function forTargets(caller, arg, action, doneText)
	local targets, err = resolveTargets(caller, arg)
	if not targets then
		return err
	end
	for _, target in ipairs(targets) do
		action(target)
	end
	return doneText .. ": " .. names(targets)
end

register({
	names = { "cmds", "comandos", "help" },
	usage = "cmds",
	description = "Lista os comandos que você pode usar",
	run = function(caller)
		local level = getLevel(caller)
		local lines = { "<b>Comandos (" .. rankName(level) .. ")</b>" }
		for _, cmd in ipairs(Commands) do
			if level >= cmd.level then
				table.insert(lines, Config.Prefix .. cmd.usage .. "  -  " .. cmd.description)
			end
		end
		notify(caller, table.concat(lines, "\n"), 15, true)
		return nil
	end,
})

register({
	names = { "rank" },
	usage = "rank [jogador]",
	description = "Mostra o rank de alguém",
	run = function(caller, args)
		local target, err = findOne(caller, args[1] or "me")
		if not target then
			return err
		end
		local level = getLevel(target)
		return target.Name .. " é " .. rankName(level) .. " (nível " .. level .. ")"
	end,
})

register({
	names = { "kick" },
	usage = "kick [jogador] [motivo]",
	description = "Expulsa do servidor",
	run = function(caller, args)
		local reason = rest(args, 2)
		if reason ~= "" then
			reason = filterBroadcast(reason, caller.UserId) or "(motivo filtrado)"
		else
			reason = "Sem motivo"
		end
		return forTargets(caller, args[1], function(target)
			if target ~= caller then
				target:Kick("Expulso por " .. caller.Name .. ". Motivo: " .. reason)
			end
		end, "Expulsos")
	end,
})

register({
	names = { "ban" },
	usage = "ban [jogador] [motivo]",
	description = "Bane para sempre (todos os servidores)",
	run = function(caller, args)
		local targets, err = resolveTargets(caller, args[1])
		if not targets then
			return err
		end
		local reason = rest(args, 2)
		if reason ~= "" then
			reason = filterBroadcast(reason, caller.UserId) or "(motivo filtrado)"
		else
			reason = "Sem motivo"
		end
		local banned = {}
		for _, target in ipairs(targets) do
			if target ~= caller then
				local ok = retry(function()
					banStore:SetAsync(tostring(target.UserId), {
						reason = reason,
						by = caller.UserId,
						byName = caller.Name,
						at = os.time(),
					})
				end)
				if ok then
					target:Kick("Você foi banido por " .. caller.Name .. ". Motivo: " .. reason)
					table.insert(banned, target.Name)
				end
			end
		end
		if #banned == 0 then
			return "Ninguém foi banido."
		end
		return "Banidos: " .. table.concat(banned, ", ")
	end,
})

register({
	names = { "unban" },
	usage = "unban [usuário ou UserId]",
	description = "Remove o ban de alguém",
	run = function(caller, args)
		local input = args[1]
		if not input then
			return "Diga o nome ou o UserId."
		end
		local userId = tonumber(input)
		if not userId then
			local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, input)
			if not ok then
				return "Usuário não encontrado."
			end
			userId = id
		end
		local ok = retry(function()
			banStore:RemoveAsync(tostring(userId))
		end)
		return ok and ("Ban removido de " .. input) or "Falha ao remover o ban, tente de novo."
	end,
})

register({
	names = { "kill" },
	usage = "kill [jogador]",
	description = "Mata o personagem",
	run = function(caller, args)
		return forTargets(caller, args[1], function(target)
			local hum = getHumanoid(target)
			if hum then
				hum.Health = 0
			end
		end, "Mortos")
	end,
})

register({
	names = { "respawn", "re" },
	usage = "respawn [jogador]",
	description = "Faz renascer",
	run = function(caller, args)
		return forTargets(caller, args[1] or "me", function(target)
			target:LoadCharacter()
		end, "Renascidos")
	end,
})

local function teleport(list, destination)
	local destRoot = getRoot(destination)
	if not destRoot then
		return false
	end
	for i, p in ipairs(list) do
		local root = getRoot(p)
		if root and p ~= destination then
			root.CFrame = destRoot.CFrame * CFrame.new(0, 0, -(2 + i * 2))
		end
	end
	return true
end

register({
	names = { "to", "goto" },
	usage = "to [jogador]",
	description = "Vai até alguém",
	run = function(caller, args)
		local target, err = findOne(caller, args[1])
		if not target then
			return err
		end
		return teleport({ caller }, target) and ("Teleportado até " .. target.Name) or "O jogador não tem personagem."
	end,
})

register({
	names = { "bring" },
	usage = "bring [jogador]",
	description = "Traz alguém até você",
	run = function(caller, args)
		local targets, err = resolveTargets(caller, args[1])
		if not targets then
			return err
		end
		return teleport(targets, caller) and ("Trazidos: " .. names(targets)) or "Você não tem personagem."
	end,
})

register({
	names = { "tp" },
	usage = "tp [jogador] [destino]",
	description = "Teleporta alguém até outro jogador",
	run = function(caller, args)
		local targets, err = resolveTargets(caller, args[1])
		if not targets then
			return err
		end
		local destination, err2 = findOne(caller, args[2])
		if not destination then
			return err2
		end
		return teleport(targets, destination) and ("Teleportados até " .. destination.Name) or "O destino não tem personagem."
	end,
})

register({
	names = { "freeze" },
	usage = "freeze [jogador]",
	description = "Congela",
	run = function(caller, args)
		return forTargets(caller, args[1], function(target)
			local root = getRoot(target)
			if root then
				root.Anchored = true
			end
		end, "Congelados")
	end,
})

register({
	names = { "unfreeze", "thaw" },
	usage = "unfreeze [jogador]",
	description = "Descongela",
	run = function(caller, args)
		return forTargets(caller, args[1], function(target)
			local root = getRoot(target)
			if root then
				root.Anchored = false
			end
		end, "Descongelados")
	end,
})

register({
	names = { "speed", "ws" },
	usage = "speed [jogador] [valor]",
	description = "Muda a velocidade (padrão 16)",
	run = function(caller, args)
		local value = math.clamp(tonumber(args[2]) or 16, 0, 500)
		return forTargets(caller, args[1], function(target)
			local hum = getHumanoid(target)
			if hum then
				hum.WalkSpeed = value
			end
		end, "Velocidade " .. value)
	end,
})

register({
	names = { "jump", "jp" },
	usage = "jump [jogador] [valor]",
	description = "Muda a força do pulo (padrão 50)",
	run = function(caller, args)
		local value = math.clamp(tonumber(args[2]) or 50, 0, 1000)
		return forTargets(caller, args[1], function(target)
			local hum = getHumanoid(target)
			if hum then
				hum.UseJumpPower = true
				hum.JumpPower = value
			end
		end, "Pulo " .. value)
	end,
})

register({
	names = { "god" },
	usage = "god [jogador]",
	description = "Vida infinita",
	run = function(caller, args)
		return forTargets(caller, args[1] or "me", function(target)
			local hum = getHumanoid(target)
			if hum then
				hum.MaxHealth = math.huge
				hum.Health = math.huge
			end
		end, "God")
	end,
})

register({
	names = { "ungod" },
	usage = "ungod [jogador]",
	description = "Tira a vida infinita",
	run = function(caller, args)
		return forTargets(caller, args[1] or "me", function(target)
			local hum = getHumanoid(target)
			if hum then
				hum.MaxHealth = 100
				hum.Health = 100
			end
		end, "Ungod")
	end,
})

register({
	names = { "m", "anuncio", "announce" },
	usage = "m [mensagem]",
	description = "Anúncio para o servidor",
	run = function(caller, args)
		local text = rest(args, 1)
		if text == "" then
			return "Escreva a mensagem."
		end
		local filtered = filterBroadcast(text, caller.UserId)
		if not filtered then
			return "Não foi possível filtrar a mensagem, tente de novo."
		end
		for _, p in ipairs(Players:GetPlayers()) do
			notify(p, "[" .. rankName(getLevel(caller)) .. "] " .. caller.DisplayName .. ": " .. filtered, 8)
		end
		return nil
	end,
})

register({
	names = { "shutdown" },
	usage = "shutdown",
	description = "Fecha o servidor",
	run = function(caller)
		shuttingDown = true
		for _, p in ipairs(Players:GetPlayers()) do
			p:Kick("Servidor fechado por " .. caller.Name .. ".")
		end
		return nil
	end,
})

local function onChatted(player, message)
	local prefix = Config.Prefix
	if string.sub(message, 1, #prefix) ~= prefix then
		return
	end

	local args = {}
	for word in string.gmatch(string.sub(message, #prefix + 1), "%S+") do
		table.insert(args, word)
	end
	local name = table.remove(args, 1)
	if not name then
		return
	end

	local cmd = Aliases[string.lower(name)]
	if not cmd then
		return
	end

	local level = getLevel(player)
	if level < cmd.level then
		if level > 0 then
			notify(player, "Esse comando é para " .. rankName(cmd.level) .. " ou acima.")
		end
		return
	end

	local ok, result = pcall(cmd.run, player, args)
	if not ok then
		warn("[RoDeliver] Erro no comando " .. name .. ": " .. tostring(result))
		notify(player, "Erro ao executar o comando.")
	elseif type(result) == "string" then
		notify(player, result)
	end
end

----------------------------------------------------------------------
-- Entrada/saída de jogadores
----------------------------------------------------------------------

local function onPlayerAdded(player)
	if shuttingDown then
		player:Kick("Servidor fechando.")
		return
	end

	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)

	local okBan, ban = retry(function()
		return banStore:GetAsync(tostring(player.UserId))
	end)
	if okBan and type(ban) == "table" then
		player:Kick("Você está banido deste jogo. Motivo: " .. tostring(ban.reason or "Sem motivo"))
		return
	end

	baseLevels[player.UserId] = computeBaseLevel(player)

	local okRank, data = retry(function()
		return rankStore:GetAsync(tostring(player.UserId))
	end)
	if okRank then
		-- Se chegou uma atualização ao vivo enquanto carregava, ela vale mais
		if discordLevels[player.UserId] == nil then
			discordLevels[player.UserId] = (type(data) == "table" and tonumber(data.level)) or 0
		end
	else
		warn("[RoDeliver] Falha ao carregar rank de " .. player.Name .. ": " .. tostring(data))
	end

	if player.Parent == nil then
		return
	end
	applyAttributes(player)

	local level = getLevel(player)
	if level > 0 then
		task.delay(3, function()
			if player.Parent then
				notify(player, "Seu rank: " .. rankName(level) .. ". Digite " .. Config.Prefix .. "cmds para ver os comandos.", 6)
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	discordLevels[player.UserId] = nil
	baseLevels[player.UserId] = nil
end)

----------------------------------------------------------------------
-- Atualização ao vivo vinda do bot (cargo mudou no Discord)
----------------------------------------------------------------------

local function onRankMessage(message)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, message.Data)
	if not ok or type(data) ~= "table" then
		return
	end
	local userId = tonumber(data.userId)
	if not userId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end

	local before = getLevel(player)
	discordLevels[userId] = tonumber(data.level) or 0
	applyAttributes(player)
	local after = getLevel(player)

	if after ~= before then
		notify(player, "Seu rank mudou para " .. rankName(after) .. ".", 6)
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(function()
			return MessagingService:SubscribeAsync(Config.MessagingTopic, onRankMessage)
		end)
		if ok then
			break
		end
		warn("[RoDeliver] Falha ao assinar MessagingService, tentando de novo: " .. tostring(err))
		task.wait(10)
	end
end)

print("[RoDeliver] Admin carregado.")
