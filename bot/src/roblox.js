import crypto from 'node:crypto';
import { config } from './config.js';

const OPEN_CLOUD = 'https://apis.roblox.com';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function request(url, { method = 'GET', body, auth = false, md5 = false, okStatuses = [] } = {}) {
  for (let attempt = 1; ; attempt++) {
    const headers = {};
    let payload;
    if (auth) headers['x-api-key'] = config.robloxApiKey;
    if (body !== undefined) {
      payload = JSON.stringify(body);
      headers['content-type'] = 'application/json';
      if (md5) headers['content-md5'] = crypto.createHash('md5').update(payload).digest('base64');
    }

    const res = await fetch(url, { method, headers, body: payload });
    const text = await res.text();

    if (res.ok || okStatuses.includes(res.status)) {
      let parsed = null;
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = text;
      }
      return { status: res.status, data: parsed };
    }

    if ((res.status === 429 || res.status >= 500) && attempt < 4) {
      const retryAfter = Number(res.headers.get('retry-after'));
      await sleep(retryAfter > 0 ? retryAfter * 1000 : attempt * 2000);
      continue;
    }

    throw new Error(`Roblox ${method} ${url.split('?')[0]} -> ${res.status}: ${text.slice(0, 300)}`);
  }
}

function entryUrl(robloxId) {
  const params = new URLSearchParams({
    datastoreName: config.dataStoreName,
    entryKey: String(robloxId),
  });
  return `${OPEN_CLOUD}/datastores/v1/universes/${config.robloxUniverseId}/standard-datastores/datastore/entries/entry?${params}`;
}

/** Salva o rank no DataStore (o jogo lê quando o jogador entra). */
export async function setRankEntry(robloxId, value) {
  await request(entryUrl(robloxId), { method: 'POST', body: value, auth: true, md5: true });
}

/** Remove o rank do DataStore. */
export async function deleteRankEntry(robloxId) {
  await request(entryUrl(robloxId), { method: 'DELETE', auth: true, okStatuses: [404] });
}

/** Avisa os servidores abertos do jogo, na hora, que o rank mudou. */
export async function publishRankUpdate(payload) {
  const url = `${OPEN_CLOUD}/messaging-service/v1/universes/${config.robloxUniverseId}/topics/${encodeURIComponent(config.messagingTopic)}`;
  await request(url, { method: 'POST', body: { message: JSON.stringify(payload) }, auth: true });
}

/** Busca um usuário do Roblox pelo nome. Retorna { id, name, displayName } ou null. */
export async function getUserByUsername(username) {
  const { data } = await request('https://users.roblox.com/v1/usernames/users', {
    method: 'POST',
    body: { usernames: [username], excludeBannedUsers: true },
  });
  return data?.data?.[0] ?? null;
}

/** Busca o perfil (inclui a descrição) de um usuário do Roblox. */
export async function getUserById(robloxId) {
  const { status, data } = await request(`https://users.roblox.com/v1/users/${robloxId}`, { okStatuses: [404] });
  return status === 404 ? null : data;
}
