-- RoDeliver Admin - Configuração
-- ModuleScript chamado "Config", DENTRO do Script RoDeliverAdmin (ServerScriptService)

return {
	-- Precisam ser iguais ao DATASTORE_NAME / MESSAGING_TOPIC do .env do bot
	DataStoreName = "RoDeliverRanks",
	MessagingTopic = "RoDeliverRanks",
	BanDataStoreName = "RoDeliverBans",

	-- Prefixo dos comandos no chat. Ex: ;kick fulano
	Prefix = ";",

	-- Nome de cada nível. Os níveis precisam bater com o config.json do bot.
	Ranks = {
		[0] = "Jogador",
		[1] = "Helper",
		[2] = "Moderador",
		[3] = "Admin",
		[4] = "Head Admin",
		[5] = "Dono",
	},

	-- O dono do jogo (ou o dono do grupo, rank 255) ganha este nível automaticamente
	GiveCreatorOwner = true,
	OwnerLevel = 5,

	-- Ranks fixos que não dependem do Discord: [UserId] = nível
	ManualRanks = {
		-- [123456789] = 5,
	},

	-- Nível mínimo de cada comando (dá pra mudar à vontade)
	CommandLevels = {
		cmds = 1,
		rank = 1,
		to = 1,
		kick = 2,
		kill = 2,
		respawn = 2,
		bring = 2,
		tp = 2,
		freeze = 2,
		unfreeze = 2,
		m = 2,
		speed = 3,
		jump = 3,
		god = 3,
		ungod = 3,
		ban = 3,
		unban = 3,
		shutdown = 5,
	},
}
