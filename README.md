# RoDeliver Admin

Sistema de admin para Roblox em que os ranks do jogo vêm dos **cargos do Discord**.
A pessoa recebe o cargo `Moderator` no servidor e vira Moderador no jogo, automaticamente, inclusive com o jogo aberto.

```
Discord (cargo muda) ──► Bot RoDeliver ──► Roblox Open Cloud
                                              ├─ DataStore "RoDeliverRanks"   (o jogo lê quando o jogador entra)
                                              └─ MessagingService             (servidores abertos atualizam na hora)
```

## Como funciona

1. O membro usa `/verificar usuario:<nome no Roblox>`. O bot pede pra colocar um código de palavras na descrição do perfil do Roblox e confere.
2. A partir daí, sempre que os cargos dele mudarem, o bot grava o maior rank que ele tem no DataStore e avisa os servidores do jogo.
3. Se ele perder o cargo ou sair do servidor, o rank é removido.

## Ranks padrão

| Nível | Rank | Comandos |
|---|---|---|
| 1 | Helper | `cmds`, `rank`, `to` |
| 2 | Moderador | + `kick`, `kill`, `respawn`, `bring`, `tp`, `freeze`, `unfreeze`, `m` |
| 3 | Admin | + `speed`, `jump`, `god`, `ungod`, `ban`, `unban` |
| 4 | Head Admin | (mesmos do Admin, mas pode agir em Admins) |
| 5 | Dono | + `shutdown` |

Ninguém consegue usar comandos em alguém com rank igual ou maior. Os níveis de cada comando ficam em `Config.CommandLevels`.
Alvos aceitos: nome ou começo do nome, `me`/`eu`, `all`/`todos`, `others`/`outros`.

---

## 1. Roblox

1. No Studio, crie um **Script** chamado `RoDeliverAdmin` em `ServerScriptService` e cole o conteúdo de `roblox/RoDeliverAdmin.server.luau`.
2. Dentro dele, crie um **ModuleScript** chamado `Config` e cole o conteúdo de `roblox/Config.luau`.
3. Publique o jogo. Em *Game Settings → Security*, ative **Enable Studio Access to API Services** pra testar no Studio.
4. Pegue o **Universe ID**: no [Creator Dashboard](https://create.roblox.com/dashboard/creations), clique nos `...` da experiência → *Copy Universe ID*.

### Chave da Open Cloud

Em [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials) → *Create API Key*:

- **Access Permissions → Add API System:**
  - `messaging-service`: escolha a experiência → `universe-messaging-service:publish`
  - `universe-datastores`: escolha a experiência → `universe-datastores.objects:create`, `:update`, `:delete` e `:read`
- **Accepted IP Addresses:** o IP do servidor onde o bot vai rodar (ou `0.0.0.0/0` para qualquer IP)

## 2. Discord

1. Crie a aplicação em [discord.com/developers/applications](https://discord.com/developers/applications) → *Bot* → copie o token.
2. Em *Bot → Privileged Gateway Intents*, ative **Server Members Intent** (obrigatório, é por ele que o bot vê os cargos mudando).
3. Convide o bot com os escopos `bot` e `applications.commands`.
4. Ative o *Modo desenvolvedor* no Discord para copiar os IDs (clique direito → Copiar ID) do servidor e dos cargos.

## 3. Rodando o bot

Precisa de Node.js 18 ou mais novo.

```bash
cd bot
npm install
cp .env.example .env
cp config.example.json config.json
```

Preencha o `.env` (token, client ID, API key e Universe ID) e o `config.json` (ID do servidor e os IDs dos cargos de cada rank).
Você pode colocar mais de um cargo no mesmo rank, e quem tiver vários cargos fica com o rank mais alto.

```bash
npm run deploy
```

```bash
npm start
```

`npm run deploy` registra os comandos de barra (rode de novo se mudar os comandos).

### Comandos do bot

| Comando | Quem usa | O que faz |
|---|---|---|
| `/verificar usuario` | todos | Vincula a conta do Roblox (verificação pela descrição do perfil) |
| `/desvincular` | todos | Remove o vínculo e o rank |
| `/meurank` | todos | Mostra a conta vinculada e o rank |
| `/vincular membro usuario` | staff (Gerenciar Servidor) | Vincula alguém sem verificação |
| `/sincronizar` | staff (Gerenciar Servidor) | Reenvia os ranks de todo mundo para o jogo |

## Observações

- Os níveis do `config.json` do bot e do `Config.Ranks` do jogo precisam ser os mesmos. O nome exibido no jogo vem do `Config` do jogo.
- O dono do jogo (ou o dono do grupo) é sempre `Dono` no jogo. Use `Config.ManualRanks` para dar rank fixo a alguém sem depender do Discord.
- Os vínculos ficam em `bot/data/links.json`. Faça backup desse arquivo.
- O rank também fica nos atributos `AdminLevel` e `AdminRank` do jogador, pra usar em outros scripts (portas de staff, etc.).
