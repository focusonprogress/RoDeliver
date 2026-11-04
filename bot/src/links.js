import fs from 'node:fs';

// Guarda os vínculos Discord -> Roblox:
// { [discordId]: { robloxId, robloxName, level } }
const DIR = new URL('../data/', import.meta.url);
const FILE = new URL('links.json', DIR);
const TMP = new URL('links.json.tmp', DIR);

let data = {};
try {
  data = JSON.parse(fs.readFileSync(FILE, 'utf8'));
} catch (err) {
  if (err.code !== 'ENOENT') throw err;
}

function save() {
  fs.mkdirSync(DIR, { recursive: true });
  fs.writeFileSync(TMP, JSON.stringify(data, null, 2));
  fs.renameSync(TMP, FILE);
}

export const links = {
  get(discordId) {
    return data[discordId] ?? null;
  },
  set(discordId, value) {
    data[discordId] = value;
    save();
  },
  delete(discordId) {
    delete data[discordId];
    save();
  },
  entries() {
    return Object.entries(data);
  },
  findDiscordIdByRoblox(robloxId) {
    return Object.keys(data).find((id) => data[id].robloxId === robloxId) ?? null;
  },
};
