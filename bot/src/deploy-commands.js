import { REST, Routes } from 'discord.js';
import { config } from './config.js';
import { commandData } from './commands.js';

const rest = new REST().setToken(config.discordToken);
await rest.put(Routes.applicationGuildCommands(config.discordClientId, config.guildId), { body: commandData });
console.log(`${commandData.length} comandos registrados no servidor ${config.guildId}.`);
