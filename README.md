# Abissal

Jogo de terror aquático em primeira pessoa, feito com Babylon.js (JavaScript puro, sem bundler).
Tudo é gerado por código: terreno, naufrágio, criatura e som.

Você é um mergulhador em um vale submarino. Recupere as 3 caixas de registro e volte ao cabo do barco antes que
o oxigênio acabe e antes que a criatura encontre você.

## Rodar

```bash
python -m http.server 8123
```

Abra http://localhost:8123 e clique na tela para mergulhar. Use fones: o som faz parte do jogo.

## Controles

- WASD nadar, mouse olhar, Espaço subir, Ctrl ou C descer, Shift nadar rápido
- F lanterna, Q sonar, G sinalizador, E interagir, Esc solta o mouse

## Como funciona

- A criatura percebe a lanterna, a pressa e o sonar. Com a luz apagada, ela só nota você de muito perto.
- Dentro do naufrágio o metal abafa tudo, e ela não passa pelas portas estreitas.
- De tempos em tempos ela fareja mais ou menos onde você está, então ficar parado não resolve.
- Um sinalizador atrai a criatura por alguns segundos.
- Uma mordida rasga o traje, tira vida e oxigênio; depois ela se afasta. A segunda mata.
- Ao pegar a última caixa, ela vem atrás de você até o cabo.

Os ajustes ficam no `CONFIG`, no início de `game.js`.
