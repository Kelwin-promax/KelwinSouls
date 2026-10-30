'use strict';
/* ======================================================================
   KELWIN SOULS — caça ao monstro em Babylon.js
   Mexa no CONFIG abaixo para criar suas próprias alterações.
   ====================================================================== */

const CONFIG = {
  player: {
    maxHp: 100, maxStamina: 100, estusMax: 3, estusHeal: 55,
    walk: 4.2, sprint: 7.2, roll: 8.5,
    // ataque leve encadeia: vertical -> horizontal -> diagonal (arc = meia abertura do golpe, em radianos)
    light:  { windup: 0.18, active: 0.12, recover: 0.30, stamina: 14, dmg: 22, range: 2.9, arc: 1.0, clip: 'vertical' },
    sweep:  { windup: 0.20, active: 0.14, recover: 0.32, stamina: 16, dmg: 20, range: 3.0, arc: 1.7, clip: 'sweep' },
    diag:   { windup: 0.22, active: 0.13, recover: 0.36, stamina: 18, dmg: 27, range: 3.0, arc: 1.25, clip: 'diag' },
    heavy:  { windup: 0.50, active: 0.15, recover: 0.55, stamina: 30, dmg: 50, range: 3.3, arc: 1.0, clip: 'vertical' },
    combo: ['light', 'sweep', 'diag'],
  },
  // a caçada: você persegue o monstro e ele persegue você
  hunt: {
    lives: 3,               // mortes permitidas antes de o monstro vencer
    ambushMult: 2.5,        // dano ao atacar o monstro antes de ele notar você
    sight: 26, sightArc: 70,                         // alcance (m) e meia abertura (graus) da visão do monstro
    noise: { sprint: 28, fight: 18, roll: 14, walk: 8 },   // de quantos metros ele ouve cada ação
    scentEvery: 11, scentErr: [20, 6],               // de quanto em quanto tempo fareja você e o erro (m) da pista: começa grande e diminui
    roarEvery: [18, 30],                             // intervalo entre rugidos: é a sua pista de onde ele está
    fleeAt: [0.66, 0.33],                            // fração da vida em que ele foge para se recuperar
    lurkTime: 9, lurkHeal: 0.05,                     // tempo escondido e vida recuperada (fração)
    trackLife: 60,                                   // segundos até uma pegada sumir
  },
  enemies: {
    boss: {
      name: 'Monstro das Cinzas', hp: 900, speed: 4.4, huntSpeed: 2.1, alertSpeed: 3.6, fleeSpeed: 6.4, scale: 2.5, boss: true, stopDist: 4.2,
      look: { tint: [1.0, 0.45, 0.4], skin: [0.35, 0.3, 0.28], armor: [0.2, 0.08, 0.08], eye: [1, 0.15, 0.1], weapon: 1.6, horns: true },
      // anim = clipe do boss.glb; hit = [fim da preparação, fim do golpe] em fração do clipe
      attacks: [
        { kind: 'melee', windup: 0.6, active: 0.2, recover: 1.0, range: 5.0, arc: 70,  dmg: 38, maxD: 5.5, anim: 'Attack_Base_03', hit: [0.25, 0.38] },
        { kind: 'melee', windup: 0.6, active: 0.2, recover: 1.0, range: 5.0, arc: 140, dmg: 34, maxD: 5.5, anim: 'Attack_Base_01', hit: [0.28, 0.42] },
        { kind: 'aoe',   windup: 1.0, active: 0.2, recover: 1.3, radius: 6.0, reach: 4.0, dmg: 55, maxD: 5.5, anim: 'Attack_Base_02', hit: [0.25, 0.35] },
        { kind: 'leap',  windup: 1.0, active: 0.5, recover: 1.1, radius: 4.5, dmg: 50, minD: 9, maxD: 18, anim: 'Attack_Base_09', hit: [0.3, 0.47] },
      ],
    },
  },
};

/* ------------------------------ utilidades ------------------------------ */
const V3 = BABYLON.Vector3, C3 = BABYLON.Color3;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const easeOut = t => 1 - (1 - t) * (1 - t);
function angDiff(a, b) { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; }
function turnToward(cur, target, step) { return cur + clamp(angDiff(cur, target), -step, step); }
function mulberry(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const rnd = mulberry(1337);
const $ = id => document.getElementById(id);

/* ------------------------------ engine/cena ------------------------------ */
const canvas = $('c');
const engine = new BABYLON.Engine(canvas, true, { stencil: true });
const scene = new BABYLON.Scene(engine);
scene.clearColor = new BABYLON.Color4(0.04, 0.05, 0.07, 1);
scene.fogMode = BABYLON.Scene.FOGMODE_EXP2;
scene.fogDensity = 0.03;
scene.fogColor = new C3(0.07, 0.08, 0.11);

const camera = new BABYLON.FreeCamera('cam', new V3(0, 4, -8), scene);
camera.minZ = 0.1; camera.maxZ = 300; camera.fov = 0.95;

const hemi = new BABYLON.HemisphericLight('hemi', new V3(0, 1, 0), scene);
hemi.intensity = 0.55; hemi.diffuse = new C3(0.55, 0.6, 0.8); hemi.groundColor = new C3(0.12, 0.12, 0.16);
const moon = new BABYLON.DirectionalLight('moon', new V3(-0.5, -1, 0.4), scene);
moon.intensity = 0.7; moon.diffuse = new C3(0.6, 0.7, 1);
moon.autoUpdateExtends = false;
moon.orthoLeft = -32; moon.orthoRight = 32; moon.orthoTop = 32; moon.orthoBottom = -32;
moon.shadowMinZ = 1; moon.shadowMaxZ = 120;
const sg = new BABYLON.ShadowGenerator(2048, moon);
sg.useBlurExponentialShadowMap = true; sg.blurKernel = 12; sg.setDarkness(0.35);
const glow = new BABYLON.GlowLayer('glow', scene); glow.intensity = 0.6;

// pós-processamento: bloom leve, vinheta, tonemapping e FXAA
const pipe = new BABYLON.DefaultRenderingPipeline('pipe', true, scene, [camera]);
pipe.fxaaEnabled = true; pipe.bloomEnabled = true; pipe.bloomThreshold = 0.85; pipe.bloomWeight = 0.25; pipe.bloomKernel = 48;
pipe.imageProcessingEnabled = true; pipe.imageProcessing.toneMappingEnabled = true; pipe.imageProcessing.contrast = 1.25; pipe.imageProcessing.exposure = 1.1;
pipe.imageProcessing.vignetteEnabled = true; pipe.imageProcessing.vignetteWeight = 2.2; pipe.imageProcessing.vignetteColor = new BABYLON.Color4(0, 0, 0, 0);

// céu noturno: gradiente, estrelas e lua
{
  const sky = BABYLON.MeshBuilder.CreateSphere('sky', { diameter: 500, segments: 16 }, scene);
  const t = new BABYLON.DynamicTexture('skyT', { width: 1024, height: 512 }, scene, true), c = t.getContext();
  const g = c.createLinearGradient(0, 0, 0, 512);
  g.addColorStop(0, '#05070f'); g.addColorStop(0.45, '#0b1020'); g.addColorStop(0.5, '#141b2c'); g.addColorStop(1, '#0d1018');
  c.fillStyle = g; c.fillRect(0, 0, 1024, 512);
  for (let i = 0; i < 700; i++) { const y = Math.random() * 250, a = 0.3 + Math.random() * 0.7; c.fillStyle = `rgba(220,230,255,${a})`; c.fillRect(Math.random() * 1024, y, Math.random() < 0.1 ? 2 : 1, Math.random() < 0.1 ? 2 : 1); }
  const mg = c.createRadialGradient(700, 130, 0, 700, 130, 90); mg.addColorStop(0, 'rgba(200,215,255,0.35)'); mg.addColorStop(1, 'rgba(200,215,255,0)');
  c.fillStyle = mg; c.fillRect(560, 0, 280, 280);
  c.fillStyle = '#dfe7ff'; c.beginPath(); c.arc(700, 130, 22, 0, 7); c.fill();
  t.update();
  const sm = new BABYLON.StandardMaterial('skyM', scene);
  sm.backFaceCulling = false; sm.disableLighting = true; sm.emissiveTexture = t; sm.fogEnabled = false; sm.diffuseColor = C3.Black(); sm.specularColor = C3.Black();
  sky.material = sm; sky.infiniteDistance = true; sky.isPickable = false; sky.applyFog = false;
}

function mat(c, emissive) {
  const m = new BABYLON.StandardMaterial('m', scene);
  m.maxSimultaneousLights = 8;
  m.diffuseColor = new C3(c[0], c[1], c[2]); m.specularColor = new C3(0.06, 0.06, 0.06);
  if (emissive) m.emissiveColor = new C3(emissive[0], emissive[1], emissive[2]);
  return m;
}
function shadowCast(node) { node.getChildMeshes().forEach(m => sg.addShadowCaster(m)); }

const flareTex = (() => {
  const t = new BABYLON.DynamicTexture('flare', 64, scene, true), c = t.getContext();
  const g = c.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  c.fillStyle = g; c.fillRect(0, 0, 64, 64); t.update(); t.hasAlpha = true; return t;
})();

// cinzas flutuando ao redor do jogador
const ash = (() => {
  const ps = new BABYLON.ParticleSystem('ash', 400, scene);
  ps.particleTexture = flareTex; ps.emitter = new V3(0, 3, 0);
  ps.minEmitBox = new V3(-25, -1, -25); ps.maxEmitBox = new V3(25, 5, 25);
  ps.color1 = new BABYLON.Color4(0.8, 0.75, 0.7, 0.5); ps.color2 = new BABYLON.Color4(1, 0.6, 0.3, 0.4); ps.colorDead = new BABYLON.Color4(0.5, 0.5, 0.5, 0);
  ps.minSize = 0.04; ps.maxSize = 0.12; ps.minLifeTime = 5; ps.maxLifeTime = 10; ps.emitRate = 45;
  ps.direction1 = new V3(-0.3, 0.1, -0.3); ps.direction2 = new V3(0.5, 0.4, 0.5); ps.gravity = new V3(0.1, 0.05, 0.05);
  ps.minEmitPower = 0.2; ps.maxEmitPower = 0.8; ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; ps.start(); return ps;
})();

const sparks = (() => {
  const ps = new BABYLON.ParticleSystem('sparks', 200, scene);
  ps.particleTexture = flareTex; ps.emitter = new V3(0, 1, 0);
  ps.color1 = new BABYLON.Color4(1, 0.7, 0.3, 1); ps.color2 = new BABYLON.Color4(1, 0.2, 0.1, 1); ps.colorDead = new BABYLON.Color4(0.3, 0, 0, 0);
  ps.minSize = 0.08; ps.maxSize = 0.25; ps.minLifeTime = 0.2; ps.maxLifeTime = 0.5; ps.emitRate = 0;
  ps.direction1 = new V3(-3, 2, -3); ps.direction2 = new V3(3, 5, 3); ps.gravity = new V3(0, -9, 0);
  ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; ps.start(); return ps;
})();
function burst(p, n = 18) { sparks.emitter = new V3(p.x, p.y, p.z); sparks.manualEmitCount = n; }

/* ------------------------------ som sintetizado ------------------------------ */
let ac = null;
const SFX = {
  swing: ['sawtooth', 320, 90, 0.12, 0.05], hit: ['square', 180, 50, 0.16, 0.12], block: ['triangle', 700, 300, 0.12, 0.12],
  roll: ['sine', 140, 70, 0.2, 0.1], hurt: ['sawtooth', 200, 60, 0.25, 0.14], estus: ['sine', 400, 900, 0.35, 0.1],
  slam: ['square', 90, 30, 0.5, 0.2], bonfire: ['sine', 220, 440, 0.8, 0.1], die: ['sawtooth', 160, 30, 1.2, 0.2],
  roar: ['sawtooth', 130, 38, 1.5, 0.3], step: ['sine', 70, 35, 0.16, 0.3], heart: ['sine', 62, 40, 0.14, 0.22],
};
function sfx(k, gain = 1) {
  if (!ac) return; const [type, f0, f1, dur, v] = SFX[k], t = ac.currentTime, vol = Math.max(v * gain, 0.0002);
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ac.destination); o.start(t); o.stop(t + dur);
}

