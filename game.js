'use strict';
/* ======================================================================
   KELWIN SOULS — protótipo soulslike em Babylon.js
   Mexa no CONFIG abaixo para criar suas próprias alterações.
   ====================================================================== */

const CONFIG = {
  player: {
    maxHp: 100, maxStamina: 100, estusMax: 3, estusHeal: 55,
    walk: 4.2, sprint: 7.2, roll: 8.5,
    light:  { windup: 0.18, active: 0.12, recover: 0.30, stamina: 14, dmg: 22, range: 2.9 },
    heavy:  { windup: 0.50, active: 0.15, recover: 0.55, stamina: 30, dmg: 50, range: 3.3 },
  },
  levelUp: { baseCost: 100, costPerLevel: 60, hpPerLevel: 10, dmgPerLevel: 0.08 },
  enemies: {
    hollow: {
      name: 'Oco', hp: 60, speed: 3.1, souls: 40, scale: 1, aggro: 14, stopDist: 2.1,
      look: { tint: [0.62, 0.78, 0.55], skin: [0.55, 0.6, 0.5], armor: [0.25, 0.22, 0.2], eye: [1, 0.5, 0.1], weapon: 0.9 },
      attacks: [{ kind: 'melee', windup: 0.7, active: 0.15, recover: 0.8, range: 2.5, arc: 80, dmg: 20 }],
    },
    knight: {
      name: 'Cavaleiro Sombrio', hp: 150, speed: 2.5, souls: 150, scale: 1.18, aggro: 15, stopDist: 2.5,
      look: { tint: [0.55, 0.62, 1.0], skin: [0.3, 0.3, 0.35], armor: [0.12, 0.12, 0.18], eye: [0.3, 0.6, 1], weapon: 1.25 },
      attacks: [
        { kind: 'melee', windup: 0.65, active: 0.15, recover: 0.9, range: 3.0, arc: 80, dmg: 34 },
        { kind: 'melee', windup: 1.0, active: 0.15, recover: 1.1, range: 3.3, arc: 100, dmg: 48 },
      ],
    },
    boss: {
      name: 'Guardião das Cinzas', subtitle: 'Sentinela do Trono Esquecido', hp: 900, speed: 3.6, souls: 2500, scale: 2.5, boss: true, stopDist: 4.2,
      look: { tint: [1.0, 0.45, 0.4], skin: [0.35, 0.3, 0.28], armor: [0.2, 0.08, 0.08], eye: [1, 0.15, 0.1], weapon: 1.6, horns: true },
      attacks: [
        { kind: 'melee', windup: 0.8, active: 0.2, recover: 1.0, range: 5.0, arc: 120, dmg: 38, maxD: 5.5 },
        { kind: 'aoe',   windup: 1.2, active: 0.2, recover: 1.3, radius: 6.0, reach: 4.0, dmg: 55, maxD: 5.5 },
        { kind: 'leap',  windup: 0.9, active: 0.5, recover: 1.1, radius: 4.5, dmg: 50, minD: 9, maxD: 26 },
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
scene.fogDensity = 0.016;
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
};
function sfx(k) {
  if (!ac) return; const [type, f0, f1, dur, vol] = SFX[k], t = ac.currentTime;
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ac.destination); o.start(t); o.stop(t + dur);
}

/* ------------------------------ mundo ------------------------------ */
const ARENA = { x: 0, z: 61, r: 23 };
const obstacles = [];

// chão com textura procedural de pedra
const ground = BABYLON.MeshBuilder.CreateGround('ground', { width: 240, height: 240 }, scene);
{
  const gm = new BABYLON.StandardMaterial('gm', scene), tex = new BABYLON.DynamicTexture('gt', 512, scene, true), c = tex.getContext();
  c.fillStyle = '#4a4a4c'; c.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 900; i++) {
    const g = 50 + Math.floor(rnd() * 50); c.fillStyle = `rgba(${g},${g},${g + 4},0.35)`;
    c.beginPath(); c.arc(rnd() * 512, rnd() * 512, 6 + rnd() * 26, 0, 7); c.fill();
  }
  tex.update(); tex.uScale = tex.vScale = 30; gm.diffuseTexture = tex; gm.specularColor = new C3(0.02, 0.02, 0.02);
  gm.maxSimultaneousLights = 8; ground.material = gm; ground.receiveShadows = true;
}
const arenaFloor = BABYLON.MeshBuilder.CreateDisc('arena', { radius: ARENA.r, tessellation: 64 }, scene);
arenaFloor.rotation.x = Math.PI / 2; arenaFloor.position.set(ARENA.x, 0.02, ARENA.z);
const runeTex = (() => {
  const t = new BABYLON.DynamicTexture('runes', 1024, scene, true), c = t.getContext(), R = 512;
  c.fillStyle = '#000'; c.fillRect(0, 0, 1024, 1024); c.translate(R, R);
  c.strokeStyle = '#ff5a1f'; c.lineCap = 'round';
  const ring = (r, w) => { c.lineWidth = w; c.beginPath(); c.arc(0, 0, r, 0, 7); c.stroke(); };
  ring(498, 6); ring(470, 3); ring(330, 5); ring(318, 2); ring(150, 4);
  for (let i = 0; i < 48; i++) { // marcas entre os aneis externos
    c.save(); c.rotate(i / 48 * Math.PI * 2); c.lineWidth = 3; c.beginPath(); c.moveTo(0, -470); c.lineTo(0, -498); c.stroke(); c.restore();
  }
  for (let i = 0; i < 12; i++) { // glifos entre os aneis 330 e 470
    c.save(); c.rotate(i / 12 * Math.PI * 2); c.lineWidth = 4; const y = -400;
    c.beginPath(); c.moveTo(-16, y + 26); c.lineTo(0, y - 28); c.lineTo(16, y + 26); c.moveTo(-22, y + 4); c.lineTo(22, y + 4);
    if (i % 3 === 0) { c.moveTo(0, y - 28); c.lineTo(0, y - 46); }
    c.stroke(); c.restore();
  }
  c.lineWidth = 4; for (const off of [0, Math.PI / 6]) { // sigilo central: duas estrelas de 6 pontas
    c.beginPath(); for (let i = 0; i <= 6; i++) { const a = off + i / 3 * Math.PI * 2 - Math.PI / 2; c.lineTo(Math.cos(a) * 300, Math.sin(a) * 300); } c.stroke();
  }
  c.lineWidth = 6; c.beginPath(); c.arc(0, 0, 40, 0, 7); c.stroke(); c.fillStyle = '#ff5a1f'; c.beginPath(); c.arc(0, 0, 14, 0, 7); c.fill();
  t.update(); return t;
})();
{
  const m = mat([0.13, 0.12, 0.12]); m.emissiveTexture = runeTex; runeTex.level = 0.25; m.backFaceCulling = false;
  arenaFloor.material = m; arenaFloor.receiveShadows = true;
}

// pilares / ruínas
const pillarMat = mat([0.55, 0.55, 0.58]);
{
  const t = new BABYLON.DynamicTexture('stoneT', 256, scene, true), c = t.getContext();
  c.fillStyle = '#4c4c50'; c.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 40; i++) { c.fillStyle = `rgba(20,20,24,${0.15 + Math.random() * 0.2})`; c.fillRect(0, Math.random() * 256, 256, 1 + Math.random() * 3); }       // juntas/estrias
  for (let i = 0; i < 300; i++) { const g = 60 + Math.random() * 40; c.fillStyle = `rgba(${g},${g + 4},${g},0.3)`; c.beginPath(); c.arc(Math.random() * 256, Math.random() * 256, 2 + Math.random() * 10, 0, 7); c.fill(); }
  for (let i = 0; i < 120; i++) { c.fillStyle = 'rgba(40,70,35,0.22)'; c.beginPath(); c.arc(Math.random() * 256, 170 + Math.random() * 86, 3 + Math.random() * 12, 0, 7); c.fill(); } // musgo na base
  t.update(); t.uScale = 2; t.vScale = 3; pillarMat.diffuseTexture = t;
}
function addPillar(x, z, r, h, tilt) {
  const p = BABYLON.MeshBuilder.CreateCylinder('pillar', { diameter: r * 2, height: h, tessellation: 10 }, scene);
  p.position.set(x, h / 2, z); p.material = pillarMat; if (tilt) p.rotation.z = tilt; sg.addShadowCaster(p); p.receiveShadows = true;
  obstacles.push({ x, z, r: r * 0.95 });
}
const keepClear = [[0, 0, 7], [0, 24, 7], [0, 36, 8]];
for (let i = 0; i < 46; i++) {
  const x = (rnd() - 0.5) * 120, z = -50 + rnd() * 84;
  if (keepClear.some(([a, b, r]) => Math.hypot(x - a, z - b) < r)) continue;
  addPillar(x, z, 0.7 + rnd() * 0.5, 3 + rnd() * 6, rnd() < 0.2 ? (rnd() - 0.5) * 0.25 : 0);
}
// muralha com a névoa no meio
for (let x = -60; x <= 60; x += 2.6) { if (Math.abs(x) < 6) continue; addPillar(x, 36, 1.35, 8 + rnd() * 2); }
// anel de pilares da arena
for (let a = 0; a < 360; a += 24) {
  const rad = a * Math.PI / 180, dx = Math.sin(rad), dz = -Math.cos(rad);
  if (dz < -0.8) continue;
  const px = ARENA.x + dx * (ARENA.r + 1.5), pz = ARENA.z + dz * (ARENA.r + 1.5);
  addPillar(px, pz, 1.2, 10 + rnd() * 3);
}

