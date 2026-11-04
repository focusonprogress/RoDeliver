import { links } from './links.js';
import { NO_RANK, rankFor } from './ranks.js';
import { deleteRankEntry, publishRankUpdate, setRankEntry } from './roblox.js';

// Todas as escritas no Roblox passam por esta fila, uma por vez,
// pra não estourar o limite da API e não ter corrida entre mudanças de cargo.
let queue = Promise.resolve();
function enqueue(task) {
  const result = queue.then(task);
  queue = result.catch(() => {});
  return result;
}

async function writeRank(robloxId, rank, discordId) {
  if (rank.level > 0) {
    await setRankEntry(robloxId, {
      level: rank.level,
      rank: rank.name,
      discordId,
      updatedAt: new Date().toISOString(),
    });
  } else {
    await deleteRankEntry(robloxId);
  }
  await publishRankUpdate({ userId: robloxId, level: rank.level, rank: rank.name });
}

async function syncMemberNow(member, { force = false } = {}) {
  const link = links.get(member.id);
  if (!link) return null;
  // Usa a versão mais nova do membro em cache, se existir
  const current = member.guild.members.cache.get(member.id) ?? member;
  const rank = rankFor(current);
  if (!force && link.level === rank.level) return rank;
  await writeRank(link.robloxId, rank, member.id);
  links.set(member.id, { ...link, level: rank.level });
  return rank;
}

async function clearNow(discordId, { unlink }) {
  const link = links.get(discordId);
  if (!link) return null;
  await writeRank(link.robloxId, NO_RANK, discordId);
  if (unlink) links.delete(discordId);
  else links.set(discordId, { ...link, level: 0 });
  return link;
}

/** Envia o rank atual de um membro vinculado para o jogo. */
export function syncMember(member, options) {
  return enqueue(() => syncMemberNow(member, options));
}

/** Tira o rank no jogo. Com unlink=true também apaga o vínculo. */
export function clearRank(discordId, { unlink = false } = {}) {
  return enqueue(() => clearNow(discordId, { unlink }));
}

/** Ressincroniza todos os vínculos com o estado atual do servidor. */
export function fullSync(guild, { force = false } = {}) {
  return enqueue(async () => {
    const members = await guild.members.fetch();
    const result = { synced: 0, removed: 0, failed: 0 };
    for (const [discordId, link] of links.entries()) {
      try {
        const member = members.get(discordId);
        if (member) {
          await syncMemberNow(member, { force });
          result.synced++;
        } else if (force || link.level !== 0) {
          await clearNow(discordId, { unlink: false });
          result.removed++;
        }
      } catch (err) {
        result.failed++;
        console.error(`[sync] Falha ao sincronizar ${discordId}:`, err.message);
      }
    }
    return result;
  });
}