/* ------------------------------ mundo ------------------------------ */
// floresta morta (assets/forest.glb, gerada por tools/blender/forest.py); o mapa jogável vem da grade:
// rows: '.' chão livre, '#' tronco, ' ' fora do escaneamento; heights: altura do chão em cm
let worldGrid = null;
function groundY(x, z) {
  const g = worldGrid; if (!g) return 0;
  const u = clamp((x - g.x0) / g.hcell, 0, g.hx - 1.001), v = clamp((z - g.z0) / g.hcell, 0, g.hz - 1.001), i = Math.floor(u), j = Math.floor(v), a = u - i, b = v - j, h = g.heights;
  return lerp(lerp(h[j][i], h[j][i + 1], a), lerp(h[j + 1][i], h[j + 1][i + 1], a), b) / 100;
}
const OUTER_Y = -0.7;   // chão escuro além do escaneamento, some na névoa
{
  const ground = BABYLON.MeshBuilder.CreateGround('ground', { width: 600, height: 600 }, scene);
  ground.position.y = OUTER_Y;
  const gm = new BABYLON.StandardMaterial('gm', scene), tex = new BABYLON.DynamicTexture('gt', 512, scene, true), c = tex.getContext();
  c.fillStyle = '#2a2520'; c.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 900; i++) { const g = 30 + Math.floor(rnd() * 30); c.fillStyle = `rgba(${g + 6},${g},${g - 6},0.35)`; c.beginPath(); c.arc(rnd() * 512, rnd() * 512, 6 + rnd() * 26, 0, 7); c.fill(); }
  tex.update(); tex.uScale = tex.vScale = 60; gm.diffuseTexture = tex; gm.specularColor = C3.Black();
  ground.material = gm;
}
// troncos distantes além do limite do mapa, para a floresta não acabar no vazio
function addFarTrees() {
  const g = worldGrid, trunk = BABYLON.MeshBuilder.CreateCylinder('farTree', { diameterTop: 0.25, diameterBottom: 0.8, height: 30, tessellation: 7 }, scene);
  trunk.material = mat([0.1, 0.085, 0.07]); trunk.isPickable = false;
  for (let n = 0; n < 320;) {
    const x = (rnd() - 0.5) * 220, z = (rnd() - 0.5) * 300;
    const i = Math.floor((x - g.x0) / g.cell), j = Math.floor((z - g.z0) / g.cell);
    n++;
    if (j >= 0 && j < g.nz && i >= 0 && i < g.nx) continue;
    trunk.thinInstanceAdd(BABYLON.Matrix.Translation(x, OUTER_Y + 15, z), n === 320);
  }
}

function resolveWorld(p, r) { gridCollide(p, r); }
// colisão círculo x grade: só o chão livre não bloqueia
function gridBlocked(i, j) {
  const g = worldGrid;
  return i < 0 || j < 0 || i >= g.nx || j >= g.nz || g.rows[j][i] !== '.';
}
function gridCollide(p, r) {
  const g = worldGrid, c = g.cell;
  for (let it = 0; it < 2; it++) {
    const i0 = Math.floor((p.x - r - g.x0) / c), i1 = Math.floor((p.x + r - g.x0) / c);
    const j0 = Math.floor((p.z - r - g.z0) / c), j1 = Math.floor((p.z + r - g.z0) / c);
    for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
      if (!gridBlocked(i, j)) continue;
      const cx = g.x0 + i * c, cz = g.z0 + j * c;
      const nx = clamp(p.x, cx, cx + c), nz = clamp(p.z, cz, cz + c), dx = p.x - nx, dz = p.z - nz, d = Math.hypot(dx, dz);
      if (d < r && d > 1e-5) { p.x = nx + dx / d * r; p.z = nz + dz / d * r; }
    }
  }
}
function trunkAt(x, z) { // a câmera só desvia de troncos; o limite do mapa não a segura
  const g = worldGrid; if (!g) return false;               // a câmera roda antes de a floresta carregar
  const i = Math.floor((x - g.x0) / g.cell), j = Math.floor((z - g.z0) / g.cell);
  return j >= 0 && j < g.nz && i >= 0 && i < g.nx && g.rows[j][i] === '#';
}

// fogueiras
const bonfires = [];
function makeBonfire(x, z, name) {
  const y = groundY(x, z);
  const ash = BABYLON.MeshBuilder.CreateCylinder('ash', { diameterTop: 1.0, diameterBottom: 1.8, height: 0.4 }, scene);
  ash.position.set(x, y + 0.2, z); ash.material = mat([0.1, 0.09, 0.08]);
  const blade = BABYLON.MeshBuilder.CreateBox('coil', { width: 0.08, height: 1.9, depth: 0.2 }, scene);
  blade.position.set(x, y + 1.1, z); blade.rotation.z = 0.08; blade.material = mat([0.7, 0.7, 0.75], [0.15, 0.15, 0.15]);
  const light = new BABYLON.PointLight('fl', new V3(x, y + 1.5, z), scene);
  light.diffuse = new C3(1, 0.55, 0.2); light.intensity = 0; light.range = 28;
  const ps = new BABYLON.ParticleSystem('fire', 250, scene);
  ps.particleTexture = flareTex; ps.emitter = new V3(x, y + 0.45, z);
  ps.minEmitBox = new V3(-0.25, 0, -0.25); ps.maxEmitBox = new V3(0.25, 0, 0.25);
  ps.color1 = new BABYLON.Color4(1, 0.6, 0.1, 1); ps.color2 = new BABYLON.Color4(1, 0.3, 0, 1); ps.colorDead = new BABYLON.Color4(0.3, 0, 0, 0);
  ps.minSize = 0.3; ps.maxSize = 0.75; ps.minLifeTime = 0.4; ps.maxLifeTime = 1.1; ps.emitRate = 0;
  ps.direction1 = new V3(-0.3, 1, -0.3); ps.direction2 = new V3(0.3, 2, 0.3); ps.gravity = new V3(0, 2, 0);
  ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; ps.start();
  const b = { pos: new V3(x, 0, z), name, lit: false, light, ps };
  b.setLit = () => { b.lit = true; light.intensity = 1.6; ps.emitRate = 90; };
  b.putOut = () => { b.lit = false; light.intensity = 0; ps.emitRate = 0; };
  bonfires.push(b); return b;
}

/* ------------------------------ navegação do monstro ------------------------------ */
// grade de 1 m do mapa inteiro: nav = cabe o corpo do monstro; open = a visão passa
const NAV = { x0: 0, z0: 0, nx: 0, nz: 0, nav: null, open: null, field: null, goal: -1 };
const navIndex = (x, z) => {
  const i = Math.floor(x - NAV.x0), j = Math.floor(z - NAV.z0);
  return i < 0 || j < 0 || i >= NAV.nx || j >= NAV.nz ? -1 : j * NAV.nx + i;
};
function buildNav(r) {
  const g = worldGrid, c = g.cell;
  NAV.x0 = Math.floor(g.x0); NAV.z0 = Math.floor(g.z0); NAV.nx = Math.ceil(g.nx * c) + 1; NAV.nz = Math.ceil(g.nz * c) + 1;
  const n = NAV.nx * NAV.nz;
  NAV.nav = new Uint8Array(n); NAV.open = new Uint8Array(n); NAV.field = new Int32Array(n);
  const free = (x, z, rr) => {
    for (let j = Math.floor((z - rr - g.z0) / c); j <= Math.floor((z + rr - g.z0) / c); j++)
      for (let i = Math.floor((x - rr - g.x0) / c); i <= Math.floor((x + rr - g.x0) / c); i++) {
        if (!gridBlocked(i, j)) continue;
        if (Math.hypot(x - clamp(x, g.x0 + i * c, g.x0 + (i + 1) * c), z - clamp(z, g.z0 + j * c, g.z0 + (j + 1) * c)) < rr) return false;
      }
    return true;
  };
  for (let j = 0, k = 0; j < NAV.nz; j++) for (let i = 0; i < NAV.nx; i++, k++) {
    const x = NAV.x0 + i + 0.5, z = NAV.z0 + j + 0.5;
    NAV.nav[k] = free(x, z, r) ? 1 : 0; NAV.open[k] = free(x, z, 0.05) ? 1 : 0;
  }
}
function nearestNav(x, z) { // célula livre mais próxima de um ponto
  const c = navIndex(x, z); if (c >= 0 && NAV.nav[c]) return c;
  for (let r = 1; r < 14; r++) for (let a = 0; a < 16; a++) {
    const k = navIndex(x + Math.sin(a / 16 * 6.283) * r, z + Math.cos(a / 16 * 6.283) * r);
    if (k >= 0 && NAV.nav[k]) return k;
  }
  return -1;
}
function navGoal(x, z) { // recalcula o campo de distâncias (BFS) quando o destino muda de célula
  const g = nearestNav(x, z); if (g < 0 || g === NAV.goal) return;
  NAV.goal = g; const f = NAV.field, q = new Int32Array(NAV.nx * NAV.nz); f.fill(-1); f[g] = 0;
  for (let h = 0, t = 1, cur = q[0] = g; h < t; cur = q[++h]) {
    const i = cur % NAV.nx, d = f[cur] + 1;
    if (i > 0 && NAV.nav[cur - 1] && f[cur - 1] < 0) { f[cur - 1] = d; q[t++] = cur - 1; }
    if (i < NAV.nx - 1 && NAV.nav[cur + 1] && f[cur + 1] < 0) { f[cur + 1] = d; q[t++] = cur + 1; }
    if (cur >= NAV.nx && NAV.nav[cur - NAV.nx] && f[cur - NAV.nx] < 0) { f[cur - NAV.nx] = d; q[t++] = cur - NAV.nx; }
    if (cur + NAV.nx < f.length && NAV.nav[cur + NAV.nx] && f[cur + NAV.nx] < 0) { f[cur + NAV.nx] = d; q[t++] = cur + NAV.nx; }
  }
}
function lineClear(ax, az, bx, bz, grid) { // amostra a reta na grade
  const d = Math.hypot(bx - ax, bz - az), n = Math.ceil(d * 2);
  for (let s = 1; s < n; s++) { const k = navIndex(lerp(ax, bx, s / n), lerp(az, bz, s / n)); if (k < 0 || !grid[k]) return false; }
  return true;
}
const canSee = (a, b) => !NAV.open || lineClear(a.x, a.z, b.x, b.z, NAV.open);
function navStep(pos) { // próximo ponto do caminho: desce o campo e corta caminho enquanto a reta estiver livre
  let c = nearestNav(pos.x, pos.z); if (c < 0 || NAV.field[c] < 0) return null;
  let best = null;
  for (let s = 0; s < 8 && NAV.field[c] > 0; s++) {
    const i = c % NAV.nx; let next = -1, low = NAV.field[c];
    for (const k of [i > 0 ? c - 1 : -1, i < NAV.nx - 1 ? c + 1 : -1, c - NAV.nx, c + NAV.nx]) if (k >= 0 && k < NAV.field.length && NAV.field[k] >= 0 && NAV.field[k] < low) { low = NAV.field[k]; next = k; }
    if (next < 0) break;
    c = next; const x = NAV.x0 + c % NAV.nx + 0.5, z = NAV.z0 + Math.floor(c / NAV.nx) + 0.5;
    if (best && !lineClear(pos.x, pos.z, x, z, NAV.nav)) break;
    best = { x, z };
  }
  return best;
}

