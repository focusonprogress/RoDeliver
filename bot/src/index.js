import { Client, Events, GatewayIntentBits, Partials } from 'discord.js';
import { config } from './config.js';
import { handleInteraction } from './commands.js';
import { links } from './links.js';
import { clearRank, fullSync, syncMember } from './sync.js';

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers],
  partials: [Partials.GuildMember],
});

client.once(Events.ClientReady, async (c) => {
  console.log(`Online como ${c.user.tag}`);
  if (!config.syncOnStartup) return;
  try {
    const guild = await c.guilds.fetch(config.guildId);
    const r = await fullSync(guild, { force: true });
    console.log(`[sync] Inicial: ${r.synced} atualizados, ${r.removed} removidos, ${r.failed} com erro.`);
  } catch (err) {
    console.error('[sync] Falha na sincronização inicial:', err);
  }
});

// Cargo adicionado/removido -> atualiza o rank no jogo
client.on(Events.GuildMemberUpdate, async (oldMember, newMember) => {
  if (newMember.guild.id !== config.guildId) return;
  if (!oldMember.partial && oldMember.roles.cache.equals(newMember.roles.cache)) return;
  try {
    const before = links.get(newMember.id)?.level;
    const rank = await syncMember(newMember);
    if (rank && rank.level !== before) {
      console.log(`[sync] ${newMember.user.tag} -> ${rank.name} (nível ${rank.level})`);
    }
  } catch (err) {
    console.error(`[sync] Falha ao atualizar ${newMember.id}:`, err.message);
  }
});

// Saiu do servidor -> perde o rank (o vínculo fica guardado caso volte)
client.on(Events.GuildMemberRemove, async (member) => {
  if (member.guild.id !== config.guildId) return;
  try {
    const link = await clearRank(member.id);
    if (link) console.log(`[sync] ${member.id} saiu do servidor; rank de ${link.robloxName} removido.`);
  } catch (err) {
    console.error(`[sync] Falha ao remover rank de ${member.id}:`, err.message);
  }
});

client.on(Events.InteractionCreate, handleInteraction);

process.on('unhandledRejection', (err) => console.error('[erro]', err));

client.login(config.discordToken);