// ---- decoracao da arena do chefe ----
const arenaLight = new BABYLON.PointLight('arenaL', new V3(ARENA.x, 7, ARENA.z), scene);
arenaLight.diffuse = new C3(1, 0.3, 0.15); arenaLight.range = 45; arenaLight.intensity = 0.3;
const braziers = [];
{
  const stone = mat([0.2, 0.2, 0.22]), cloth = mat([0.35, 0.05, 0.06], [0.08, 0.0, 0.0]); cloth.backFaceCulling = false;
  const clothTex = new BABYLON.DynamicTexture('banner', { width: 64, height: 256 }, scene, true), bc = clothTex.getContext();
  bc.fillStyle = '#4a0a0d'; bc.fillRect(0, 0, 64, 256); bc.fillStyle = '#b8964a'; bc.fillRect(4, 0, 3, 256); bc.fillRect(57, 0, 3, 256);
  bc.strokeStyle = '#b8964a'; bc.lineWidth = 3; bc.beginPath(); bc.arc(32, 90, 14, 0, 7); bc.moveTo(32, 60); bc.lineTo(32, 150); bc.moveTo(14, 110); bc.lineTo(50, 110); bc.stroke();
  clothTex.update(); cloth.diffuseTexture = clothTex; cloth.emissiveColor = new C3(0.12, 0.02, 0.02);
  for (let a = 0; a < 360; a += 24) {
    const rad = a * Math.PI / 180, dx = Math.sin(rad), dz = -Math.cos(rad);
    if (dz < -0.8) continue;
    if (a % 48 === 0) { // estandarte voltado para o centro
      const b = BABYLON.MeshBuilder.CreatePlane('banner', { width: 2.6, height: 8 }, scene);
      const r = ARENA.r + 0.3; b.position.set(ARENA.x + dx * r, 6.5, ARENA.z + dz * r); b.rotation.y = Math.atan2(dx, dz); b.material = cloth;
    } else if (dz > -0.5) { // braseiro entre os pilares
      const r = ARENA.r - 2.5, x = ARENA.x + dx * r, z = ARENA.z + dz * r;
      const base = BABYLON.MeshBuilder.CreateCylinder('brb', { diameterTop: 0.5, diameterBottom: 0.9, height: 1.3 }, scene); base.position.set(x, 0.65, z); base.material = stone;
      const bowl = BABYLON.MeshBuilder.CreateCylinder('brw', { diameterTop: 1.3, diameterBottom: 0.6, height: 0.4 }, scene); bowl.position.set(x, 1.5, z); bowl.material = stone;
      sg.addShadowCaster(base);
      obstacles.push({ x, z, r: 0.5 });
      const ps = new BABYLON.ParticleSystem('brazier', 150, scene);
      ps.particleTexture = flareTex; ps.emitter = new V3(x, 1.7, z); ps.minEmitBox = new V3(-0.25, 0, -0.25); ps.maxEmitBox = new V3(0.25, 0, 0.25);
      ps.color1 = new BABYLON.Color4(1, 0.55, 0.15, 1); ps.color2 = new BABYLON.Color4(1, 0.25, 0.05, 1); ps.colorDead = new BABYLON.Color4(0.3, 0, 0, 0);
      ps.minSize = 0.3; ps.maxSize = 0.8; ps.minLifeTime = 0.4; ps.maxLifeTime = 1.2; ps.emitRate = 0;
      ps.direction1 = new V3(-0.2, 1, -0.2); ps.direction2 = new V3(0.2, 2, 0.2); ps.gravity = new V3(0, 2, 0); ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; ps.start();
      braziers.push(ps);
    }
  }
  // trono ao fundo
  const dark = mat([0.12, 0.11, 0.13], [0.03, 0.0, 0.0]), tz = ARENA.z + ARENA.r - 3.5;
  const tb = (w, h, d, x, y, z) => { const b = BABYLON.MeshBuilder.CreateBox('throne', { width: w, height: h, depth: d }, scene); b.position.set(x, y, z); b.material = dark; sg.addShadowCaster(b); return b; };
  tb(9, 0.5, 6, 0, 0.25, tz); tb(7, 0.5, 4.6, 0, 0.75, tz + 0.2);               // degraus
  tb(3.6, 1.0, 2.6, 0, 1.5, tz + 0.6); tb(4.2, 8, 1.0, 0, 5.0, tz + 1.9);        // assento e encosto
  tb(0.8, 2.2, 2.6, -2.2, 2.1, tz + 0.6); tb(0.8, 2.2, 2.6, 2.2, 2.1, tz + 0.6); // bracos
  for (const x of [-1.6, 0, 1.6]) { const sp = BABYLON.MeshBuilder.CreateCylinder('spike', { diameterTop: 0, diameterBottom: 0.9, height: x === 0 ? 3.2 : 2.2, tessellation: 4 }, scene); sp.position.set(x, 9 + (x === 0 ? 1.6 : 1.1), tz + 1.9); sp.material = dark; }
  obstacles.push({ x: 0, z: tz + 0.8, r: 2.4 }, { x: -2.2, z: tz + 0.6, r: 1.0 }, { x: 2.2, z: tz + 0.6, r: 1.0 });
}
// clima da arena: 'idle' | 'fight' | 'dead'
let arenaMood = 'idle';
function setArenaMood(m) {
  arenaMood = m;
  braziers.forEach(ps => {
    ps.emitRate = m === 'fight' ? 120 : m === 'idle' ? 28 : 0;
    ps.color1 = m === 'fight' ? new BABYLON.Color4(1, 0.25, 0.05, 1) : new BABYLON.Color4(1, 0.55, 0.15, 1);
  });
}
setArenaMood('idle');