// pegadas que o monstro deixa: é assim que você o rastreia
const tracks = (() => {
  const m = mat([0, 0, 0], [1, 0.32, 0.06]); m.zOffset = -3; m.disableLighting = true; m.backFaceCulling = false;
  return Array.from({ length: 90 }, () => {
    const d = BABYLON.MeshBuilder.CreateDisc('track', { radius: 0.34, tessellation: 10 }, scene);
    d.rotation.x = Math.PI / 2; d.scaling.x = 0.8; d.scaling.y = 1.4; d.material = m; d.isPickable = false; d.setEnabled(false); d.age = 1e9;
    return d;
  });
})();
let trackNext = 0, trackSide = 1;
function dropTrack(x, z, yaw) {
  const d = tracks[trackNext]; trackNext = (trackNext + 1) % tracks.length; trackSide = -trackSide;
  const tx = x + Math.cos(yaw) * 0.55 * trackSide, tz = z - Math.sin(yaw) * 0.55 * trackSide;
  d.position.set(tx, groundY(tx, tz) + 0.14, tz);
  d.rotation.y = yaw; d.age = 0; d.setEnabled(true);
}
function updateTracks(dt) {
  const life = CONFIG.hunt.trackLife;
  for (const d of tracks) if (d.age < life) { d.age += dt; d.visibility = 0.75 * (1 - d.age / life); if (d.age >= life) d.setEnabled(false); }
}

/* ------------------------------ humanoide procedural ------------------------------ */
function buildHumanoid(o) {
  const root = new BABYLON.TransformNode('ent', scene);
  const pivot = new BABYLON.TransformNode('pv', scene); pivot.parent = root; pivot.position.y = 0.9;
  const model = new BABYLON.TransformNode('md', scene); model.parent = pivot; model.position.y = -0.9;
  const mats = [], M = c => { const m = mat(c); mats.push(m); return m; };
  const skin = M(o.skin), armor = M(o.armor);
  const box = (w, h, d, parent, x, y, z, m) => {
    const b = BABYLON.MeshBuilder.CreateBox('b', { width: w, height: h, depth: d }, scene);
    b.parent = parent; b.position.set(x, y, z); b.material = m; return b;
  };
  box(0.7, 0.75, 0.4, model, 0, 1.2, 0, armor);
  const head = BABYLON.MeshBuilder.CreateSphere('head', { diameter: 0.4 }, scene);
  head.parent = model; head.position.y = 1.8; head.material = skin;
  const eyeM = mat(o.eye, o.eye);
  box(0.07, 0.05, 0.05, model, -0.09, 1.83, 0.18, eyeM); box(0.07, 0.05, 0.05, model, 0.09, 1.83, 0.18, eyeM);
  const pv = (x, y) => { const n = new BABYLON.TransformNode('j', scene); n.parent = model; n.position.set(x, y, 0); return n; };
  const legL = pv(-0.18, 0.8), legR = pv(0.18, 0.8), lArm = pv(-0.5, 1.5), rArm = pv(0.5, 1.5);
  box(0.26, 0.8, 0.28, legL, 0, -0.4, 0, armor); box(0.26, 0.8, 0.28, legR, 0, -0.4, 0, armor);
  box(0.2, 0.7, 0.2, lArm, 0, -0.35, 0, skin); box(0.2, 0.7, 0.2, rArm, 0, -0.35, 0, skin);
  const len = o.weapon, wm = mat([0.75, 0.75, 0.8], [0.12, 0.12, 0.14]);
  box(0.07, len, 0.22, rArm, 0, -0.7 - len / 2, 0, wm); box(0.34, 0.06, 0.1, rArm, 0, -0.72, 0, wm);
  if (o.horns) for (const s of [-1, 1]) {
    const h = BABYLON.MeshBuilder.CreateCylinder('horn', { diameterTop: 0, diameterBottom: 0.14, height: 0.4 }, scene);
    h.parent = model; h.position.set(s * 0.2, 2.05, 0); h.rotation.z = -s * 0.5; h.material = mat([0.8, 0.75, 0.6]);
  }
  const shield = BABYLON.MeshBuilder.CreateCylinder('shield', { diameter: 0.8, height: 0.08, tessellation: 24 }, scene);
  shield.parent = model; shield.rotation.x = Math.PI / 2; shield.material = mat([0.35, 0.28, 0.18]); shield.setEnabled(!!o.shield);
  shadowCast(root);
  return { root, pivot, model, legL, legR, lArm, rArm, mats, shield };
}

/* ------------------------------ cavalo de xadrez procedural ------------------------------ */
function buildChessKnight(o) {
  const root = new BABYLON.TransformNode('ent', scene);
  const pivot = new BABYLON.TransformNode('pv', scene); pivot.parent = root; pivot.position.y = 0.9;
  const model = new BABYLON.TransformNode('md', scene); model.parent = pivot; model.position.y = -0.9;
  const mats = [], M = c => { const m = mat(c); mats.push(m); return m; };
  const stone = M(o.armor), skin = M(o.skin), dark = M(o.armor.map(v => v * 0.6));
  const cyl = (name, dt, db, h, y, m, parent = model) => {
    const c = BABYLON.MeshBuilder.CreateCylinder(name, { diameterTop: dt, diameterBottom: db, height: h, tessellation: 24 }, scene);
    c.parent = parent; c.position.y = y; c.material = m; return c;
  };
  const box = (w, h, d, parent, x, y, z, m, rx = 0) => {
    const b = BABYLON.MeshBuilder.CreateBox('b', { width: w, height: h, depth: d }, scene);
    b.parent = parent; b.position.set(x, y, z); b.rotation.x = rx; b.material = m; return b;
  };
  // base escalonada
  cyl('base1', 1.0, 1.15, 0.16, 0.08, dark); cyl('base2', 0.85, 1.0, 0.14, 0.23, stone); cyl('ring', 0.78, 0.78, 0.07, 0.33, dark);
  cyl('collar', 0.6, 0.8, 0.32, 0.52, stone);
  // tronco/pescoço inclinado para a frente
  const neck = cyl('neck', 0.42, 0.62, 0.8, 1.0, stone); neck.rotation.x = 0.22; neck.position.z = 0.04;
  // crina descendo pela nuca
  for (let i = 0; i < 5; i++) box(0.1, 0.2, 0.16, model, 0, 1.55 - i * 0.18, -0.2 - i * 0.015, dark, -0.25);
  // cabeça (pivô usado na animação de ataque)
  const head = new BABYLON.TransformNode('head', scene); head.parent = model; head.position.set(0, 1.42, 0.08);
  box(0.36, 0.52, 0.42, head, 0, 0.08, 0, skin, -0.15);        // crânio
  box(0.27, 0.27, 0.58, head, 0, -0.1, 0.42, skin, 0.38);      // focinho
  box(0.3, 0.12, 0.14, head, 0, -0.27, 0.66, dark, 0.38);      // ponta do focinho
  const eye = mat(o.eye, o.eye);
  box(0.05, 0.07, 0.1, head, -0.19, 0.14, 0.2, eye); box(0.05, 0.07, 0.1, head, 0.19, 0.14, 0.2, eye);
  for (const s of [-1, 1]) {
    const ear = BABYLON.MeshBuilder.CreateCylinder('ear', { diameterTop: 0, diameterBottom: 0.14, height: 0.3, tessellation: 8 }, scene);
    ear.parent = head; ear.position.set(s * 0.11, 0.44, -0.06); ear.rotation.z = -s * 0.15; ear.material = dark;
    if (o.horns) {
      const h = BABYLON.MeshBuilder.CreateCylinder('horn', { diameterTop: 0, diameterBottom: 0.14, height: 0.5, tessellation: 8 }, scene);
      h.parent = head; h.position.set(s * 0.22, 0.45, 0.02); h.rotation.z = -s * 0.6; h.material = mat([0.8, 0.75, 0.6]);
    }
  }
  const dummy = () => new BABYLON.TransformNode('j', scene);
  shadowCast(root);
  return { root, pivot, model, rArm: head, lArm: dummy(), legL: dummy(), legR: dummy(), mats, chess: true };
}

