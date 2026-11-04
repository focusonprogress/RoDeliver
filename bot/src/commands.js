import crypto from 'node:crypto';
import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  EmbedBuilder,
  MessageFlags,
  PermissionFlagsBits,
  SlashCommandBuilder,
} from 'discord.js';
import { config } from './config.js';
import { links } from './links.js';
import { rankFor } from './ranks.js';
import { getUserById, getUserByUsername } from './roblox.js';
import { clearRank, fullSync, syncMember } from './sync.js';

const VERIFY_BUTTON_ID = 'rodeliver:verify';
const VERIFY_TTL_MS = 15 * 60 * 1000;
const COLOR = 0x5865f2;

// Palavras simples: o filtro do Roblox costuma esconder números na descrição.
const WORDS = [
  'apple', 'banana', 'rocket', 'tiger', 'cloud', 'river', 'panda', 'pizza', 'planet', 'dragon',
  'forest', 'island', 'castle', 'guitar', 'orange', 'purple', 'silver', 'thunder', 'window', 'yellow',
  'candle', 'falcon', 'garden', 'jungle', 'lemon', 'mango', 'ocean', 'pepper', 'rabbit', 'shadow',
];

/** discordId -> { robloxId, robloxName, code, expires } */
const pending = new Map();

function makeCode() {
  return Array.from({ length: 5 }, () => WORDS[crypto.randomInt(WORDS.length)]).join(' ');
}

export const commandData = [
  new SlashCommandBuilder()
    .setName('verificar')
    .setDescription('Vincula sua conta do Roblox ao Discord')
    .addStringOption((o) => o.setName('usuario').setDescription('Seu nome de usuário no Roblox').setRequired(true)),
  new SlashCommandBuilder().setName('desvincular').setDescription('Remove o vínculo com a sua conta do Roblox'),
  new SlashCommandBuilder().setName('meurank').setDescription('Mostra sua conta vinculada e seu rank no jogo'),
  new SlashCommandBuilder()
    .setName('vincular')
    .setDescription('(Staff) Vincula um membro a uma conta do Roblox sem verificação')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addUserOption((o) => o.setName('membro').setDescription('Membro do Discord').setRequired(true))
    .addStringOption((o) => o.setName('usuario').setDescription('Usuário do Roblox').setRequired(true)),
  new SlashCommandBuilder()
    .setName('sincronizar')
    .setDescription('(Staff) Reenvia os ranks de todos os membros vinculados para o jogo')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
].map((c) => c.toJSON());

async function linkAndSync(guild, discordId, robloxUser) {
  links.set(discordId, { robloxId: robloxUser.id, robloxName: robloxUser.name, level: null });
  const member = await guild.members.fetch(discordId);
  return syncMember(member, { force: true });
}

async function handleVerify(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });

  const existing = links.get(interaction.user.id);
  if (existing) {
    return interaction.editReply(
      `Você já está vinculado a **${existing.robloxName}**. Use \`/desvincular\` antes se quiser trocar de conta.`,
    );
  }

  const user = await getUserByUsername(interaction.options.getString('usuario', true).trim());
  if (!user) return interaction.editReply('Não encontrei esse usuário no Roblox. Confere o nome.');

  const owner = links.findDiscordIdByRoblox(user.id);
  if (owner && owner !== interaction.user.id) {
    return interaction.editReply('Essa conta do Roblox já está vinculada a outro membro.');
  }

  const code = makeCode();
  pending.set(interaction.user.id, {
    robloxId: user.id,
    robloxName: user.name,
    code,
    expires: Date.now() + VERIFY_TTL_MS,
  });

  const embed = new EmbedBuilder()
    .setColor(COLOR)
    .setTitle('Verificação da conta do Roblox')
    .setDescription(
      [
        `Conta: **${user.displayName}** (@${user.name})`,
        '',
        '1. Abra seu perfil no Roblox e edite a **Descrição (About)**.',
        '2. Cole este código e salve:',
        `\`\`\`${code}\`\`\``,
        '3. Clique em **Já coloquei** aqui embaixo.',
        '',
        'Depois de verificar, pode apagar o código. Ele expira em 15 minutos.',
      ].join('\n'),
    );

  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId(VERIFY_BUTTON_ID).setLabel('Já coloquei').setStyle(ButtonStyle.Success),
  );

  return interaction.editReply({ embeds: [embed], components: [row] });
}