function resolveWorld(p, r) {
  for (const o of obstacles) {
    const dx = p.x - o.x, dz = p.z - o.z, d = Math.hypot(dx, dz), min = o.r + r;
    if (d < min && d > 1e-4) { p.x = o.x + dx / d * min; p.z = o.z + dz / d * min; }
  }
  if (p.z > ARENA.z - ARENA.r) {
    const dx = p.x - ARENA.x, dz = p.z - ARENA.z, d = Math.hypot(dx, dz), max = ARENA.r - r;
    if (d > max) { p.x = ARENA.x + dx / d * max; p.z = ARENA.z + dz / d * max; }
  } else { p.x = clamp(p.x, -70, 70); p.z = clamp(p.z, -60, ARENA.z - ARENA.r); }
}

// névoa
const fogGate = BABYLON.MeshBuilder.CreatePlane('fog', { width: 12, height: 8 }, scene);
fogGate.position.set(0, 4, 37.2);
{ const m = mat([0.8, 0.85, 1], [0.5, 0.55, 0.7]); m.alpha = 0.35; m.backFaceCulling = false; fogGate.material = m; }

// fogueiras
const bonfires = [];
function makeBonfire(x, z, name) {
  const ash = BABYLON.MeshBuilder.CreateCylinder('ash', { diameterTop: 1.0, diameterBottom: 1.8, height: 0.4 }, scene);
  ash.position.set(x, 0.2, z); ash.material = mat([0.1, 0.09, 0.08]);
  const blade = BABYLON.MeshBuilder.CreateBox('coil', { width: 0.08, height: 1.9, depth: 0.2 }, scene);
  blade.position.set(x, 1.1, z); blade.rotation.z = 0.08; blade.material = mat([0.7, 0.7, 0.75], [0.15, 0.15, 0.15]);
  const light = new BABYLON.PointLight('fl', new V3(x, 1.5, z), scene);
  light.diffuse = new C3(1, 0.55, 0.2); light.intensity = 0; light.range = 28;
  const ps = new BABYLON.ParticleSystem('fire', 250, scene);
  ps.particleTexture = flareTex; ps.emitter = new V3(x, 0.45, z);
  ps.minEmitBox = new V3(-0.25, 0, -0.25); ps.maxEmitBox = new V3(0.25, 0, 0.25);
  ps.color1 = new BABYLON.Color4(1, 0.6, 0.1, 1); ps.color2 = new BABYLON.Color4(1, 0.3, 0, 1); ps.colorDead = new BABYLON.Color4(0.3, 0, 0, 0);
  ps.minSize = 0.3; ps.maxSize = 0.75; ps.minLifeTime = 0.4; ps.maxLifeTime = 1.1; ps.emitRate = 0;
  ps.direction1 = new V3(-0.3, 1, -0.3); ps.direction2 = new V3(0.3, 2, 0.3); ps.gravity = new V3(0, 2, 0);
  ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD; ps.start();
  const b = { pos: new V3(x, 0, z), name, lit: false, light, ps };
  b.setLit = () => { b.lit = true; light.intensity = 1.6; ps.emitRate = 90; };
  bonfires.push(b); return b;
}
makeBonfire(0, 0, 'Santuário Inicial').setLit();
makeBonfire(0, 24, 'Antes da Muralha');

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
let knightAsset = null;
const KNIGHT = { scale: 0.16, facing: 0, idleFrom: 130, idleTo: 350 };   // frames da animação "Take 001"
function buildKnight(o) {
  const root = new BABYLON.TransformNode('ent', scene);
  const pivot = new BABYLON.TransformNode('pv', scene); pivot.parent = root; pivot.position.y = 0.9;
  const model = new BABYLON.TransformNode('md', scene); model.parent = pivot; model.position.y = -0.9;
  const wrap = new BABYLON.TransformNode('wrap', scene); wrap.parent = model; wrap.scaling.setAll(KNIGHT.scale); wrap.rotation.y = KNIGHT.facing;
  const inst = knightAsset.instantiateModelsToScene(n => n, true);
  inst.rootNodes[0].parent = wrap;
  const meshes = inst.rootNodes[0].getChildMeshes(), mats = [];
  meshes.forEach(m => {
    m.alwaysSelectAsActiveMesh = true;
    if (m.material && !mats.includes(m.material)) { m.material.maxSimultaneousLights = 8; mats.push(m.material); if (o.tint) m.material.albedoColor = new C3(o.tint[0], o.tint[1], o.tint[2]); }
  });
  const anim = inst.animationGroups[0]; anim.start(false, 1, 0, 0); anim.pause();
  shadowCast(root);
  const dummy = () => new BABYLON.TransformNode('j', scene);
  return { root, pivot, model, rArm: dummy(), lArm: dummy(), legL: dummy(), legR: dummy(), mats, glb: true, anim };
}
const BLACK = new C3(0, 0, 0), FLASH = new C3(0.75, 0.15, 0.1), RAGE = new C3(0.35, 0, 0);
const setEmissive = (mats, c) => mats.forEach(m => m.emissiveColor = c);
function animateLimbs(h, speed, dt, o) {
  o.phase = (o.phase || 0) + speed * dt * 1.5;
  if (h.glb) { // cavaleiro: respira (idle) e desliza com leve inclinação
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
function armPose(h, stage, p, raise = -3.2, strike = -1.1) {
  if (h.glb) { // quadros da animação: 0-30 ergue, 30-42 golpe, 42-130 recupera
    h.anim.goToFrame(stage === 'windup' ? lerp(0, 30, p) : stage === 'active' ? lerp(30, 42, p) : lerp(42, 130, p));
    h.model.rotation.x = stage === 'active' ? 0.12 : 0; return;
  }
  if (h.chess) { // cavalo: empina para trás e investe com a cabeça
    const k = stage === 'windup' ? -easeOut(p) : stage === 'active' ? lerp(-1, 1, p) : lerp(1, 0, p * p * (3 - 2 * p));
    h.rArm.rotation.x = k * 0.8; h.model.rotation.x = k * 0.3; return;
  }
  if (stage === 'windup') h.rArm.rotation.x = lerp(0, raise, easeOut(p));
  else if (stage === 'active') h.rArm.rotation.x = lerp(raise, strike, p);
  else h.rArm.rotation.x = lerp(strike, 0, p * p * (3 - 2 * p));
}

/* ------------------------------ estado do jogo ------------------------------ */
const game = {
  started: false, bossFight: false, bossDefeated: false, gateOpen: false,
  lock: null, bonfire: bonfires[0], stain: null,
};
const keys = {}, pressed = {};
const cam = { yaw: 0, pitch: 0.35, dist: 6.5 };
let shake = 0;

/* ------------------------------ jogador ------------------------------ */
const P = (() => {
  const h = buildHumanoid({ skin: [0.7, 0.55, 0.45], armor: [0.3, 0.32, 0.38], eye: [0.9, 0.9, 1], weapon: 1.1, shield: true });
  h.shield.position.set(0.52, 1.1, -0.1);
  return {
    h, root: h.root, pos: h.root.position, radius: 0.5,
    maxHp: CONFIG.player.maxHp, hp: CONFIG.player.maxHp, maxStamina: CONFIG.player.maxStamina, stamina: CONFIG.player.maxStamina,
    estus: CONFIG.player.estusMax, souls: 0, level: 1, dmgMult: 1,
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
    burst(new V3(P.pos.x, 1.3, P.pos.z), 10);
    if (P.stamina > 0) { P.hp -= dmg * 0.12; sfx('block'); updateDeath(); return true; }
    P.stamina = 0; dmg *= 0.6; staggerPlayer(0.8); sfx('hurt');          // guarda quebrada
  } else { staggerPlayer(0.4); sfx('hurt'); }
  P.hp -= dmg; P.flash = 0.15;
  const away = Math.atan2(P.pos.x - from.x, P.pos.z - from.z);
  P.pos.x += Math.sin(away) * 0.4; P.pos.z += Math.cos(away) * 0.4;
  burst(new V3(P.pos.x, 1.3, P.pos.z), 14);
  updateDeath(); return true;
}
function staggerPlayer(d) { P.state = 'stagger'; P.t = 0; P.stagDur = d; P.atk = null; P.h.pivot.rotation.x = 0; }
function updateDeath() { if (P.hp <= 0 && P.state !== 'dead') killPlayer(); }
function killPlayer() {
  P.hp = 0; P.state = 'dead'; P.deadT = 0; sfx('die'); game.lock = null;
  if (game.stain) { game.stain.mesh.dispose(); game.stain = null; }
  if (P.souls > 0) {
    const m = BABYLON.MeshBuilder.CreateSphere('stain', { diameter: 0.7 }, scene);
    m.position.set(P.pos.x, 0.8, P.pos.z); m.material = mat([1, 0.85, 0.4], [1, 0.8, 0.3]);
    game.stain = { mesh: m, souls: P.souls }; P.souls = 0;
  }
  $('death').classList.add('show');
}
function respawn() {
  $('death').classList.remove('show');
  const b = game.bonfire;
  P.pos.set(b.pos.x + 2, 0, b.pos.z); P.root.rotation.y = 0;
  fullRest(); resetEnemies(); P.state = 'free'; P.h.pivot.rotation.x = 0; P.h.pivot.position.y = 0.9;
}
function fullRest() { P.hp = P.maxHp; P.stamina = P.maxStamina; P.estus = CONFIG.player.estusMax; }

/* ------------------------------ inimigos ------------------------------ */
const enemies = [];
class Enemy {
  constructor(type, x, z) {
    this.type = type; this.def = CONFIG.enemies[type]; this.home = new V3(x, 0, z);
    this.h = knightAsset ? buildKnight(this.def.look) : buildChessKnight(this.def.look); this.root = this.h.root; this.root.scaling.setAll(this.def.scale);
    this.pos = this.root.position; this.radius = 0.5 * this.def.scale; this.anim = {};
    if (this.def.attacks.some(a => a.kind === 'aoe' || a.kind === 'leap')) {
      this.ring = BABYLON.MeshBuilder.CreateDisc('ring', { radius: 1, tessellation: 48 }, scene);
      this.ring.rotation.x = Math.PI / 2; this.ring.position.y = 0.06;
      const rm = mat([0.8, 0.1, 0.05], [0.8, 0.1, 0.05]); rm.alpha = 0.35; rm.backFaceCulling = false; this.ring.material = rm;
    }
    this.reset();
  }
  reset() {
    if (this.permaDead) return;
    this.hp = this.def.hp; this.state = 'idle'; this.t = 0; this.dead = false; this.deadT = 0; this.cd = 1; this.phase = 1;
    this.atk = null; this.flash = 0; this.introPose = false; this.strafe = Math.random() < 0.5 ? 1 : -1;
    this.pos.copyFrom(this.home); this.root.rotation.y = this.def.boss ? Math.PI : rnd() * 6.28;
    this.root.setEnabled(true); this.h.pivot.rotation.x = 0; this.h.pivot.position.y = 0.9;
    this.h.rArm.rotation.x = 0; if (this.ring) this.ring.setEnabled(false);
  }
  get spd() { return this.def.speed * (this.phase === 2 ? 1.25 : 1); }
  damage(amount, heavy) {
    if (this.dead) return;
    this.hp -= amount; this.flash = 0.12; sfx('hit');
    burst(new V3(this.pos.x, 1.4 * this.def.scale, this.pos.z), 16);
    if (this.state === 'idle') this.state = 'chase';
    if (this.def.boss) {
      if (this.phase === 1 && this.hp > 0 && this.hp < this.def.hp / 2) { this.phase = 2; showMsg('O GUARDIÃO ENFURECE', 'red', 2200); }
    } else if (this.state !== 'active' && (heavy || this.state === 'windup' || Math.random() < 0.35)) {
      this.state = 'stagger'; this.t = 0; this.stagDur = heavy ? 0.9 : 0.45; this.atk = null;
      this.h.rArm.rotation.x = 0; this.hideRing();
      const a = Math.atan2(this.pos.x - P.pos.x, this.pos.z - P.pos.z);
      this.pos.x += Math.sin(a) * 0.6; this.pos.z += Math.cos(a) * 0.6;
    }
    if (this.hp <= 0) this.die();
  }
  die() {
    this.dead = true; this.deadT = 0; this.hideRing(); P.souls += this.def.souls;
    if (game.lock === this) game.lock = null;
    if (this.def.boss) bossDefeated();
  }
  hideRing() { if (this.ring) this.ring.setEnabled(false); }
  startAttack(a) { this.atk = a; this.state = 'windup'; this.t = 0; this.windDur = a.windup * (this.phase === 2 ? 0.8 : 1); }
  strike() {
    const a = this.atk, f = this.root.rotation.y, dx = P.pos.x - this.pos.x, dz = P.pos.z - this.pos.z, d = Math.hypot(dx, dz);
    if (a.kind === 'melee') {
      const inArc = Math.abs(angDiff(f, Math.atan2(dx, dz))) < (a.arc / 2) * Math.PI / 180;
      if (d < a.range + 0.4 && inArc) hurtPlayer(a.dmg, this.pos);
    } else {
      const c = a.kind === 'aoe' ? new V3(this.pos.x + Math.sin(f) * a.reach, 0, this.pos.z + Math.cos(f) * a.reach) : this.pos;
      burst(new V3(c.x, 0.3, c.z), 60); sfx('slam'); shake = Math.max(shake, a.kind === 'leap' ? 0.7 : 0.5);
      if (Math.hypot(P.pos.x - c.x, P.pos.z - c.z) < a.radius) hurtPlayer(a.dmg, c);
    }
  }
  update(dt) {
    if (this.dead) {
      if (this.def.boss) return;
      this.deadT += dt; const k = clamp(this.deadT * 3, 0, 1);
      this.h.pivot.rotation.x = lerp(0, 1.5, k); this.h.pivot.position.y = lerp(0.9, 0.25, k);
      if (this.deadT > 3) { this.root.setEnabled(false); if (this.def.boss) this.permaDead = true; }
      return;
    }
    if (this.flash > 0) this.flash -= dt;
    setEmissive(this.h.mats, this.flash > 0 ? FLASH : this.phase === 2 ? RAGE : BLACK);
    const dx = P.pos.x - this.pos.x, dz = P.pos.z - this.pos.z, dist = Math.hypot(dx, dz), want = Math.atan2(dx, dz);
    const alive = P.state !== 'dead';
    let moveSpeed = 0;
    if (this.cd > 0) this.cd -= dt;
    switch (this.state) {
      case 'idle':
        if (alive && (this.def.boss ? game.bossFight : dist < this.def.aggro)) this.state = 'chase';
        break;
      case 'chase': {
        if (!alive) { this.state = 'idle'; break; }
        this.root.rotation.y = turnToward(this.root.rotation.y, want, 4.5 * dt);
        const f = this.root.rotation.y;
        if (this.cd <= 0) {
          const opts = this.def.attacks.filter(a => dist >= (a.minD || 0) && dist <= (a.maxD || a.range + 0.5));
          if (opts.length) { this.startAttack(opts[Math.floor(Math.random() * opts.length)]); break; }
        }
        if (dist > this.def.stopDist) { moveSpeed = this.spd; }
        else if (dist < this.def.stopDist - 0.6) { moveSpeed = -this.spd * 0.5; }
        else { // circula esperando a recarga
          this.pos.x += Math.cos(f) * this.strafe * this.spd * 0.35 * dt; this.pos.z -= Math.sin(f) * this.strafe * this.spd * 0.35 * dt; moveSpeed = this.spd * 0.35;
        }
        this.pos.x += Math.sin(f) * moveSpeed * dt; this.pos.z += Math.cos(f) * moveSpeed * dt;
        break;
      }
      case 'windup': {
        this.t += dt; const p = clamp(this.t / this.windDur, 0, 1), a = this.atk;
        if (this.t < this.windDur * 0.6) this.root.rotation.y = turnToward(this.root.rotation.y, want, (this.def.boss ? 3 : 2.2) * dt);
        armPose(this.h, 'windup', p);
        if (this.ring) {
          const f = this.root.rotation.y;
          if (a.kind === 'aoe') { this.ring.setEnabled(true); this.ring.scaling.setAll(a.radius); this.ring.position.x = this.pos.x + Math.sin(f) * a.reach; this.ring.position.z = this.pos.z + Math.cos(f) * a.reach; }
          else if (a.kind === 'leap') { this.ring.setEnabled(true); this.ring.scaling.setAll(a.radius); this.ring.position.x = P.pos.x; this.ring.position.z = P.pos.z; }
        }
        if (this.t >= this.windDur) {
          this.state = 'active'; this.t = 0;
          if (a.kind === 'leap') { this.leapFrom = this.pos.clone(); const d = Math.max(dist - 1.5, 0); this.leapTo = new V3(this.pos.x + Math.sin(want) * d, 0, this.pos.z + Math.cos(want) * d); this.root.rotation.y = want; }
          else this.strike();
        }
        break;
      }
      case 'active': {
        this.t += dt; const a = this.atk, p = clamp(this.t / a.active, 0, 1);
        armPose(this.h, 'active', p);
        if (a.kind === 'leap') {
          this.pos.x = lerp(this.leapFrom.x, this.leapTo.x, p); this.pos.z = lerp(this.leapFrom.z, this.leapTo.z, p);
          this.pos.y = Math.sin(p * Math.PI) * 4;
        }
        if (this.t >= a.active) {
          if (a.kind === 'leap') { this.pos.y = 0; this.strike(); }
          this.hideRing(); this.state = 'recover'; this.t = 0;
        }
        break;
      }
      case 'recover': {
        this.t += dt; const a = this.atk, r = a.recover * (this.phase === 2 ? 0.75 : 1);
        armPose(this.h, 'recover', clamp(this.t / r, 0, 1));
        if (this.t >= r) { this.state = 'chase'; this.cd = (0.3 + Math.random() * 0.7) * (this.phase === 2 ? 0.6 : 1); this.strafe = Math.random() < 0.5 ? 1 : -1; }
        break;
      }
      case 'stagger':
        this.t += dt; if (this.t >= this.stagDur) { this.state = 'chase'; this.cd = 0.4; }
        break;
    }
    // separação do jogador e colisão com o mundo
    const ddx = this.pos.x - P.pos.x, ddz = this.pos.z - P.pos.z, dd = Math.hypot(ddx, ddz), minD = this.radius + P.radius;
    if (dd < minD && dd > 1e-4 && this.state !== 'active') { this.pos.x = P.pos.x + ddx / dd * minD; this.pos.z = P.pos.z + ddz / dd * minD; }
    resolveWorld(this.pos, this.radius);
    this.anim.flinch = this.state === 'stagger' ? -0.3 * Math.sin(Math.PI * clamp(this.t / this.stagDur, 0, 1)) : 0;
    this.anim.armsBusy = this.introPose || this.state === 'windup' || this.state === 'active' || this.state === 'recover';
    animateLimbs(this.h, Math.abs(moveSpeed), dt, this.anim);
  }
}
const SPAWNS = [
  ['hollow', 8, 10], ['hollow', -9, 12], ['hollow', 16, 5], ['hollow', -17, 6], ['hollow', 10, 18], ['hollow', -12, 20],
  ['knight', 14, 29], ['knight', -14, 29], ['boss', 0, 66],
];
let boss = null;
async function loadAssets() {
  try { knightAsset = await BABYLON.SceneLoader.LoadAssetContainerAsync('assets/', 'knight.glb', scene); }
  catch (err) { console.warn('knight.glb não carregou, usando o cavalo procedural', err); }
  if (knightAsset) { // jogador também vira cavaleiro (azul)
    const old = P.root, k = buildKnight({ tint: [0.45, 0.6, 1.0] });
    k.shield = new BABYLON.TransformNode('shield', scene);
    k.root.position.copyFrom(old.position); k.root.rotation.y = old.rotation.y;
    old.getChildMeshes().forEach(m => m.dispose()); old.dispose();
    P.h = k; P.root = k.root; P.pos = k.root.position;
  }
  SPAWNS.forEach(([t, x, z]) => enemies.push(new Enemy(t, x, z)));
  boss = enemies.find(e => e.def.boss);
  game.ready = true; $('goText').textContent = 'CLIQUE PARA COMEÇAR';
}
function resetEnemies() {
  enemies.forEach(e => e.reset()); game.bossFight = false; if (!game.bossDefeated) setArenaMood('idle'); $('boss').style.display = 'none';
}
function bossDefeated() { // chamado quando o chefe morre: inicia a cutscene
  game.bossDefeated = true;
  const B = boss.pos.clone();
  const emb = new BABYLON.ParticleSystem('souls', 700, scene);
  emb.particleTexture = flareTex; emb.emitter = new V3(B.x, 0.3, B.z);
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
  boss.introPose = true; if (boss.h.anim) boss.h.anim.goToFrame(42); boss.h.model.rotation.x = 0.12;
  setEmissive(boss.h.mats, FLASH); sfx('hit'); shake = 0.7;
  $('boss').style.display = 'none';
  $('title').firstElementChild.textContent = 'INIMIGO ABATIDO'; $('title').lastElementChild.textContent = '+' + boss.def.souls + ' almas';
  document.body.classList.add('cinematic');
}
function updateDeathCut(dt) {
  const c = game.cut; c.t += dt; const t = c.t, B = c.B, h = boss.h;
  if ((t > 1.0 && (pressed.Space || pressed.Enter || pressed.KeyE || pressed.M0)) || t >= 9) return endDeathCut();
  const sm = x => x * x * (3 - 2 * x);
  const kneel = sm(clamp((t - 0.35) / 2.2, 0, 1)), fall = Math.pow(clamp((t - 3.0) / 1.0, 0, 1), 2);
  h.pivot.rotation.x = lerp(0, 0.35, kneel) + 1.15 * fall; h.pivot.position.y = 0.9 - 0.3 * kneel - 0.35 * fall;
  if (t >= 0.35 && c.flashed) { c.flashed = false; setEmissive(h.mats, BLACK); }
  if (t >= 3.9 && !c.impact) { c.impact = true; burst(new V3(B.x, 0.4, B.z), 100); sfx('slam'); shake = Math.max(shake, 0.6); }
  if (t >= 4.0 && !c.ember) { c.ember = true; c.emb.emitRate = 260; setArenaMood('dead'); }
  if (t >= 6.0) c.emb.emitRate = 0;
  if (t >= 4.2) { const v = clamp(1 - (t - 4.2) / 1.8, 0, 1); h.root.getChildMeshes().forEach(m => m.visibility = v); }
  if (t >= 5.0) $('title').classList.add('show');
  // camera: orbita lenta ao redor do chefe e depois plano geral
  const tt = Math.min(t, 6), ang = c.a0 + 0.35 * Math.max(tt - 0.35, 0), r = lerp(9, 6.5, tt / 6), y = lerp(1.8, 3.5, tt / 6);
  let pos = new V3(B.x + Math.sin(ang) * r, y, B.z + Math.cos(ang) * r);
  let tgt = new V3(B.x, lerp(2.4, 1.0, kneel * 0.5 + fall * 0.5), B.z);
  if (t < 1.2) { const k = sm(t / 1.2); pos = V3.Lerp(c.startPos, pos, k); tgt = V3.Lerp(c.startTgt, tgt, k); }
  if (t > 6.0) {
    const k = sm(clamp((t - 6.0) / 2.5, 0, 1));
    pos = V3.Lerp(pos, new V3(ARENA.x, 16, ARENA.z - 22), k); tgt = V3.Lerp(tgt, new V3(ARENA.x, 1, ARENA.z), k);
  }
  if (shake > 0) { pos.x += (Math.random() - 0.5) * shake; pos.y += (Math.random() - 0.5) * shake; shake = Math.max(0, shake - dt * 1.2); }
  camera.position.copyFrom(pos); camera.setTarget(tgt);
}
function endDeathCut() {
  const c = game.cut; game.cut = null; c.emb.emitRate = 0; setTimeout(() => c.emb.dispose(), 5000);
  boss.root.setEnabled(false); boss.permaDead = true; boss.introPose = false;
  game.bossFight = false; fogGate.setEnabled(false); setArenaMood('dead');
  const b = makeBonfire(ARENA.x, ARENA.z, 'Arena do Guardião'); b.setLit();
  cam.yaw = Math.atan2(ARENA.x - P.pos.x, ARENA.z - P.pos.z); cam.pitch = 0.35; cam.dist = 6.5;
  document.body.classList.remove('cinematic'); $('title').classList.remove('show');
  sfx('bonfire'); setTimeout(() => showMsg('FOGUEIRA ACESA', 'gold', 2800), 500);
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
  $('estus').textContent = '⚱ Estus ' + P.estus + '/' + CONFIG.player.estusMax + '   ·   Nível ' + P.level;
  $('soulsN').textContent = Math.floor(P.souls);
  if (game.bossFight && boss && !boss.dead) {
    $('boss').style.display = 'block'; $('boss').firstElementChild.textContent = boss.def.name;
    $('boss').querySelector('i').style.width = clamp(boss.hp / boss.def.hp, 0, 1) * 100 + '%';
  }
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
  const def = CONFIG.player[kind]; spend(def.stamina);
  P.state = 'attack'; P.t = 0; P.atk = { ...def, heavy: kind === 'heavy', hit: false }; P.blocking = false;
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
    if (d < a.range + e.radius && Math.abs(angDiff(f, Math.atan2(dx, dz))) < 1.0) e.damage(a.dmg * P.dmgMult, a.heavy);
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
      P.h.pivot.rotation.x = p * Math.PI * 2; armsBusy = true;
      if (P.t >= D) { P.state = 'free'; P.h.pivot.rotation.x = 0; }
      break;
    }
    case 'attack': {
      const a = P.atk, f = P.root.rotation.y, tW = a.windup, tA = tW + a.active, tR = tA + a.recover;
      armsBusy = true;
      const lunge = P.t < tA ? (a.heavy ? 3.5 : 2.5) : 0;
      P.pos.x += Math.sin(f) * lunge * dt; P.pos.z += Math.cos(f) * lunge * dt;
      if (P.t < tW) armPose(P.h, 'windup', P.t / tW);
      else if (P.t < tA) { if (!a.hit) { a.hit = true; playerStrike(); } armPose(P.h, 'active', (P.t - tW) / a.active); }
      else {
        armPose(P.h, 'recover', (P.t - tA) / a.recover);
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
  P.anim.armsBusy = P.h.glb ? P.state === 'attack' : armsBusy;
  P.anim.flinch = P.blocking ? 0.12 : 0;
  animateLimbs(P.h, speed, dt, P.anim);
  if (P.state !== 'dead') {
    resolveWorld(P.pos, P.radius);
    if (game.bossFight) P.pos.z = Math.max(P.pos.z, ARENA.z - ARENA.r + 1.5);
  }
}

/* ------------------------------ interações / mundo ------------------------------ */
function updateWorld(dt, time) {
  let prompt = '';
  if (P.state === 'free') {
    for (const b of bonfires) {
      if (Math.hypot(P.pos.x - b.pos.x, P.pos.z - b.pos.z) < 3) {
        const cost = CONFIG.levelUp.baseCost + P.level * CONFIG.levelUp.costPerLevel;
        prompt = b.lit ? `[E] Descansar — ${b.name}<br>[L] Subir de nível (${cost} almas)` : '[E] Acender a fogueira';
        if (pressed.KeyE) {
          if (!b.lit) { b.setLit(); showMsg('FOGUEIRA ACESA', 'gold', 2800); }
          else showMsg('DESCANSANDO', 'gold', 1500);
          sfx('bonfire'); game.bonfire = b; fullRest(); resetEnemies();
        }
        if (pressed.KeyL && b.lit) {
          if (P.souls >= cost) {
            P.souls -= cost; P.level++; P.maxHp += CONFIG.levelUp.hpPerLevel; P.dmgMult += CONFIG.levelUp.dmgPerLevel; P.hp = P.maxHp; sfx('estus');
            showMsg('NÍVEL ' + P.level, 'gold', 1800);
          } else showMsg('ALMAS INSUFICIENTES', 'red', 1500);
        }
        break;
      }
    }
    if (!prompt && !game.gateOpen && !game.bossDefeated && Math.hypot(P.pos.x, P.pos.z - 36) < 5) {
      prompt = '[E] Atravessar a névoa';
      if (pressed.KeyE) { game.gateOpen = true; P.pos.set(0, 0, 40.5); P.root.rotation.y = 0; }
    }
  }
  if (game.gateOpen && !game.bossFight && !game.bossDefeated && !boss.dead && P.pos.z > ARENA.z - ARENA.r + 3) {
    startCutscene();
  }
  $('prompt').innerHTML = prompt;
  // alma perdida
  if (game.stain) {
    game.stain.mesh.position.y = 0.8 + Math.sin(time * 3) * 0.15;
    if (Math.hypot(P.pos.x - game.stain.mesh.position.x, P.pos.z - game.stain.mesh.position.z) < 1.6 && P.state !== 'dead') {
      P.souls += game.stain.souls; game.stain.mesh.dispose(); game.stain = null; sfx('estus'); showMsg('ALMAS RECUPERADAS', 'gold', 1800);
    }
  }
  bonfires.forEach(b => { if (b.lit) b.light.intensity = 1.5 + Math.sin(time * 17) * 0.15 + Math.random() * 0.15; });
  const pulse = Math.sin(time * (arenaMood === 'fight' ? 4 : 1.2)) * 0.5 + 0.5;
  runeTex.level = arenaMood === 'fight' ? 0.7 + pulse * 0.5 : arenaMood === 'dead' ? 0.05 : 0.2 + pulse * 0.12;
  arenaLight.intensity = arenaMood === 'fight' ? 1.0 + pulse * 0.5 : arenaMood === 'dead' ? 0.05 : 0.3 + pulse * 0.1;
  fogGate.material.alpha = (game.bossFight ? 0.65 : 0.3) + Math.sin(time * 2) * 0.06;
}

function toggleLock() {
  if (game.lock) { game.lock = null; return; }
  const fx = Math.sin(cam.yaw), fz = Math.cos(cam.yaw);
  let best = null, bs = -1;
  for (const e of enemies) {
    if (e.dead || !e.root.isEnabled()) continue;
    const dx = e.pos.x - P.pos.x, dz = e.pos.z - P.pos.z, d = Math.hypot(dx, dz);
    if (d > 28) continue;
    const dot = (dx * fx + dz * fz) / d; if (dot < 0.2) continue;
    const score = dot * 2 - d / 28; if (score > bs) { bs = score; best = e; }
  }
  game.lock = best;
}


/* ------------------------------ cutscene do chefe ------------------------------ */
function startCutscene() {
  game.bossFight = true; boss.state = 'intro'; game.lock = null;
  const B = boss.pos, yaw = Math.atan2(B.x - P.pos.x, B.z - P.pos.z), cp = Math.cos(0.32), sp = Math.sin(0.32);
  const piv = new V3(P.pos.x, 1.7, P.pos.z), dir = new V3(Math.sin(yaw) * cp, -sp, Math.cos(yaw) * cp);
  game.cut = { t: game.bossSeen ? 1.9 : 0, slam: false, yaw, endPos: piv.subtract(dir.scale(6.5)), endTgt: piv };
  $('title').firstElementChild.textContent = boss.def.name; $('title').lastElementChild.textContent = boss.def.subtitle || '';
  document.body.classList.add('cinematic');
}
function endCutscene() {
  const c = game.cut; game.cut = null; game.bossSeen = true;
  boss.introPose = false; boss.state = 'chase'; boss.cd = 0.8; boss.h.rArm.rotation.x = 0;
  setArenaMood('fight'); cam.yaw = c.yaw; cam.pitch = 0.32; cam.dist = 6.5;
  document.body.classList.remove('cinematic'); $('title').classList.remove('show');
}
function updateCutscene(dt) {
  if (game.cut.kind === 'death') return updateDeathCut(dt);
  const c = game.cut; c.t += dt; const t = c.t, B = boss.pos;
  if ((c.t > 0.8 && (pressed.Space || pressed.Enter || pressed.KeyE || pressed.M0)) || t >= 6.2) return endCutscene();
  // pose do chefe: ergue a espada e bate no chao
  if (t >= 1.9) {
    boss.introPose = true;
    if (t < 3.5) armPose(boss.h, 'windup', clamp((t - 1.9) / 1.6, 0, 1));
    else if (t < 3.62) armPose(boss.h, 'active', (t - 3.5) / 0.12);
    else armPose(boss.h, 'recover', clamp((t - 3.62) / 1.8, 0, 1));
  }
  if (t >= 3.62 && !c.slam) {
    c.slam = true; const f = boss.root.rotation.y;
    burst(new V3(B.x + Math.sin(f) * 4, 0.3, B.z + Math.cos(f) * 4), 90); sfx('slam'); shake = 1.1; setArenaMood('fight');
  }
  if (t >= 3.7) $('title').classList.add('show');
  const sm = x => x * x * (3 - 2 * x), L = (a, b, k) => V3.Lerp(a, b, k);
  let pos, tgt;
  if (t < 1.9) {
    const k = sm(t / 1.9);
    pos = L(new V3(B.x + 4, 1.0, B.z - 14), new V3(B.x + 2.5, 1.4, B.z - 9.5), k); tgt = L(new V3(B.x, 1.0, B.z), new V3(B.x, 4.0, B.z), k);
  } else if (t < 3.5) {
    const k = sm((t - 1.9) / 1.6);
    pos = L(new V3(B.x - 3.5, 0.6, B.z - 8), new V3(B.x - 1.5, 0.8, B.z - 7), k); tgt = new V3(B.x, 4.6, B.z);
  } else if (t < 3.9) {
    pos = new V3(B.x + 7, 2.5, B.z - 6); tgt = new V3(B.x, 1.5, B.z - 3);
  } else {
    const k = sm(clamp((t - 3.9) / 2.3, 0, 1));
    pos = L(new V3(B.x + 7, 2.5, B.z - 6), c.endPos, k); tgt = L(new V3(B.x, 1.5, B.z - 3), c.endTgt, k);
  }
  if (shake > 0) { pos.x += (Math.random() - 0.5) * shake; pos.y += (Math.random() - 0.5) * shake; shake = Math.max(0, shake - dt * 1.2); }
  camera.position.copyFrom(pos); camera.setTarget(tgt);
}

function updateCamera(dt) {
  if (game.cut) { moon.position.set(P.pos.x + 30, 60, P.pos.z - 24); ash.emitter.set(P.pos.x, 2.5, P.pos.z); return; }
  if (keys.ArrowLeft) cam.yaw -= 2 * dt; if (keys.ArrowRight) cam.yaw += 2 * dt;
  if (game.lock) {
    if (game.lock.dead || Math.hypot(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z) > 32) game.lock = null;
    else { cam.yaw = turnToward(cam.yaw, Math.atan2(game.lock.pos.x - P.pos.x, game.lock.pos.z - P.pos.z), 7 * dt); cam.pitch = lerp(cam.pitch, 0.32, 4 * dt); }
  }
  cam.dist = lerp(cam.dist, game.lock && game.lock.def.boss ? 11 : 6.5, 3 * dt);
  const piv = new V3(P.pos.x, 1.7, P.pos.z), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
  const dir = new V3(Math.sin(cam.yaw) * cp, -sp, Math.cos(cam.yaw) * cp);
  const pos = piv.subtract(dir.scale(cam.dist)); pos.y = Math.max(pos.y, 0.5);
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
  showMsg('KELWIN SOULS', 'gold', 3000);
});
addEventListener('resize', () => engine.resize());

/* ------------------------------ loop ------------------------------ */
let clock = 0;
scene.onBeforeRenderObservable.add(() => {
  const dt = Math.min(engine.getDeltaTime() / 1000, 0.05); clock += dt;
  if (game.started) {
    if (game.cut) updateCutscene(dt); else updatePlayer(dt);
    enemies.forEach(e => e.update(dt));
    updateWorld(dt, clock);
  }
  updateCamera(dt);
  updateHud();
  for (const k in pressed) pressed[k] = false;
});
engine.runRenderLoop(() => scene.render());
loadAssets();

// atalho de depuração para testes: window.__ks
window.__ks = { P, enemies, game, bonfires, CONFIG };
