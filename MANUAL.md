# mri_Qstorerobbery — Manual

Assalto a lojas de conveniência: quebre a registradora, vasculhe o escritório atrás da senha do cofre e esvazie o cofre antes que a polícia chegue.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Permissões (ACE)](#permissões-ace)
4. [Configuração](#configuração)
5. [Lojas](#lojas)
6. [Comandos](#comandos)
7. [Fluxo do assalto](#fluxo-do-assalto)
8. [Itens](#itens)
9. [Integrações](#integrações)
10. [Entrypoints para outros recursos](#entrypoints-para-outros-recursos)
11. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `ox_lib` | Sim | Zonas, callbacks, `progressCircle`, `inputDialog`, `alertDialog`, context menu, `addCommand` |
| `oxmysql` | Sim | Carregado no `fxmanifest`; usado para gravar o cofre em `stashitems` quando o inventário é `qb` |
| `mri_Qminigames` | Sim | Minigames `MineSweep` (registradora), `OpenTerminal` (computador) e `MemoryCard` (hack do alarme) |
| `qb-core` | Sim (ou ESX) | Bridge de framework — ver observação abaixo |
| `es_extended` | Sim (ou QB) | Bridge de framework — ver observação abaixo |
| `ox_inventory` | Não | Se `Config.Inventory = "ox"` (padrão): cofre como stash temporário e hook anti-transferência |
| `ox_target` / `qb-target` | Sim | Alvos do hack, do vasculhar e da registradora (`Config.Target`) |
| `ps-dispatch` | Não | Alerta de assalto à polícia, se o recurso estiver iniciado |

> **Framework:** `bridge/shared.lua` detecta `ox_core`, `qb-core` ou `es_extended`, nessa ordem de prioridade. Porém só existem as pastas `bridge/qb/` e `bridge/esx/` — **não há bridge para `ox_core`**. Em um servidor com `ox_core` iniciado, o recurso aborta com "Unable to find framework bridge for 'ox'". Use QBCore/QBox ou ESX.

---

## Instalação

1. Copie a pasta `mri_Qstorerobbery` para `resources/`.
2. Adicione ao `server.cfg`:
   ```
   ensure mri_Qstorerobbery
   ```
3. Cadastre os itens usados pelo recurso no seu inventário (ver [Itens](#itens)): `trojan_usb`, `stickynote`, e as recompensas `black_money` e `goldbar`.
4. Ajuste `Config.Inventory` e `Config.Target` para o que você usa.
5. Com `Config.Inventory = "qb"`, o cofre é gravado na tabela `stashitems` — a mesma do `qb-inventory`. Não há SQL próprio a importar.

---

## Permissões (ACE)

O comando `/get-store-config` é registrado via `lib.addCommand` com `restricted = 'group.admin'`. O `ox_lib` cria a ACE `command.get-store-config` e a concede ao grupo indicado — basta o jogador pertencer a `group.admin`.

O comando `/liberar` **não** usa ACE: ele checa o job do jogador diretamente e só aceita `police`.

---

## Configuração

Arquivo: `config.lua`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `Config.MinPolice` | number | Sim | Policiais online mínimos para assaltar. `0` libera sempre. A contagem vem do evento `police:SetCopCount` |
| `Config.Inventory` | string | Sim | `ox` ou `qb`. Define como o cofre é criado e como os itens são entregues |
| `Config.Target` | string | Sim | `ox` ou `qb`. Define qual recurso de target registra as zonas |
| `Config.Debug` | bool | Sim | Desenha as box zones do `ox_target` |
| `Config.RegisterSearchTime` | number (ms) | Sim | Duração da barra de progresso antes do minigame da registradora |
| `Config.HackItem` | string | Sim | Item exigido para hackear o alarme e para usar o computador. Padrão: `trojan_usb` |
| `Config.Prize.min` / `.max` | number | Sim | Faixa de valor sorteado por registradora. O servidor derruba o jogador (`DropPlayer`) se o valor recebido passar de `max` |
| `Config.Prize.item` | string | Sim | Item pago pela registradora. Se não existir no inventário, paga em dinheiro (`cash`) |
| `Config.Prize.safe` | tabela | Sim | Loot do cofre. Uma entrada por item, com `min`, `max` e `chance` |
| `Config.Store` | tabela | Sim | Lista de lojas — ver abaixo |

### Estrutura de uma loja em `Config.Store`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `coords` | vector3 | Sim | Centro da loja. As zonas só são criadas quando o jogador chega a 20 m |
| `registar` | tabela | Sim | Registradoras. Cada entrada tem `robbed` (bool inicial) e `coords` (vector4) |
| `search` | tabela | Sim | Pontos de busca da senha. Cada entrada tem `coords`, `size`, `rotation` e, opcionalmente, `iscomputer = true` |
| `safe` | tabela | Sim | Cofre: `coords` (vector3/vector4) |
| `hack` | tabela | Não | Painel de alarme: `hacked`, `coords`, `size`, `rotation`. Lojas sem `hack` não permitem atrasar o alerta |

A configuração de fábrica traz 10 lojas; 5 delas (IDs 1, 2, 3, 5 e 8) têm painel de alarme hackeável.

---

## Lojas

As lojas são identificadas pelo índice numérico em `Config.Store` (1 a 10 de fábrica). O estado de cada loja (`alerted`, `cooldown`, `combination`, registradoras roubadas, pontos já vasculhados, cofre aberto) vive na memória do servidor e é replicado para os clients via `ran-storerobbery:client:setStoreConfig`.

Depois que a polícia libera a loja com `/liberar`, ela entra em **cooldown de 1 hora**; ao fim do prazo o estado é resetado automaticamente. Uma loja alertada mas nunca liberada também é resetada 1 hora após o alerta.

---

## Comandos

| Comando | Permissão | Descrição |
|---|---|---|
| `/liberar` | Job `police` | Libera a loja em que o policial está: pede confirmação, encerra o assalto e coloca a loja em cooldown de 1 hora |
| `/get-store-config` | `group.admin` | Abre um menu com todas as lojas (ID, se tem hack, nº de registradoras, se está roubada) e teleporta o admin para a loja escolhida |

---

## Fluxo do assalto

1. **(Opcional) Hackear o alarme** — em lojas com `hack`, use o `trojan_usb` no painel para rodar o minigame `MemoryCard`. O sucesso atrasa o acionamento da polícia em 60 a 90 segundos (valor sorteado e informado ao jogador).
2. **Registradoras** — quebre o prop `prop_till_01` (vida abaixo de 1000) e use o target "Roubar Caixa". Roda uma barra de progresso de `Config.RegisterSearchTime` e depois o minigame `MineSweep`. O valor obtido é pago em `Config.Prize.item` (ou dinheiro). Cada registradora só pode ser roubada uma vez por ciclo.
3. **Alerta** — a polícia é notificada quando o jogador danifica um `prop_till_01` ou começa a vasculhar o escritório. Com o alarme hackeado, o alerta sai apenas depois do atraso.
4. **Vasculhar** — os pontos de `search` sem `iscomputer` têm ~10% de chance de entregar a combinação (em um `stickynote` com metadata). O ponto com `iscomputer = true` exige que **todos** os outros pontos já tenham sido vasculhados, pede o `trojan_usb`, roda o minigame `OpenTerminal` e tem ~80% de chance de decodificar a senha após 20 a 30 segundos de espera.
5. **Cofre** — aproxime-se do cofre e pressione **E**. Se ainda estiver trancado, abre o prompt de PIN (4 dígitos). Com o PIN correto, o cofre é aberto e populado pelo sorteio de `Config.Prize.safe`. A partir daí, **E** abre o stash.

---

## Itens

| Item | Papel |
|---|---|
| `trojan_usb` | Exigido no target do painel de alarme e no computador do escritório (valor de `Config.HackItem`) |
| `stickynote` | Entregue com a combinação na metadata quando um ponto de busca comum dá certo. É um item usável: usar mostra o PIN |
| `black_money` | Recompensa padrão das registradoras (`Config.Prize.item`) e do cofre |
| `goldbar` | Loot do cofre com 20% de peso no sorteio |

Se `Config.Prize.item` não existir no inventário, a registradora paga em dinheiro (`cash`).

---

## Integrações

### ox_inventory

Com `Config.Inventory = "ox"`, o cofre é um stash temporário (`CreateTemporaryStash`, 10 slots) criado no momento em que o PIN é aceito. O recurso também registra um hook `swapItems` que **bloqueia depositar itens do jogador dentro dos stashes temporários** (`^temp-[%w]+`), impedindo o uso do cofre como armazenamento. O hook é removido no `onResourceStop`.

Com o inventário QB, o cofre vira um stash com ID aleatório gravado na tabela `stashitems`.

### ps-dispatch

Se o `ps-dispatch` estiver iniciado, o alerta chama `exports['ps-dispatch']:StoreRobbery()`. Sem ele, o jogador ainda recebe a notificação "As autoridades foram alertadas!", mas nenhum alerta é enviado à polícia.

### mri_Qminigames

Três minigames são chamados por export, e são obrigatórios para o fluxo funcionar:

```lua
exports['mri_Qminigames']:MineSweep(prize, 10, 3, "left")  -- registradora
exports['mri_Qminigames']:OpenTerminal()                   -- computador do escritório
exports['mri_Qminigames']:MemoryCard()                     -- hack do painel de alarme
```

### Logs por Discord webhook

`server.lua` tem uma função `SendLog` que monta um embed de Discord para início do assalto, prêmio obtido e fim do assalto. A variável `webhook` **não é atribuída em nenhum lugar do código** — na prática os logs não são enviados e o console imprime o aviso "No webhook link for mri_Qstorerobbery". Para habilitar, atribua a URL do webhook a essa variável no topo do `server.lua`.

---

## Entrypoints para outros recursos

### Evento `police:SetCopCount` (client)

O recurso escuta este evento (emitido pelo `qb-policejob`) para saber quantos policiais estão online e comparar com `Config.MinPolice`.

```lua
TriggerClientEvent('police:SetCopCount', src, amount)
```

### Callback `ran-storerobbery:client:resetStore`

Pergunta ao client em qual loja ele está e pede confirmação para liberar. Retorna o ID da loja ou `false`. É o que o `/liberar` usa.

```lua
local storeId = lib.callback.await('ran-storerobbery:client:resetStore', source)
```

### Evento `ran-storerobbery:server:getConfig`

Faz o servidor reenviar a tabela completa de lojas para o client que chamou.

```lua
TriggerServerEvent('ran-storerobbery:server:getConfig')
```

### Evento `ran-storerobbery:client:setStoreConfig`

Broadcast do servidor com o estado atualizado de uma loja: `(storeId, storeConfig)`.

---

## Estrutura de arquivos

```
mri_Qstorerobbery/
├── client.lua           — zonas por proximidade, registradoras, busca da senha, cofre, alerta, menus de admin
├── server.lua           — estado das lojas, prêmios, geração do PIN, cofre, cooldown, comandos, logs
├── config.lua           — MinPolice, inventário, target, prêmios e as 10 lojas
├── bridge/
│   ├── shared.lua       — detecção do framework
│   ├── client.lua       — carrega bridge/<framework>/client.lua
│   ├── server.lua       — carrega bridge/<framework>/server.lua
│   ├── qb/              — client.lua e server.lua (notify, itens, stash, job)
│   └── esx/             — client.lua e server.lua
├── locales/
│   └── en.json          — arquivo vazio; o recurso não usa ox_lib locale (strings estão fixas no código)
└── fxmanifest.lua
```