async function handleVerifyButton(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });

  const entry = pending.get(interaction.user.id);
  if (!entry || entry.expires < Date.now()) {
    pending.delete(interaction.user.id);
    return interaction.editReply('Sua verificação expirou ou não existe. Use `/verificar` de novo.');
  }

  const profile = await getUserById(entry.robloxId);
  const description = (profile?.description ?? '').toLowerCase();
  if (!description.includes(entry.code)) {
    return interaction.editReply(
      `Ainda não achei o código \`${entry.code}\` na sua descrição. Confere se salvou e tenta de novo em alguns segundos.`,
    );
  }

  const owner = links.findDiscordIdByRoblox(entry.robloxId);
  if (owner && owner !== interaction.user.id) {
    pending.delete(interaction.user.id);
    return interaction.editReply('Essa conta do Roblox já foi vinculada por outro membro.');
  }

  pending.delete(interaction.user.id);
  const rank = await linkAndSync(interaction.guild, interaction.user.id, { id: entry.robloxId, name: entry.robloxName });
  return interaction.editReply(
    `Pronto! Você está vinculado a **${entry.robloxName}**. Seu rank no jogo: **${rank.name}**.\nJá pode tirar o código da descrição.`,
  );
}

async function handleUnlink(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });
  const link = await clearRank(interaction.user.id, { unlink: true });
  if (!link) return interaction.editReply('Você não tem nenhuma conta vinculada.');
  return interaction.editReply(`Desvinculado de **${link.robloxName}**. Seu rank no jogo foi removido.`);
}

async function handleMyRank(interaction) {
  const link = links.get(interaction.user.id);
  if (!link) {
    return interaction.reply({
      content: 'Você ainda não vinculou sua conta. Use `/verificar`.',
      flags: MessageFlags.Ephemeral,
    });
  }
  const rank = rankFor(interaction.member);
  return interaction.reply({
    content: `Conta do Roblox: **${link.robloxName}** (ID ${link.robloxId})\nRank no jogo: **${rank.name}** (nível ${rank.level})`,
    flags: MessageFlags.Ephemeral,
  });
}

async function handleManualLink(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });
  const target = interaction.options.getUser('membro', true);

  const user = await getUserByUsername(interaction.options.getString('usuario', true).trim());
  if (!user) return interaction.editReply('Não encontrei esse usuário no Roblox.');

  const owner = links.findDiscordIdByRoblox(user.id);
  if (owner && owner !== target.id) {
    return interaction.editReply(`Essa conta do Roblox já está vinculada a <@${owner}>.`);
  }

  const previous = links.get(target.id);
  if (previous && previous.robloxId !== user.id) {
    await clearRank(target.id, { unlink: true });
  }

  const rank = await linkAndSync(interaction.guild, target.id, user);
  return interaction.editReply(`<@${target.id}> agora está vinculado a **${user.name}** com o rank **${rank.name}**.`);
}

async function handleSyncAll(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });
  const r = await fullSync(interaction.guild, { force: true });
  return interaction.editReply(
    `Sincronização concluída: ${r.synced} atualizados, ${r.removed} removidos (saíram do servidor), ${r.failed} com erro.`,
  );
}

const handlers = {
  verificar: handleVerify,
  desvincular: handleUnlink,
  meurank: handleMyRank,
  vincular: handleManualLink,
  sincronizar: handleSyncAll,
};

export async function handleInteraction(interaction) {
  let handler;
  if (interaction.isChatInputCommand()) handler = handlers[interaction.commandName];
  else if (interaction.isButton() && interaction.customId === VERIFY_BUTTON_ID) handler = handleVerifyButton;
  if (!handler) return;

  if (interaction.guildId !== config.guildId) {
    return interaction.reply({ content: 'Esse bot só funciona no servidor configurado.', flags: MessageFlags.Ephemeral });
  }

  try {
    await handler(interaction);
  } catch (err) {
    console.error(`[interaction] Erro em ${interaction.commandName ?? interaction.customId}:`, err);
    const message = 'Deu um erro aqui. Tenta de novo daqui a pouco; se continuar, chama a staff.';
    if (interaction.deferred || interaction.replied) await interaction.editReply({ content: message, embeds: [], components: [] }).catch(() => {});
    else await interaction.reply({ content: message, flags: MessageFlags.Ephemeral }).catch(() => {});
  }
}