/* ------------------------------ cavaleiro (modelo .glb) ------------------------------ */
let knightAsset = null, bossAsset = null;
// frames da animação "Take 001"; andar, correr, rolar e os cortes extras gerados no Blender (tools/blender/knight_anims.py)
const KNIGHT = {
  scale: 0.16, facing: 0, idleFrom: 130, idleTo: 350,
  walk: { from: 375, to: 435, stride: 2.4 },   // stride = metros por ciclo (sincroniza os pés com o deslocamento)
  run:  { from: 450, to: 490, stride: 3.6 },
  runAbove: 5.5,                                // m/s a partir do qual usa a corrida
  roll: { from: 500, to: 535 },
  // golpes: [início, fim da preparação, fim do golpe, fim da recuperação]
  clips: { vertical: [0, 30, 42, 130], sweep: [550, 572.5, 577.5, 625], diag: [650, 672.5, 677.5, 725] },
};
// monstro: boss.glb ("Tillagemon Boss Skeleton", Vasian-Digital3D, CC-BY-4.0) com animações próprias
const BOSS = {
  scale: 0.25,                                  // multiplicado pelo scale do CONFIG (2.5) => 0.625 m por unidade
  walk: { clip: 'Battle_Walk', stride: 3.1 },   // stride em unidades do modelo
  run:  { clip: 'Battle_Run',  stride: 3.1 },
  runAbove: 2.2,
};
function instantiate(asset, scale, o) {
  const root = new BABYLON.TransformNode('ent', scene);
  const pivot = new BABYLON.TransformNode('pv', scene); pivot.parent = root; pivot.position.y = 0.9;
  const model = new BABYLON.TransformNode('md', scene); model.parent = pivot; model.position.y = -0.9;
  const wrap = new BABYLON.TransformNode('wrap', scene); wrap.parent = model; wrap.scaling.setAll(scale);
  const inst = asset.instantiateModelsToScene(n => n, true);
  inst.rootNodes[0].parent = wrap;
  const mats = [];
  inst.rootNodes[0].getChildMeshes().forEach(m => {
    m.alwaysSelectAsActiveMesh = true;
    if (m.material && !mats.includes(m.material)) { m.material.maxSimultaneousLights = 8; mats.push(m.material); if (o.tint) m.material.albedoColor = new C3(o.tint[0], o.tint[1], o.tint[2]); }
  });
  inst.animationGroups.forEach(g => { g.start(false, 1, g.from, g.to); g.pause(); });
  shadowCast(root);
  const dummy = () => new BABYLON.TransformNode('j', scene);
  return { root, pivot, model, rArm: dummy(), lArm: dummy(), legL: dummy(), legR: dummy(), mats, groups: inst.animationGroups };
}
function buildKnight(o) {
  const h = instantiate(knightAsset, KNIGHT.scale, o);
  h.glb = true; h.anim = h.groups[0]; return h;
}
function buildBoss(o) {
  const h = instantiate(bossAsset, BOSS.scale, {});
  h.bossRig = true; h.clips = {};
  h.groups.forEach(g => {
    // o exportador do Sketchfab põe uma chave extra no tempo 0: o clipe começa na segunda chave
    g.clipFrom = Math.min(...g.targetedAnimations.map(t => { const k = t.animation.getKeys(); return k[k.length > 1 ? 1 : 0].frame; }));
    h.clips[g.name.replace(/^TillagemonBoss\d*_/, '')] = g;
  });
  h.pose = (name, u) => { const g = h.clips[name]; g.goToFrame(g.clipFrom + clamp(u, 0, 1) * (g.to - g.clipFrom)); };
  h.len = name => (h.clips[name].to - h.clips[name].clipFrom) / 60;
  return h;
}
const BLACK = new C3(0, 0, 0), FLASH = new C3(0.75, 0.15, 0.1), RAGE = new C3(0.35, 0, 0);
const setEmissive = (mats, c) => mats.forEach(m => m.emissiveColor = c);
function gaitCycle(o, g, signedSpeed, s, dt) { // avança o ciclo de passos; velocidade negativa anda de costas
  if (o.gait !== g) { o.gait = g; o.cycle = 0; }
  return o.cycle = ((o.cycle + Math.sign(signedSpeed) * s * dt / g.stride) % 1 + 1) % 1;
}
function animateLimbs(h, signedSpeed, dt, o) {
  const speed = Math.abs(signedSpeed);
  o.phase = (o.phase || 0) + speed * dt * 1.5;
  if (h.bossRig) { // monstro: parado, andando ou correndo com os clipes do modelo
    if (o.armsBusy) return;
    const s = speed / h.root.scaling.x;
    if (speed < 0.3) { o.clock = (o.clock || 0) + dt; o.gait = null; h.pose('Battle_Stand', (o.clock / h.len('Battle_Stand')) % 1); }
    else { const g = speed > BOSS.runAbove ? BOSS.run : BOSS.walk; h.pose(g.clip, gaitCycle(o, g, signedSpeed, s / BOSS.scale, dt)); }
    h.model.rotation.x = o.flinch || 0;
    return;
  }
  if (h.glb && !o.noLocomotion) { // cavaleiro: idle parado, ciclos de andar/correr em movimento
    if (o.armsBusy) return;
    const s = speed / h.root.scaling.x;                      // velocidade em escala do modelo
    if (s < 0.3) {
      o.clock = (o.clock || 0) + dt; o.gait = null;
      h.anim.goToFrame(KNIGHT.idleFrom + (o.clock * 60) % (KNIGHT.idleTo - KNIGHT.idleFrom));
    } else {
      const g = s > KNIGHT.runAbove ? KNIGHT.run : KNIGHT.walk;
      h.anim.goToFrame(g.from + gaitCycle(o, g, signedSpeed, s, dt) * (g.to - g.from));
    }
    h.model.position.y = -0.9; h.model.rotation.x = o.flinch || 0;
    return;
  }
  if (h.glb) { // monstro sem boss.glb: respira (idle) e desliza com leve inclinação
    const k = clamp(speed / 6, 0, 1);
    if (!o.armsBusy) {
      o.clock = (o.clock || 0) + dt * (1 + k * 1.6);
      h.anim.goToFrame(KNIGHT.idleFrom + (o.clock * 60) % (KNIGHT.idleTo - KNIGHT.idleFrom));
      h.model.position.y = -0.9 + Math.abs(Math.sin(o.phase)) * 0.06 * k;
      h.model.rotation.x = 0.1 * k + (o.flinch || 0);
    }
    return;
  }
  if (h.chess) { // peça desliza aos pulinhos
    const k = clamp(speed / 6, 0, 1);
    h.model.position.y = -0.9 + Math.abs(Math.sin(o.phase)) * 0.15 * k; h.model.rotation.z = Math.sin(o.phase) * 0.07 * k;
    if (!o.armsBusy) { h.model.rotation.x *= 0.8; h.rArm.rotation.x *= 0.8; }
    return;
  }
  const amp = clamp(speed / 6, 0, 1) * 0.9, s = Math.sin(o.phase);
  h.legL.rotation.x = s * amp; h.legR.rotation.x = -s * amp;
  if (!o.armsBusy) { h.lArm.rotation.x = -s * amp * 0.7; h.rArm.rotation.x = s * amp * 0.7; }
}
// pose de ataque; a = definição do ataque (clipe do cavaleiro ou animação do chefe)
function armPose(h, stage, p, a) {
  if (h.bossRig) {
    const [w, e] = a.hit;
    h.pose(a.anim, stage === 'windup' ? lerp(0, w, p) : stage === 'active' ? lerp(w, e, p) : lerp(e, 1, p)); return;
  }
  if (h.glb) {
    const [f0, w, e, f1] = KNIGHT.clips[(a && a.clip) || 'vertical'];
    h.anim.goToFrame(stage === 'windup' ? lerp(f0, w, p) : stage === 'active' ? lerp(w, e, p) : lerp(e, f1, p));
    h.model.rotation.x = stage === 'active' ? 0.12 : 0; return;
  }
  if (h.chess) { // cavalo: empina para trás e investe com a cabeça
    const k = stage === 'windup' ? -easeOut(p) : stage === 'active' ? lerp(-1, 1, p) : lerp(1, 0, p * p * (3 - 2 * p));
    h.rArm.rotation.x = k * 0.8; h.model.rotation.x = k * 0.3; return;
  }
  const raise = -3.2, strike = -1.1;
  if (stage === 'windup') h.rArm.rotation.x = lerp(0, raise, easeOut(p));
  else if (stage === 'active') h.rArm.rotation.x = lerp(raise, strike, p);
  else h.rArm.rotation.x = lerp(strike, 0, p * p * (3 - 2 * p));
}

/* ------------------------------ estado do jogo ------------------------------ */
const game = {
  started: false, over: false, huntTime: 0,
  lock: null, bonfire: null, sign: null,   // sign = última pista de onde o monstro está (bússola)
};
const keys = {}, pressed = {};
const cam = { yaw: 0, pitch: 0.35, dist: 6.5, cur: 6.5 };   // cur = distância real (encurta ao bater em paredes)
let shake = 0;

/* ------------------------------ jogador ------------------------------ */
const P = (() => {
  const h = buildHumanoid({ skin: [0.7, 0.55, 0.45], armor: [0.3, 0.32, 0.38], eye: [0.9, 0.9, 1], weapon: 1.1, shield: true });
  h.shield.position.set(0.52, 1.1, -0.1);
  return {
    h, root: h.root, pos: h.root.position, radius: 0.5,
    maxHp: CONFIG.player.maxHp, hp: CONFIG.player.maxHp, maxStamina: CONFIG.player.maxStamina, stamina: CONFIG.player.maxStamina,
    estus: CONFIG.player.estusMax, lives: CONFIG.hunt.lives, noise: 0,
    state: 'free', t: 0, staminaDelay: 0, blocking: false, buf: null, atk: null, combo: 0, flash: 0, anim: {},
    rollDir: new V3(0, 0, 1), healed: false, deadT: 0,
  };
})();
P.pos.set(2, 0, 0);

function hurtPlayer(dmg, from) {
  if (P.state === 'dead') return false;
  if (P.state === 'roll' && P.t > 0.05 && P.t < 0.38) return false;
  const toSrc = Math.atan2(from.x - P.pos.x, from.z - P.pos.z);
  const facing = Math.abs(angDiff(P.root.rotation.y, toSrc)) < 1.2;
  if (P.blocking && P.state === 'free' && facing) {
    P.stamina -= dmg * 0.9; P.staminaDelay = 1.0;
    burst(new V3(P.pos.x, P.pos.y + 1.3, P.pos.z), 10);
    if (P.stamina > 0) { P.hp -= dmg * 0.12; sfx('block'); updateDeath(); return true; }
    P.stamina = 0; dmg *= 0.6; staggerPlayer(0.8); sfx('hurt');          // guarda quebrada
  } else { staggerPlayer(0.4); sfx('hurt'); }
  P.hp -= dmg; P.flash = 0.15;
  const away = Math.atan2(P.pos.x - from.x, P.pos.z - from.z);
  P.pos.x += Math.sin(away) * 0.4; P.pos.z += Math.cos(away) * 0.4;
  burst(new V3(P.pos.x, P.pos.y + 1.3, P.pos.z), 14);
  updateDeath(); return true;
}
function staggerPlayer(d) { P.state = 'stagger'; P.t = 0; P.stagDur = d; P.atk = null; P.h.pivot.rotation.x = 0; }
function updateDeath() { if (P.hp <= 0 && P.state !== 'dead') killPlayer(); }
function killPlayer() {
  P.hp = 0; P.state = 'dead'; P.deadT = 0; P.lives--; sfx('die'); game.lock = null;
  if (P.lives > 0) $('death').classList.add('show');
}
function respawn() {
  if (P.lives <= 0) return endHunt(false);
  $('death').classList.remove('show');
  const b = game.bonfire;
  P.pos.set(b.pos.x + 2, 0, b.pos.z); P.root.rotation.y = 0;
  fullRest(); P.state = 'free'; P.h.pivot.rotation.x = 0; P.h.pivot.position.y = 0.9;
  if (monster) monster.startFlee(false);                     // satisfeito, ele recua e volta a caçar
}
function fullRest() { P.hp = P.maxHp; P.stamina = P.maxStamina; P.estus = CONFIG.player.estusMax; }

