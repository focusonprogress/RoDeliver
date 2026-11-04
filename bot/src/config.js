import 'dotenv/config';
import fs from 'node:fs';

const REQUIRED_ENV = ['DISCORD_TOKEN', 'DISCORD_CLIENT_ID', 'ROBLOX_API_KEY', 'ROBLOX_UNIVERSE_ID'];
const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
if (missing.length) {
  throw new Error(`Faltam variáveis no .env: ${missing.join(', ')}`);
}

const configUrl = new URL('../config.json', import.meta.url);
if (!fs.existsSync(configUrl)) {
  throw new Error('Arquivo bot/config.json não encontrado. Copie o config.example.json e preencha.');
}
const file = JSON.parse(fs.readFileSync(configUrl, 'utf8'));

if (!file.guildId) throw new Error('config.json: "guildId" é obrigatório.');
if (!Array.isArray(file.ranks) || file.ranks.length === 0) {
  throw new Error('config.json: "ranks" precisa ter pelo menos um rank.');
}
for (const rank of file.ranks) {
  if (!Number.isInteger(rank.level) || rank.level < 1) {
    throw new Error(`config.json: rank "${rank.name}" precisa de um "level" inteiro >= 1.`);
  }
  if (!Array.isArray(rank.discordRoleIds)) {
    throw new Error(`config.json: rank "${rank.name}" precisa de "discordRoleIds" (lista).`);
  }
}

export const config = {
  discordToken: process.env.DISCORD_TOKEN,
  discordClientId: process.env.DISCORD_CLIENT_ID,
  robloxApiKey: process.env.ROBLOX_API_KEY,
  robloxUniverseId: process.env.ROBLOX_UNIVERSE_ID,
  dataStoreName: process.env.DATASTORE_NAME || 'RoDeliverRanks',
  messagingTopic: process.env.MESSAGING_TOPIC || 'RoDeliverRanks',
  guildId: file.guildId,
  syncOnStartup: file.syncOnStartup ?? true,
  defaultRankName: file.defaultRankName || 'Jogador',
  // Maior nível primeiro
  ranks: [...file.ranks].sort((a, b) => b.level - a.level),
};
