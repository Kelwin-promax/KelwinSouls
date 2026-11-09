# KelwinSouls

Souls-like de mundo aberto inspirado em **Dark Souls** (o ciclo da Chama, as fogueiras, a perda de almas ao morrer) e em **Elden Ring** (a Árvore gigante, as Grandes Runas/semideuses, o mapa aberto com Graças e viagem rápida).

Feito com **Godot 4.7 (GDScript)** para o jogo e **Python** para todo o pipeline de conteúdo (modelos, mundo, sons e texturas).

## Lore: As Terras de Kelwin

No princípio havia a névoa, e nela ardia a **Brasa Primordial**. Dela brotou a **Árvore de Brasa**, e em seu coração foi forjado o **Anel de Kelwin**, a lei que dá forma à vida, à morte e ao fogo.

Quando a chama começou a minguar, o Rei Kelwin despedaçou o Anel. Os fragmentos, as **Grandes Brasas**, foram tomados por seus herdeiros semideuses, que enlouqueceram e guerrearam até restarem só cinzas.

Você é um **Maculado das Cinzas**, morto e chamado de volta pela Graça. Reúna as Grandes Brasas, atravesse os portões da **Cidadela de Marfim**, derrote **Ivorae, a Rainha sem Rosto**, e decida o destino da Chama:

| Final | Requisito |
|---|---|
| **Era do Ouro**: reacender a Chama (ciclo de Dark Souls) | derrotar Ivorae |
| **Era das Cinzas**: deixar a Chama se apagar | derrotar Ivorae |
| **Era do Maculado**: fundir as Brasas em si mesmo | derrotar Ivorae com 5 Grandes Brasas |

### Regiões (mapa de 8 km × 8 km)

| Região | Chefes / destaques |
|---|---|
| Vale das Brasas Caídas (início) | O Cavaleiro Sagrado (chefe de campo), capela em ruínas |
| Ossuário de Ghelm | **Osskaroth**, Golem Lápide |
| Pântano dos Espinhos | **Morvessa**, Rainha Gastaroide, Zarakhul |
| Cidadela de Marfim | Aurencast (portão), **Ivorae** (exige 2 Grandes Brasas), Árvore de Brasa |
| A Grande Fornalha (vulcão) | **Rhaum**, Vormak, Titã Infernal, dragão Kelvhar |
| Abismo de Obsidiana | **Nexmora** |
| Picos do Véu Gélido | **Veltharion**, Dragão Ancestral |
| Pagode Carmesim | **Zhenkar** |

Os chefes em **negrito** dão Grandes Brasas. Cada chefe derrotado também dá +1 Lágrima Ígnea (cura).

## Controles

| Ação | Teclado/Mouse | Controle Xbox |
|---|---|---|
| Mover / câmera | WASD / mouse | analógicos |
| Ataque leve (combo 3) | botão esquerdo | RB |
| Ataque pesado | Ctrl + botão esquerdo | RT |
| Defender | botão direito | LB |
| Rolar (toque) / correr (segurar) | Espaço (Shift também corre) | B |
| Pular | F | Y |
| Travar mira / trocar alvo | Q ou botão do meio / roda | R3 |
| Beber Lágrima Ígnea | R | X |
| Interagir / Graça | E | A |
| Mapa / Pausa | M / Esc | Back / Start |

## Como rodar

1. Abra o Godot 4.7 e importe `game/project.godot`, ou rode:
   ```
   Godot_v4.7.2-stable_win64.exe --path game
   ```
2. Na primeira abertura o Godot importa os modelos, o que leva alguns minutos.

## Pipeline de conteúdo (Python)

```
python tools/asset_pipeline.py      # otimiza os 25 .glb da raiz → game/assets/models (usa Godot headless)
python tools/gen_world.py [semente] # heightmap 8x8 km, biomas, estradas, chefes, inimigos, props, mapa
python tools/gen_audio.py           # sintetiza todos os sons e músicas (sem direitos autorais)
python tools/gen_textures.py        # texturas procedurais tileáveis (terreno, pedra, marfim, madeira...)
```

* **Modelos**: o Python funde os pedaços de malha, solda vértices, remove UVs extras, centraliza, reescala para a altura de `tools/catalog.py` e reduz as texturas. Em seguida o Godot (meshoptimizer) simplifica de 0,3 a 3,1 milhões para cerca de 35 a 75 mil triângulos, e o Godot gera LODs extras na importação.
* **Catálogo**: `tools/catalog.py` define nome, papel (jogador/chefe/elite/inimigo), região e altura de cada modelo.

## Arquitetura (game/)

```
scripts/core/game.gd        estado global, atributos, save/load, controles
scripts/core/sfx.gd         sons 2D/3D, música com crossfade
scripts/main.gd             ciclo de jogo, streaming de inimigos/chefes, morte, Graças, finais
scripts/world/terrain.gd    terreno com streaming (pedaços de 256 m, 4 LODs, colisão perto do jogador)
scripts/world/props.gd      árvores/rochas procedurais via MultiMesh
scripts/world/structures.gd ruínas, cemitérios, santuários, cidadela, pagode, Árvore de Brasa
scripts/world/grace.gd      Graças (checkpoint, subir de nível, viagem rápida)
scripts/actors/player.gd    jogador: combos, pesado, rolamento com i-frames, defesa, cura, pulo
scripts/actors/enemy.gd     IA por estados com ataques telegrafados e postura (stagger)
scripts/actors/boss.gd      arena com névoa, fase 2, Grande Brasa
scripts/actors/dragon.gd    dragão terrestre (animações reais) e dragão voador (rasantes de fogo)
scripts/actors/model_rig.gd animação procedural para modelos sem esqueleto
shaders/terrain.gdshader    deslocamento por heightmap + splatting de 8 camadas
```

## Etapas

- [x] **Etapa 1: base jogável.** Pipeline de assets, mundo de 8 km, 8 regiões, 13 chefes e 2 dragões, cerca de 195 inimigos, combate souls, Graças, morte com perda de Brasas, subir de nível, viagem rápida, mapa, 3 finais, sons e músicas.
- [ ] **Etapa 2: animação real.** Rigging dos humanoides (Blender + Rigify, ou Mixamo) e animações de ataque, andar e morrer.
- [ ] **Etapa 3: arte do mundo.** Props modelados no Blender (castelo, pontes, catedral), texturas CC0 (Poly Haven/ambientCG), grama e vegetação densa.
- [ ] **Etapa 4: profundidade.** Armas e equipamentos, magias/FP, NPCs com diálogos (Irmã Vesper), montaria, masmorras.
- [ ] **Etapa 5: polimento.** Ciclo dia/noite, clima, cutscenes de chefe, menus de inventário, exportação .exe.

## Observações

* `drogon_-_dragon_game_of_thrones.glb` é um asset de **Game of Thrones (HBO)**. Pode ser usado num projeto pessoal, mas **não pode ser distribuído** nem publicado. Para lançar o jogo, troque esse modelo.
* Todos os sons, músicas e texturas são gerados proceduralmente pelos scripts Python, então não têm direitos autorais de terceiros.