/* ------------------------------ inimigos ------------------------------ */
const enemies = [];
class Enemy {
  constructor(type, x, z) {
    this.type = type; this.def = CONFIG.enemies[type];
    this.h = bossAsset ? buildBoss(this.def.look) : knightAsset ? buildKnight(this.def.look) : buildChessKnight(this.def.look); this.root = this.h.root; this.root.scaling.setAll(this.def.scale);
    this.pos = this.root.position; this.radius = 0.5 * this.def.scale; this.anim = { noLocomotion: true };
    this.ring = BABYLON.MeshBuilder.CreateDisc('ring', { radius: 1, tessellation: 48 }, scene);
    this.ring.rotation.x = Math.PI / 2; this.ring.setEnabled(false);
    const rm = mat([0.8, 0.1, 0.05], [0.8, 0.1, 0.05]); rm.alpha = 0.35; rm.backFaceCulling = false; rm.zOffset = -4; this.ring.material = rm;
    this.hp = this.def.hp; this.state = 'lurk'; this.t = 0; this.lurkDur = 5; this.lurkHeal = 0; this.dead = false; this.cd = 1; this.phase = 1;
    this.atk = null; this.flash = 0; this.introPose = false; this.strafe = Math.random() < 0.5 ? 1 : -1;
    this.aware = 0; this.lostT = 0; this.senseT = 0; this.seesP = false; this.scentT = 3; this.searchT = 0; this.roarT = 9; this.lead = null;
    this.air = 0; this.fleeIdx = 0; this.wantFlee = false; this.lastTrack = new V3(x, 0, z); this.visible = false;
    this.pos.set(x, 0, z); this.root.rotation.y = Math.PI;
  }
  get spd() { return this.def.speed * (this.phase === 2 ? 1.25 : 1); }
  damage(amount, heavy) {
    if (this.dead) return;
    // emboscada: ele ainda não tinha notado você
    const unaware = this.state === 'hunt' || this.state === 'search' || this.state === 'lurk' || this.state === 'roar';
    if (unaware) { amount *= CONFIG.hunt.ambushMult; showMsg('EMBOSCADA!', 'gold', 1500); }
    this.hp -= amount; this.flash = 0.12; sfx('hit');
    burst(new V3(this.pos.x, this.pos.y + 1.4 * this.def.scale, this.pos.z), 16);
    if (this.fleeIdx < CONFIG.hunt.fleeAt.length && this.hp > 0 && this.hp < this.def.hp * CONFIG.hunt.fleeAt[this.fleeIdx]) { this.fleeIdx++; this.wantFlee = true; }
    if (this.hp <= 0) return this.die();
    if (unaware) { this.spot(); this.state = 'stagger'; this.t = 0; this.stagDur = heavy ? 1.6 : 1.1; }
  }
  die() { this.dead = true; this.air = 0; this.pos.y = groundY(this.pos.x, this.pos.z); this.hideRing(); if (game.lock === this) game.lock = null; monsterDefeated(); }
  hideRing() { this.ring.setEnabled(false); }
  startAttack(a) { this.atk = a; this.state = 'windup'; this.t = 0; this.windDur = a.windup * (this.phase === 2 ? 0.8 : 1); }
  spot() { this.aware = 1; this.lostT = 0; this.lead = P.pos.clone(); }
  startFlee(enrage) {
    const H = CONFIG.hunt; let far = null, fd = -1;
    for (const [x, z] of DENS) { const d = Math.hypot(x - P.pos.x, z - P.pos.z); if (d > fd) { fd = d; far = [x, z]; } }
    this.flee = { x: far[0], z: far[1] }; this.state = 'flee'; this.t = 0; this.aware = 0; this.atk = null; this.hideRing();
    this.lurkHeal = enrage ? H.lurkHeal * this.def.hp / H.lurkTime : 0; this.lurkDur = enrage ? H.lurkTime : 3;
    if (enrage) { this.phase = 2; this.roar(); showMsg('ELE FOGE — SIGA AS PEGADAS', 'red', 2800); }
  }
  roar() { // é assim que ele denuncia onde está: a bússola aponta para o rugido
    const d = Math.hypot(this.pos.x - P.pos.x, this.pos.z - P.pos.z);
    sfx('roar', clamp(1.3 - d / 90, 0.25, 1)); shake = Math.max(shake, clamp(0.5 - d / 60, 0, 0.5));
    game.sign = { x: this.pos.x, z: this.pos.z, t: 0 };
    const [a, b] = CONFIG.hunt.roarEvery; this.roarT = a + Math.random() * (b - a);
  }
  strike() {
    const a = this.atk, f = this.root.rotation.y, dx = P.pos.x - this.pos.x, dz = P.pos.z - this.pos.z, d = Math.hypot(dx, dz);
    if (a.kind === 'melee') {
      const inArc = Math.abs(angDiff(f, Math.atan2(dx, dz))) < (a.arc / 2) * Math.PI / 180;
      if (d < a.range + 0.4 && inArc) hurtPlayer(a.dmg, this.pos);
    } else {
      const c = a.kind === 'aoe' ? new V3(this.pos.x + Math.sin(f) * a.reach, 0, this.pos.z + Math.cos(f) * a.reach) : this.pos;
      burst(new V3(c.x, groundY(c.x, c.z) + 0.3, c.z), 60); sfx('slam'); shake = Math.max(shake, a.kind === 'leap' ? 0.7 : 0.5);
      if (Math.hypot(P.pos.x - c.x, P.pos.z - c.z) < a.radius) hurtPlayer(a.dmg, c);
    }
  }
  // sentidos, 5x por segundo: visão (cone + linha livre) e audição
  sense(dist, want) {
    const H = CONFIG.hunt; this.senseT = 0.2;
    const los = canSee(this.pos, P.pos);
    this.visible = los && dist < H.sight + 6;
    this.seesP = los && dist < H.sight && (dist < 5 || Math.abs(angDiff(this.root.rotation.y, want)) < H.sightArc * Math.PI / 180);
    if (this.state === 'flee') return;
    if (this.seesP) this.aware = Math.min(1, this.aware + 0.2 * (dist < 12 ? 3 : 1.2));
    else if (this.state !== 'chase') this.aware = Math.max(0, this.aware - 0.2 * 0.25);
    if (P.noise >= dist) this.lead = P.pos.clone();           // ouviu: sabe exatamente de onde veio
  }
  moveToward(x, z, speed, dt) {
    navGoal(x, z);
    const step = navStep(this.pos), tx = step ? step.x : x, tz = step ? step.z : z;
    this.root.rotation.y = turnToward(this.root.rotation.y, Math.atan2(tx - this.pos.x, tz - this.pos.z), 4.5 * dt);
    const f = this.root.rotation.y;
    this.pos.x += Math.sin(f) * speed * dt; this.pos.z += Math.cos(f) * speed * dt;
    return speed;
  }
  update(dt) {
    if (this.dead) return;
    const H = CONFIG.hunt;
    if (this.flash > 0) this.flash -= dt;
    setEmissive(this.h.mats, this.flash > 0 ? FLASH : this.phase === 2 ? RAGE : BLACK);
    const dx = P.pos.x - this.pos.x, dz = P.pos.z - this.pos.z, dist = Math.hypot(dx, dz), want = Math.atan2(dx, dz);
    const alive = P.state !== 'dead';
    if ((this.senseT -= dt) <= 0 && alive) this.sense(dist, want);
    let moveSpeed = 0;
    if (this.cd > 0) this.cd -= dt;
    if (alive && (this.state === 'hunt' || this.state === 'search')) { // nunca para de procurar: de tempos em tempos fareja e ruge
      this.searchT += dt;
      if ((this.scentT -= dt) <= 0) {
        this.scentT = H.scentEvery * (this.phase === 2 ? 0.7 : 1);
        const err = lerp(H.scentErr[0], H.scentErr[1], clamp(this.searchT / 45, 0, 1)), a = Math.random() * 6.283;
        this.lead = new V3(P.pos.x + Math.sin(a) * err, 0, P.pos.z + Math.cos(a) * err);
        if (this.state === 'search') { this.state = 'hunt'; this.t = 0; }
      }
      if (this.aware >= 1) { this.state = 'chase'; this.spot(); this.searchT = 0; game.sign = { x: this.pos.x, z: this.pos.z, t: 0 }; showMsg('ELE TE VIU', 'red', 1500); sfx('roar', 0.7); }
      else if ((this.roarT -= dt) <= 0) { this.roar(); this.state = 'roar'; this.t = 0; }
    }
    switch (this.state) {
      case 'hunt': { // vai até a última pista; mais rápido se ouviu você de verdade
        if (!alive) break;
        if (!this.lead) { this.state = 'search'; break; }
        if (Math.hypot(this.lead.x - this.pos.x, this.lead.z - this.pos.z) < 3.5) { this.state = 'search'; this.scentT = Math.min(this.scentT, 3); this.lead = null; break; }
        moveSpeed = this.moveToward(this.lead.x, this.lead.z, P.noise >= dist ? this.def.alertSpeed : this.def.huntSpeed, dt);
        break;
      }
      case 'search': // cheira o chão e olha em volta
        this.root.rotation.y += Math.sin(this.searchT * 1.6) * 1.1 * dt;
        break;
      case 'roar':
        this.t += dt; if (this.t >= 1.6) this.state = 'hunt';
        break;
      case 'lurk': // escondido, recuperando vida
        this.t += dt; this.hp = Math.min(this.def.hp, this.hp + this.lurkHeal * dt);
        if (this.t >= this.lurkDur || (this.seesP && dist < 12)) { this.state = 'hunt'; this.t = 0; this.scentT = Math.min(this.scentT, 1); this.searchT = 0; }
        break;
      case 'flee': {
        this.t += dt;
        if (Math.hypot(this.flee.x - this.pos.x, this.flee.z - this.pos.z) < 3 || this.t > 22) { this.state = 'lurk'; this.t = 0; break; }
        moveSpeed = this.moveToward(this.flee.x, this.flee.z, this.def.fleeSpeed, dt);
        break;
      }
      case 'chase': {
        if (!alive) { this.state = 'hunt'; this.lead = null; break; }
        if (this.wantFlee) { this.wantFlee = false; this.startFlee(true); break; }
        // perdeu você de vista por tempo demais: volta a procurar a partir de onde te viu
        if (this.seesP || P.noise >= dist || dist < 8) { this.lostT = 0; this.lead = P.pos.clone(); }
        else if ((this.lostT += dt) > 4) { this.state = 'hunt'; this.aware = 0; this.scentT = H.scentEvery * 0.5; this.searchT = 0; break; }
        if (this.cd <= 0) {
          const los = canSee(this.pos, P.pos);
          const opts = this.def.attacks.filter(a => dist >= (a.minD || 0) && dist <= (a.maxD || a.range + 0.5) && (a.kind !== 'leap' || los));
          if (opts.length) { this.startAttack(opts[Math.floor(Math.random() * opts.length)]); break; }
        }
        if (dist > this.def.stopDist) moveSpeed = this.moveToward(this.lead.x, this.lead.z, this.spd, dt);
        else {
          this.root.rotation.y = turnToward(this.root.rotation.y, want, 4.5 * dt);
          const f = this.root.rotation.y;
          if (dist < this.def.stopDist - 0.6) moveSpeed = -this.spd * 0.5;
          else { // circula esperando a recarga
            this.pos.x += Math.cos(f) * this.strafe * this.spd * 0.35 * dt; this.pos.z -= Math.sin(f) * this.strafe * this.spd * 0.35 * dt; moveSpeed = this.spd * 0.35;
          }
          this.pos.x += Math.sin(f) * moveSpeed * dt; this.pos.z += Math.cos(f) * moveSpeed * dt;
        }
        break;
      }
      case 'windup': {
        this.t += dt; const p = clamp(this.t / this.windDur, 0, 1), a = this.atk;
        if (this.t < this.windDur * 0.6) this.root.rotation.y = turnToward(this.root.rotation.y, want, 3 * dt);
        armPose(this.h, 'windup', p, a);
        const f = this.root.rotation.y;
        if (a.kind === 'aoe') { this.ring.setEnabled(true); this.ring.scaling.setAll(a.radius); this.ring.position.x = this.pos.x + Math.sin(f) * a.reach; this.ring.position.z = this.pos.z + Math.cos(f) * a.reach; this.ring.position.y = groundY(this.ring.position.x, this.ring.position.z) + 0.2; }
        else if (a.kind === 'leap') { this.ring.setEnabled(true); this.ring.scaling.setAll(a.radius); this.ring.position.x = P.pos.x; this.ring.position.z = P.pos.z; this.ring.position.y = P.pos.y + 0.2; }
        if (this.t >= this.windDur) {
          this.state = 'active'; this.t = 0;
          if (a.kind === 'leap') { this.leapFrom = this.pos.clone(); const d = Math.max(dist - 1.5, 0); this.leapTo = new V3(this.pos.x + Math.sin(want) * d, 0, this.pos.z + Math.cos(want) * d); this.root.rotation.y = want;
            const k = nearestNav(this.leapTo.x, this.leapTo.z); if (k >= 0) this.leapTo.set(NAV.x0 + k % NAV.nx + 0.5, 0, NAV.z0 + Math.floor(k / NAV.nx) + 0.5); } // pousa fora dos troncos
          else this.strike();
        }
        break;
      }
      case 'active': {
        this.t += dt; const a = this.atk, p = clamp(this.t / a.active, 0, 1);
        armPose(this.h, 'active', p, a);
        if (a.kind === 'leap') {
          this.pos.x = lerp(this.leapFrom.x, this.leapTo.x, p); this.pos.z = lerp(this.leapFrom.z, this.leapTo.z, p);
          this.air = Math.sin(p * Math.PI) * 4;
        }
        if (this.t >= a.active) {
          if (a.kind === 'leap') { this.air = 0; this.strike(); }
          this.hideRing(); this.state = 'recover'; this.t = 0;
        }
        break;
      }
      case 'recover': {
        this.t += dt; const a = this.atk, r = a.recover * (this.phase === 2 ? 0.75 : 1);
        armPose(this.h, 'recover', clamp(this.t / r, 0, 1), a);
        if (this.t >= r) { this.state = 'chase'; this.lead = P.pos.clone(); this.cd = (0.3 + Math.random() * 0.7) * (this.phase === 2 ? 0.6 : 1); this.strafe = Math.random() < 0.5 ? 1 : -1; }
        break;
      }
      case 'stagger':
        this.t += dt; if (this.t >= this.stagDur) { this.state = 'chase'; this.lead = P.pos.clone(); this.cd = 0.4; }
        break;
    }
    // separação do jogador e colisão com o mundo
    const ddx = this.pos.x - P.pos.x, ddz = this.pos.z - P.pos.z, dd = Math.hypot(ddx, ddz), minD = this.radius + P.radius;
    if (dd < minD && dd > 1e-4 && this.state !== 'active') { this.pos.x = P.pos.x + ddx / dd * minD; this.pos.z = P.pos.z + ddz / dd * minD; }
    resolveWorld(this.pos, this.radius);
    this.pos.y = groundY(this.pos.x, this.pos.z) + this.air;
    // pegadas e passos pesados: os dois denunciam o monstro
    if (this.air === 0 && Math.hypot(this.pos.x - this.lastTrack.x, this.pos.z - this.lastTrack.z) > 2) {
      this.lastTrack.copyFrom(this.pos); dropTrack(this.pos.x, this.pos.z, this.root.rotation.y);
      sfx('step', clamp(1 - dist / 45, 0, 1)); if (dist < 30) shake = Math.max(shake, 0.05 * (1 - dist / 30));
    }
    this.anim.flinch = this.state === 'stagger' ? -0.3 * Math.sin(Math.PI * clamp(this.t / this.stagDur, 0, 1)) : 0;
    this.anim.armsBusy = this.introPose || this.state === 'windup' || this.state === 'active' || this.state === 'recover';
    animateLimbs(this.h, moveSpeed, dt, this.anim);
  }
}
// tocas para onde o monstro foge, longe do jogador
const DENS = [[-17, -42], [18, -42], [-17, 42], [12, 42], [0, 48]];
let monster = null;
// floresta morta ("Forrest", kampsolutions, CC-BY-4.0)
async function loadForest() {
  const [forest, grid] = await Promise.all([
    BABYLON.SceneLoader.LoadAssetContainerAsync('assets/', 'forest.glb', scene),
    fetch('assets/forest_grid.json').then(r => r.json()),
  ]);
  forest.addAllToScene();
  forest.meshes.forEach(m => {
    if (!m.getTotalVertices()) return;
    m.isPickable = false; m.freezeWorldMatrix(); m.receiveShadows = true;
    if (m.material) { m.material.maxSimultaneousLights = 8; m.material.backFaceCulling = false; }   // o escaneamento é uma casca sem espessura
  });
  worldGrid = grid;
  addFarTrees();
  makeBonfire(0, -46, 'Clareira do Sul').setLit();
  makeBonfire(-14, 4, 'Tronco Caído').setLit();
  makeBonfire(15, 22, 'Fogueira do Norte').setLit();
  game.bonfire = bonfires[0];
  P.pos.set(2, groundY(2, -46), -46);
}
async function loadAssets() {
  try { knightAsset = await BABYLON.SceneLoader.LoadAssetContainerAsync('assets/', 'knight.glb', scene); }
  catch (err) { console.warn('knight.glb não carregou, usando o cavalo procedural', err); }
  try { await loadForest(); }
  catch (err) { console.error('a floresta não carregou', err); $('goText').textContent = 'ERRO AO CARREGAR A FLORESTA'; return; }
  try { bossAsset = await BABYLON.SceneLoader.LoadAssetContainerAsync('assets/', 'boss.glb', scene); }
  catch (err) { console.warn('boss.glb não carregou, o monstro usa o modelo do cavaleiro', err); }
  if (knightAsset) { // jogador também vira cavaleiro (azul)
    const old = P.root, k = buildKnight({ tint: [0.45, 0.6, 1.0] });
    k.shield = new BABYLON.TransformNode('shield', scene);
    k.root.position.copyFrom(old.position); k.root.rotation.y = old.rotation.y;
    old.getChildMeshes().forEach(m => m.dispose()); old.dispose();
    P.h = k; P.root = k.root; P.pos = k.root.position;
  }
  monster = new Enemy('boss', 0, 48); enemies.push(monster);
  buildNav(monster.radius);
  game.ready = true; $('goText').textContent = 'CLIQUE PARA COMEÇAR';
}
function monsterDefeated() { // chamado quando o monstro morre: inicia a cutscene de vitória
  const B = monster.pos.clone();
  const emb = new BABYLON.ParticleSystem('souls', 700, scene);
  emb.particleTexture = flareTex; emb.emitter = new V3(B.x, B.y + 0.3, B.z);
  emb.minEmitBox = new V3(-1.6, 0, -1.6); emb.maxEmitBox = new V3(1.6, 3.5, 1.6);
  emb.color1 = new BABYLON.Color4(1, 0.85, 0.4, 1); emb.color2 = new BABYLON.Color4(1, 0.4, 0.1, 1); emb.colorDead = new BABYLON.Color4(0.4, 0.1, 0, 0);
  emb.minSize = 0.08; emb.maxSize = 0.28; emb.minLifeTime = 2; emb.maxLifeTime = 4; emb.emitRate = 0;
  emb.direction1 = new V3(-0.4, 1.5, -0.4); emb.direction2 = new V3(0.4, 3, 0.4); emb.gravity = new V3(0, 0.6, 0);
  emb.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; emb.start();
  game.cut = {
    kind: 'death', t: 0, B, emb, impact: false, flashed: true, ember: false,
    a0: Math.atan2(P.pos.x - B.x, P.pos.z - B.z), startPos: camera.position.clone(), startTgt: camera.getTarget().clone(),
  };
  P.state = 'free'; P.atk = null; P.buf = null; P.blocking = false; game.lock = null;
  monster.introPose = true;
  if (monster.h.bossRig) monster.h.pose('Damage_Die', 0);
  else { if (monster.h.anim) monster.h.anim.goToFrame(42); monster.h.model.rotation.x = 0.12; }
  setEmissive(monster.h.mats, FLASH); sfx('hit'); shake = 0.7;
  $('boss').style.display = 'none';
  $('title').firstElementChild.textContent = 'MONSTRO ABATIDO'; $('title').lastElementChild.textContent = 'a caçada terminou';
  document.body.classList.add('cinematic');
}
function updateDeathCut(dt) {
  const c = game.cut; c.t += dt; const t = c.t, B = c.B, h = monster.h;
  if ((t > 1.0 && (pressed.Space || pressed.Enter || pressed.KeyE || pressed.M0)) || t >= 7.5) return endDeathCut();
  const sm = x => x * x * (3 - 2 * x);
  const kneel = sm(clamp((t - 0.35) / 2.2, 0, 1)), fall = Math.pow(clamp((t - 3.0) / 1.0, 0, 1), 2);
  if (h.bossRig) h.pose('Damage_Die', (t - 0.35) / 3.55);           // desaba e toca o chão em t = 3.9
  else { h.pivot.rotation.x = lerp(0, 0.35, kneel) + 1.15 * fall; h.pivot.position.y = 0.9 - 0.3 * kneel - 0.35 * fall; }
  if (t >= 0.35 && c.flashed) { c.flashed = false; setEmissive(h.mats, BLACK); }
  if (t >= 3.9 && !c.impact) { c.impact = true; burst(new V3(B.x, B.y + 0.4, B.z), 100); sfx('slam'); shake = Math.max(shake, 0.6); }
  if (t >= 4.0 && !c.ember) { c.ember = true; c.emb.emitRate = 260; }
  if (t >= 6.0) c.emb.emitRate = 0;
  if (t >= 4.2) { const v = clamp(1 - (t - 4.2) / 1.8, 0, 1); h.root.getChildMeshes().forEach(m => m.visibility = v); }
  if (t >= 5.0) $('title').classList.add('show');
  // camera: orbita lenta ao redor do chefe e depois plano geral
  const tt = Math.min(t, 6), ang = c.a0 + 0.35 * Math.max(tt - 0.35, 0), r = lerp(9, 6.5, tt / 6), y = lerp(1.8, 3.5, tt / 6);
  let pos = new V3(B.x + Math.sin(ang) * r, B.y + y, B.z + Math.cos(ang) * r);
  let tgt = new V3(B.x, B.y + lerp(2.4, 1.0, kneel * 0.5 + fall * 0.5), B.z);
  if (t < 1.2) { const k = sm(t / 1.2); pos = V3.Lerp(c.startPos, pos, k); tgt = V3.Lerp(c.startTgt, tgt, k); }
  if (shake > 0) { pos.x += (Math.random() - 0.5) * shake; pos.y += (Math.random() - 0.5) * shake; shake = Math.max(0, shake - dt * 1.2); }
  camera.position.copyFrom(pos); camera.setTarget(tgt);
}
function endDeathCut() {
  const c = game.cut; game.cut = null; c.emb.emitRate = 0;
  monster.root.setEnabled(false); monster.introPose = false;
  document.body.classList.remove('cinematic'); $('title').classList.remove('show');
  endHunt(true);
}
function endHunt(won) { // fim da caçada: quem caçou quem
  game.over = true; game.lock = null; $('death').classList.remove('show');
  try { document.exitPointerLock(); } catch (_) { }
  const t = Math.floor(game.huntTime), time = Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
  $('endT').textContent = won ? 'VOCÊ CAÇOU O MONSTRO' : 'O MONSTRO CAÇOU VOCÊ';
  $('endS').textContent = won ? 'Caçada concluída em ' + time : 'A vida dele ficou em ' + Math.ceil(monster.hp / monster.def.hp * 100) + '%  ·  ' + time + ' de caçada';
  $('end').className = 'show ' + (won ? 'won' : 'lost');
  sfx(won ? 'bonfire' : 'die');
}

