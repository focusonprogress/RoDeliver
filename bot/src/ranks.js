import { config } from './config.js';

export const NO_RANK = Object.freeze({ level: 0, name: config.defaultRankName });

/** Retorna o maior rank que o membro tem pelos cargos do Discord. */
export function rankFor(member) {
  for (const rank of config.ranks) {
    if (rank.discordRoleIds.some((id) => member.roles.cache.has(id))) {
      return { level: rank.level, name: rank.name };
    }
  }
  return NO_RANK;
}

export function rankName(level) {
  return config.ranks.find((r) => r.level === level)?.name ?? config.defaultRankName;
}
