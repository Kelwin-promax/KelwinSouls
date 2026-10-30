# Kelwin Souls

Jogo de caça ao monstro inspirado em Dark Souls, feito com Babylon.js (JavaScript puro, sem bundler).
Você caça o monstro e ele caça você. Mate o monstro para vencer; perca as 3 vidas e ele vence.

## Rodar

```bash
python -m http.server 8123
```

Abra http://localhost:8123 e clique na tela para começar.

## Controles

- WASD mover, Shift correr, Espaço rolar
- Botão esquerdo ataque leve (combo: vertical → horizontal → diagonal), botão direito ataque pesado, F defender
- Q fixar alvo, R Estus, E descansar na fogueira
- Setas giram a câmera, Esc solta o mouse

## A caçada

- Você começa no sul da floresta morta e o monstro no norte, e ele sai atrás de você. Ele fareja sua posição aproximada, ouve quando você corre, rola ou luta e vê você se tiver linha livre à frente dele.
- Para achá-lo, siga as pegadas em brasa no chão e a bússola no topo da tela, que aponta para o último rugido.
- Atacar antes de ele notar você é uma emboscada: 2,5x de dano e ele cambaleia.
- Com 66% e 33% de vida ele foge para longe e se recupera um pouco; depois da primeira fuga fica mais rápido e agressivo.
- Cada fogueira recupera tudo uma única vez, mas se apaga e atrai o monstro. Ao morrer, você volta à última fogueira usada.

Os ajustes ficam em `CONFIG.hunt`, no início de `game.js`.

## Animações

Os ciclos de andar, correr, o rolamento e os cortes horizontal/diagonal do cavaleiro são gerados no Blender
pelo script `tools/blender/knight_anims.py`, que acrescenta os clipes à ação "Take 001" de `assets/knight.glb`:

```bash
blender -b --factory-startup --python tools/blender/knight_anims.py -- assets/knight.glb assets/knight.glb
```

A floresta (`assets/forest.glb`) e a grade do mapa (`assets/forest_grid.json`, com troncos e altura do chão) saem do
escaneamento original pelo script `tools/blender/forest.py`:

```bash
blender -b --factory-startup --python tools/blender/forest.py -- forrest.glb assets/forest.glb assets/forest_grid.json
```

O salão do castelo não é usado no momento. O arquivo continua em `assets/castle_hall.glb` e sai do modelo original
pelo script `tools/blender/castle_hall.py`:

```bash
blender -b --factory-startup --python tools/blender/castle_hall.py -- complete_medieval_tiled_castle_interior.glb assets/castle_hall.glb assets/castle_hall_grid.json
```

## Créditos

- Monstro: ["Tillagemon Boss Skeleton"](https://sketchfab.com/3d-models/tillagemon-boss-skeleton-5c83cdeb86404e63900c1d04f8b391fb)
  por [Vasian-Digital3D](https://sketchfab.com/Vasian-Digital3D), licença
  [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) (`assets/boss.glb`, sem alterações).
- Floresta: ["Forrest"](https://sketchfab.com/3d-models/forrest-5d2a49ef06e4435c8634218db6ca9afc)
  por [kampsolutions](https://sketchfab.com/kampsolutions), licença [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/)
  (`assets/forest.glb` foi nivelada, reescalada e simplificada).
- Salão do castelo (não usado no momento): ["Complete Medieval Tiled Castle Interior"](https://sketchfab.com/3d-models/complete-medieval-tiled-castle-interior-7c41daa4d30544279b13286402491da8)
  por [Teranox](https://sketchfab.com/Teranox1), licença [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/)
  (`assets/castle_hall.glb` usa só o salão principal, reposicionado).