/* ------------------------------ HUD ------------------------------ */
let msgTimer = 0;
function showMsg(text, cls, ms) {
  const m = $('msg'); m.textContent = text; m.className = 'show ' + cls;
  clearTimeout(msgTimer); msgTimer = setTimeout(() => m.classList.remove('show'), ms);
}
function updateHud() {
  $('hp').style.width = P.maxHp * 3 + 'px'; $('st').style.width = P.maxStamina * 2.6 + 'px';
  $('hp').firstElementChild.style.width = clamp(P.hp / P.maxHp, 0, 1) * 100 + '%';
  $('st').firstElementChild.style.width = clamp(P.stamina / P.maxStamina, 0, 1) * 100 + '%';
  $('estus').textContent = '⚱ Estus ' + P.estus + '/' + CONFIG.player.estusMax;
  $('livesN').textContent = '♥'.repeat(Math.max(P.lives, 0));
  const m = monster, live = m && !m.dead && game.started && !game.over;
  // barra de vida só quando ele está à vista
  $('boss').style.display = live && m.visible ? 'block' : 'none';
  if (live) {
    $('boss').firstElementChild.textContent = m.def.name;
    $('boss').querySelector('i').style.width = clamp(m.hp / m.def.hp, 0, 1) * 100 + '%';
    const chased = m.state === 'chase' || m.state === 'windup' || m.state === 'active' || m.state === 'recover' || m.state === 'stagger';
    const status = chased ? 'ELE ESTÁ TE CAÇANDO' : m.state === 'flee' ? 'ELE ESTÁ FUGINDO' : m.state === 'lurk' ? 'ELE ESTÁ ESCONDIDO' : m.aware > 0.25 ? 'ELE DESCONFIA DE VOCÊ' : 'ELE TE PROCURA';
    $('status').textContent = status; $('status').className = chased ? 'danger' : m.state === 'flee' || m.state === 'lurk' ? 'prey' : '';
  }
  // bússola: aponta para o último rugido ou avistamento
  const sign = game.sign, mk = $('mark'), SIGN_LIFE = 40;
  if (live && sign && sign.t < SIGN_LIFE) {
    const d = angDiff(cam.yaw, Math.atan2(sign.x - P.pos.x, sign.z - P.pos.z));
    mk.style.left = (50 + d / Math.PI * 50) + '%'; mk.style.opacity = 1 - sign.t / SIGN_LIFE;
    $('signD').textContent = 'rugido a ~' + Math.round(Math.hypot(sign.x - P.pos.x, sign.z - P.pos.z) / 5) * 5 + ' m';
  } else { mk.style.opacity = 0; $('signD').textContent = 'sem pista: procure pegadas'; }
  const lk = $('lock');
  if (game.lock) {
    const w = engine.getRenderWidth(), h = engine.getRenderHeight();
    const s = V3.Project(new V3(game.lock.pos.x, game.lock.pos.y + 1.4 * game.lock.def.scale, game.lock.pos.z), BABYLON.Matrix.Identity(), scene.getTransformMatrix(), camera.viewport.toGlobal(w, h));
    if (s.z > 0 && s.z < 1) { lk.style.display = 'block'; lk.style.left = s.x * canvas.clientWidth / w + 'px'; lk.style.top = s.y * canvas.clientHeight / h + 'px'; } else lk.style.display = 'none';
  } else lk.style.display = 'none';
}

