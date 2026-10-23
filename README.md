# Kelwin Souls

Jogo de ação inspirado em Dark Souls, feito com Babylon.js (JavaScript puro, sem bundler).

## Rodar

```bash
python -m http.server 8123
```

Abra http://localhost:8123 e clique na tela para começar.

## Controles

- WASD mover, Shift correr, Espaço rolar
- Botão esquerdo ataque leve (combo: vertical → horizontal → diagonal), botão direito ataque pesado, F defender
- Q fixar alvo, R Estus, E interagir, L subir de nível (na fogueira)
- Setas giram a câmera, Esc solta o mouse

## Recursos

Arena do chefe no salão de um castelo, cutscene de introdução e de morte do chefe, fogueiras, sistema de almas e níveis.

## Animações

Os ciclos de andar, correr, o rolamento e os cortes horizontal/diagonal do cavaleiro são gerados no Blender
pelo script `tools/blender/knight_anims.py`, que acrescenta os clipes à ação "Take 001" de `assets/knight.glb`:

```bash
blender -b --factory-startup --python tools/blender/knight_anims.py -- assets/knight.glb assets/knight.glb
```

O salão do chefe (`assets/castle_hall.glb`) e a grade de colisão (`assets/castle_hall_grid.json`) saem do
modelo original do castelo pelo script `tools/blender/castle_hall.py`:

```bash
blender -b --factory-startup --python tools/blender/castle_hall.py -- complete_medieval_tiled_castle_interior.glb assets/castle_hall.glb assets/castle_hall_grid.json
```

## Créditos

- Chefe: ["Tillagemon Boss Skeleton"](https://sketchfab.com/3d-models/tillagemon-boss-skeleton-5c83cdeb86404e63900c1d04f8b391fb)
  por [Vasian-Digital3D](https://sketchfab.com/Vasian-Digital3D), licença
  [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) (`assets/boss.glb`, sem alterações).
- Salão do chefe: ["Complete Medieval Tiled Castle Interior"](https://sketchfab.com/3d-models/complete-medieval-tiled-castle-interior-7c41daa4d30544279b13286402491da8)
  por [Teranox](https://sketchfab.com/Teranox1), licença [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/)
  (`assets/castle_hall.glb` usa só o salão principal, reposicionado).