/* ------------------------------ ações do jogador ------------------------------ */
function spend(n) { P.stamina = Math.max(0, P.stamina - n); P.staminaDelay = 0.9; }
function startRoll(dir) {
  spend(22); P.state = 'roll'; P.t = 0; P.blocking = false; P.rollDir.copyFrom(dir); P.atk = null;
  P.root.rotation.y = Math.atan2(dir.x, dir.z); sfx('roll');
}
function startAttack(kind) {
  let combo = 0;
  if (kind === 'light') { // encadeia se o golpe anterior também era leve
    const chain = CONFIG.player.combo;
    combo = P.state === 'attack' && P.atk && P.atk.combo !== undefined ? (P.atk.combo + 1) % chain.length : 0;
    kind = chain[combo];
  }
  const def = CONFIG.player[kind]; spend(def.stamina);
  P.state = 'attack'; P.t = 0; P.atk = { ...def, heavy: kind === 'heavy', hit: false, combo: kind === 'heavy' ? undefined : combo }; P.blocking = false;
  if (game.lock) P.root.rotation.y = Math.atan2(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z);
  else { // assistência de mira
    let best = null, bd = 4.5;
    for (const e of enemies) { if (e.dead || !e.root.isEnabled()) continue; const d = Math.hypot(e.pos.x - P.pos.x, e.pos.z - P.pos.z); if (d < bd) { bd = d; best = e; } }
    if (best) P.root.rotation.y = Math.atan2(best.pos.x - P.pos.x, best.pos.z - P.pos.z);
  }
  sfx('swing');
}
function playerStrike() {
  const a = P.atk, f = P.root.rotation.y;
  for (const e of enemies) {
    if (e.dead || !e.root.isEnabled()) continue;
    const dx = e.pos.x - P.pos.x, dz = e.pos.z - P.pos.z, d = Math.hypot(dx, dz);
    if (d < a.range + e.radius && Math.abs(angDiff(f, Math.atan2(dx, dz))) < a.arc) e.damage(a.dmg, a.heavy);
  }
}
function tryAction(act, mv) {
  if (act === 'roll' && P.stamina > 0) { startRoll(mv.len > 0 ? new V3(mv.x, 0, mv.z) : new V3(Math.sin(P.root.rotation.y), 0, Math.cos(P.root.rotation.y))); return true; }
  if ((act === 'light' || act === 'heavy') && P.stamina > 0) { startAttack(act); return true; }
  if (act === 'estus' && P.estus > 0 && P.hp < P.maxHp) { P.state = 'drink'; P.t = 0; P.healed = false; P.estus--; P.blocking = false; sfx('estus'); return true; }
  return false;
}

function updatePlayer(dt) {
  P.t += dt;
  if (P.staminaDelay > 0) P.staminaDelay -= dt; else if (P.state !== 'dead') P.stamina = Math.min(P.maxStamina, P.stamina + (P.blocking ? 14 : 32) * dt);
  if (P.flash > 0) P.flash -= dt;
  setEmissive(P.h.mats, P.flash > 0 ? FLASH : BLACK);

  const ix = (keys.KeyD ? 1 : 0) - (keys.KeyA ? 1 : 0), iz = (keys.KeyW ? 1 : 0) - (keys.KeyS ? 1 : 0);
  const sy = Math.sin(cam.yaw), cy = Math.cos(cam.yaw);
  let mx = ix * cy + iz * sy, mz = -ix * sy + iz * cy; const len = Math.hypot(mx, mz);
  if (len > 0) { mx /= len; mz /= len; }
  const mv = { x: mx, z: mz, len };

  if (pressed.Space) P.buf = { a: 'roll', t: 0.35 };
  if (pressed.M0) P.buf = { a: 'light', t: 0.4 };
  if (pressed.M2) P.buf = { a: 'heavy', t: 0.4 };
  if (pressed.KeyR) P.buf = { a: 'estus', t: 0.3 };
  if (P.buf && (P.buf.t -= dt) <= 0) P.buf = null;

  let speed = 0, armsBusy = false;
  P.h.shield.setEnabled(true);
  switch (P.state) {
    case 'free': {
      P.blocking = !!keys.KeyF && P.stamina > 0;
      if (P.buf && tryAction(P.buf.a, mv)) { P.buf = null; break; }
      const sprint = (keys.ShiftLeft || keys.ShiftRight) && len > 0 && P.stamina > 0 && !P.blocking;
      speed = len > 0 ? (P.blocking ? 2.2 : sprint ? CONFIG.player.sprint : CONFIG.player.walk) : 0;
      if (sprint) { P.stamina = Math.max(0, P.stamina - 14 * dt); P.staminaDelay = 0.4; }
      if (game.lock) P.root.rotation.y = turnToward(P.root.rotation.y, Math.atan2(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z), 12 * dt);
      else if (len > 0) P.root.rotation.y = turnToward(P.root.rotation.y, Math.atan2(mx, mz), 12 * dt);
      P.pos.x += mx * speed * dt; P.pos.z += mz * speed * dt;
      armsBusy = P.blocking; if (P.blocking) { P.h.lArm.rotation.x = -1.4; P.h.rArm.rotation.x = -0.6; }
      break;
    }
    case 'roll': {
      const D = 0.55, p = P.t / D;
      P.pos.x += P.rollDir.x * CONFIG.player.roll * (1 - 0.5 * p) * dt; P.pos.z += P.rollDir.z * CONFIG.player.roll * (1 - 0.5 * p) * dt;
      if (P.h.glb) P.h.anim.goToFrame(lerp(KNIGHT.roll.from, KNIGHT.roll.to, clamp(p, 0, 1))); // cambalhota com as juntas (Blender)
      else P.h.pivot.rotation.x = p * Math.PI * 2;
      armsBusy = true;
      if (P.t >= D) { P.state = 'free'; P.h.pivot.rotation.x = 0; }
      break;
    }
    case 'attack': {
      const a = P.atk, f = P.root.rotation.y, tW = a.windup, tA = tW + a.active, tR = tA + a.recover;
      armsBusy = true;
      const lunge = P.t < tA ? (a.heavy ? 3.5 : 2.5) : 0;
      P.pos.x += Math.sin(f) * lunge * dt; P.pos.z += Math.cos(f) * lunge * dt;
      if (P.t < tW) armPose(P.h, 'windup', P.t / tW, a);
      else if (P.t < tA) { if (!a.hit) { a.hit = true; playerStrike(); } armPose(P.h, 'active', (P.t - tW) / a.active, a); }
      else {
        armPose(P.h, 'recover', (P.t - tA) / a.recover, a);
        if (P.buf && (P.buf.a === 'roll' || (P.t - tA) > a.recover * 0.45)) { if (tryAction(P.buf.a, mv)) { P.buf = null; P.h.rArm.rotation.x = 0; break; } }
        if (P.t >= tR) { P.state = 'free'; P.h.rArm.rotation.x = 0; }
      }
      break;
    }
    case 'drink':
      speed = len > 0 ? 1.6 : 0; P.pos.x += mx * speed * dt; P.pos.z += mz * speed * dt; armsBusy = true;
      P.h.lArm.rotation.x = -2.2; P.h.rArm.rotation.x = 0;
      if (P.t > 0.5 && !P.healed) { P.healed = true; P.hp = Math.min(P.maxHp, P.hp + CONFIG.player.estusHeal); }
      if (P.t > 0.95) P.state = 'free';
      break;
    case 'stagger':
      armsBusy = true; P.h.pivot.rotation.x = Math.sin(P.t * 12) * 0.12; P.h.rArm.rotation.x = 0.4;
      if (P.t >= P.stagDur) { P.state = 'free'; P.h.pivot.rotation.x = 0; }
      break;
    case 'dead': {
      P.deadT += dt; const k = clamp(P.deadT * 3, 0, 1);
      P.h.pivot.rotation.x = lerp(0, 1.5, k); P.h.pivot.position.y = lerp(0.9, 0.25, k);
      if (P.deadT > 4) respawn();
      break;
    }
  }
  // escudo: costas quando solto, à frente quando defendendo
  if (P.blocking) { P.h.shield.position.set(0, 1.2, 0.45); P.h.shield.rotation.set(Math.PI / 2, 0, 0); }
  else { P.h.shield.position.set(0.15, 1.15, -0.28); P.h.shield.rotation.set(Math.PI / 2, 0, 0.25); }
  P.anim.armsBusy = P.h.glb ? P.state === 'attack' || P.state === 'roll' : armsBusy;
  P.anim.flinch = P.blocking ? 0.12 : 0;
  animateLimbs(P.h, speed, dt, P.anim);
  if (P.state !== 'dead') resolveWorld(P.pos, P.radius);
  P.pos.y = groundY(P.pos.x, P.pos.z);
  // barulho que o monstro pode ouvir (defendendo ou bebendo você se move em silêncio)
  const N = CONFIG.hunt.noise;
  P.noise = P.state === 'attack' || P.state === 'stagger' ? N.fight : P.state === 'roll' ? N.roll : speed > 5 ? N.sprint : speed > 3 ? N.walk : 0;
}

/* ------------------------------ interações / mundo ------------------------------ */
function updateWorld(dt, time) {
  let prompt = '';
  if (P.state === 'free') {
    for (const b of bonfires) {
      if (!b.lit || Math.hypot(P.pos.x - b.pos.x, P.pos.z - b.pos.z) >= 3) continue;
      prompt = `[E] Descansar — ${b.name}<br><small>recupera tudo, mas apaga a fogueira e atrai o monstro</small>`;
      if (pressed.KeyE) {
        sfx('bonfire'); showMsg('A FUMAÇA TE DENUNCIA', 'red', 2200);
        game.bonfire = b; b.putOut(); fullRest(); monster.lead = P.pos.clone();
      }
      break;
    }
  }
  $('prompt').innerHTML = prompt;
  if (game.sign) game.sign.t += dt;
  // coração acelera quando ele está perto
  const near = Math.hypot(monster.pos.x - P.pos.x, monster.pos.z - P.pos.z);
  if (near < 22 && (game.heartT = (game.heartT || 0) - dt) <= 0) { game.heartT = lerp(0.42, 1.1, near / 22); sfx('heart', 1 - near / 22); }
  bonfires.forEach(b => { if (b.lit) b.light.intensity = 1.5 + Math.sin(time * 17) * 0.15 + Math.random() * 0.15; });
}

function toggleLock() {
  if (game.lock) { game.lock = null; return; }
  const fx = Math.sin(cam.yaw), fz = Math.cos(cam.yaw);
  let best = null, bs = -1;
  for (const e of enemies) {
    if (e.dead || !e.root.isEnabled()) continue;
    const dx = e.pos.x - P.pos.x, dz = e.pos.z - P.pos.z, d = Math.hypot(dx, dz);
    if (d > 28 || !canSee(P.pos, e.pos)) continue;
    const dot = (dx * fx + dz * fz) / d; if (dot < 0.2) continue;
    const score = dot * 2 - d / 28; if (score > bs) { bs = score; best = e; }
  }
  game.lock = best;
}


function updateCamera(dt) {
  if (game.cut) { moon.position.set(P.pos.x + 30, 60, P.pos.z - 24); ash.emitter.set(P.pos.x, 2.5, P.pos.z); return; }
  if (keys.ArrowLeft) cam.yaw -= 2 * dt; if (keys.ArrowRight) cam.yaw += 2 * dt;
  if (game.lock) {
    if (game.lock.dead || Math.hypot(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z) > 32) game.lock = null;
    else { cam.yaw = turnToward(cam.yaw, Math.atan2(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z), 7 * dt); cam.pitch = lerp(cam.pitch, 0.32, 4 * dt); }
  }
  cam.dist = lerp(cam.dist, game.lock && game.lock.def.boss ? 11 : 6.5, 3 * dt);
  const piv = new V3(P.pos.x, P.pos.y + 1.7, P.pos.z), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
  const dir = new V3(Math.sin(cam.yaw) * cp, -sp, Math.cos(cam.yaw) * cp);
  let dist = cam.dist;
  for (let s = 1; s < cam.dist + 0.4; s += 0.25) if (trunkAt(piv.x - dir.x * s, piv.z - dir.z * s)) { dist = Math.max(1.2, s - 0.4); break; }
  cam.cur = dist < cam.cur ? dist : lerp(cam.cur, dist, 5 * dt);   // entra rápido, sai suave
  const pos = piv.subtract(dir.scale(cam.cur)); pos.y = Math.max(pos.y, groundY(pos.x, pos.z) + 0.5);
  if (shake > 0) { pos.x += (Math.random() - 0.5) * shake; pos.y += (Math.random() - 0.5) * shake; shake = Math.max(0, shake - dt * 1.6); }
  camera.position.copyFrom(pos); camera.setTarget(piv);
  moon.position.set(P.pos.x + 30, 60, P.pos.z - 24);
  ash.emitter.set(P.pos.x, 2.5, P.pos.z);
}

/* ------------------------------ entrada ------------------------------ */
addEventListener('keydown', e => {
  if (!e.repeat) { pressed[e.code] = true; if (e.code === 'KeyQ' && game.started) toggleLock(); }
  keys[e.code] = true; if (e.code === 'Space' || e.code === 'Tab' || e.code.startsWith('Arrow')) e.preventDefault();
});
addEventListener('keyup', e => { keys[e.code] = false; });
canvas.addEventListener('contextmenu', e => e.preventDefault());
canvas.addEventListener('pointerdown', e => {
  if (!game.started) return;
  if (document.pointerLockElement !== canvas) { try { Promise.resolve(canvas.requestPointerLock()).catch(() => {}); } catch (_) { } }
  pressed['M' + e.button] = true;
});
document.addEventListener('mousemove', e => {
  if (document.pointerLockElement !== canvas || game.lock) return;
  cam.yaw += e.movementX * 0.0023; cam.pitch = clamp(cam.pitch + e.movementY * 0.0023, -0.3, 1.2);
});
$('start').addEventListener('click', () => {
  if (!game.ready) return;
  game.started = true; $('start').style.display = 'none';
  try { ac = new (window.AudioContext || window.webkitAudioContext)(); } catch (_) { }
  try { Promise.resolve(canvas.requestPointerLock()).catch(() => {}); } catch (_) { }
  showMsg('CACE O MONSTRO', 'gold', 3000); monster.roar();
});
$('end').addEventListener('click', () => location.reload());
addEventListener('resize', () => engine.resize());

/* ------------------------------ loop ------------------------------ */
let clock = 0;
scene.onBeforeRenderObservable.add(() => {
  const dt = Math.min(engine.getDeltaTime() / 1000, 0.05); clock += dt;
  if (game.started && !game.over) {
    if (game.cut) updateDeathCut(dt); else { updatePlayer(dt); game.huntTime += dt; }
    enemies.forEach(e => e.update(dt));
    updateWorld(dt, clock);
    updateTracks(dt);
  }
  updateCamera(dt);
  updateHud();
  for (const k in pressed) pressed[k] = false;
});
engine.runRenderLoop(() => scene.render());
loadAssets();

// atalho de depuração para testes: window.__ks
window.__ks = { P, enemies, game, bonfires, CONFIG, NAV, get monster() { return monster; }, endHunt };
