'use strict';
/* ======================================================================
   ABISSAL — terror aquático em primeira pessoa, feito com Babylon.js.
   Tudo é gerado por código: terreno, naufrágio, criatura, som.
   Ajuste o jogo pelo CONFIG abaixo.
   ====================================================================== */
const CONFIG = {
  diver: { swim: 3.4, sprint: 5.8, accel: 7, drag: 2.4, radius: 0.5, health: 100 },
  o2: { seconds: 300, sprintMult: 1.9, fearMult: 1.3, tankBonus: 90, drownDps: 9 },
  light: { seconds: 240, offRecharge: 0.25 },
  sonar: { cooldown: 9, showFor: 5, range: 130 },
  flares: { count: 3, life: 14, lure: 90 },
  creature: {
    roam: 4.5, investigate: 7, hunt: 10, lunge: 19, enraged: 1.25,
    bite: 50, biteReach: 3.2, retreatFor: 14, headRadius: 1.5,
    hearLightOn: 34, hearLightOff: 9, hearSprint: 20,   // de quantos metros ele percebe você
    scentEvery: 24, scentErr: 28, loseAfter: 6,          // pista periódica e tempo até perder você de vista
  },
};

const V3 = BABYLON.Vector3, C3 = BABYLON.Color3, C4 = BABYLON.Color4, MB = BABYLON.MeshBuilder;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const $ = id => document.getElementById(id);
function mulberry(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const rnd = mulberry(4242);

/* ------------------------------ cena ------------------------------ */
const canvas = $('c');
const engine = new BABYLON.Engine(canvas, true, { stencil: false });
const scene = new BABYLON.Scene(engine);
const WATER = new C3(0.006, 0.03, 0.042);
scene.clearColor = new C4(WATER.r, WATER.g, WATER.b, 1);
scene.fogMode = BABYLON.Scene.FOGMODE_EXP2; scene.fogDensity = 0.05; scene.fogColor = WATER.clone();
scene.ambientColor = new C3(0, 0, 0);

const camera = new BABYLON.FreeCamera('cam', new V3(0, -50, 0), scene);
camera.minZ = 0.08; camera.maxZ = 160; camera.fov = 1.15; camera.inputs.clear();

const hemi = new BABYLON.HemisphericLight('hemi', new V3(0, 1, 0), scene);
hemi.diffuse = new C3(0.16, 0.42, 0.5); hemi.groundColor = new C3(0.01, 0.03, 0.04); hemi.specular = C3.Black(); hemi.intensity = 0.28;

const TORCH_POWER = 7;
const torch = new BABYLON.SpotLight('torch', new V3(0, 0, 0), new V3(0, 0, 1), 1.25, 22, scene);
torch.diffuse = new C3(0.85, 1, 0.92); torch.specular = new C3(0.25, 0.3, 0.28); torch.intensity = TORCH_POWER; torch.range = 40;
torch.parent = camera; torch.position.set(0.25, -0.2, 0.1);

const flareLight = new BABYLON.PointLight('flareL', new V3(0, -100, 0), scene);
flareLight.diffuse = new C3(1, 0.16, 0.08); flareLight.specular = C3.Black(); flareLight.range = 34; flareLight.intensity = 0;

// feixe da lanterna visível na água turva
const beam = MB.CreateCylinder('beam', { diameterTop: 0.25, diameterBottom: 15, height: 22, tessellation: 24, cap: BABYLON.Mesh.NO_CAP }, scene);
beam.parent = camera; beam.rotation.x = -Math.PI / 2; beam.position.set(0.25, -0.25, 11.2); beam.isPickable = false; beam.applyFog = false;
{
  const t = new BABYLON.DynamicTexture('beamT', { width: 4, height: 128 }, scene, true), c = t.getContext(), g = c.createLinearGradient(0, 0, 0, 128);
  g.addColorStop(0, '#000'); g.addColorStop(0.35, '#1b1b1b'); g.addColorStop(1, '#5a5a5a'); c.fillStyle = g; c.fillRect(0, 0, 4, 128); t.update();
  const m = new BABYLON.StandardMaterial('beamM', scene);
  m.disableLighting = true; m.emissiveTexture = t; m.diffuseColor = C3.Black(); m.specularColor = C3.Black(); m.backFaceCulling = false;
  m.alphaMode = BABYLON.Engine.ALPHA_ADD; m.alpha = 0.16; m.disableDepthWrite = true; m.fogEnabled = false; beam.material = m;
}
function mat(c, em, spec = 0.04) {
  const m = new BABYLON.StandardMaterial('m', scene);
  m.diffuseColor = new C3(c[0], c[1], c[2]); m.specularColor = new C3(spec, spec, spec); m.maxSimultaneousLights = 4;
  if (em) m.emissiveColor = new C3(em[0], em[1], em[2]);
  return m;
}
function canvasTex(size, paint, uv = 1) {
  const t = new BABYLON.DynamicTexture('t', size, scene, true), c = t.getContext();
  paint(c, size); t.update(); t.uScale = t.vScale = uv; return t;
}
const glow = new BABYLON.GlowLayer('glow', scene, { blurKernelSize: 32 }); glow.intensity = 0.8;

// lente do capacete: água ondulando, aberração na borda, vinheta, grão, medo e ferimento
BABYLON.Effect.ShadersStore.helmetFragmentShader = `
precision highp float;
varying vec2 vUV; uniform sampler2D textureSampler; uniform float time, hurt, fear, fade;
float grain(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + time) * 43758.5453); }
void main() {
  vec2 c = vUV - 0.5; float r = length(c);
  vec2 w = vec2(sin(vUV.y * 14.0 + time * 1.1), cos(vUV.x * 12.0 + time * 0.9)) * (0.0016 + fear * 0.003);
  vec2 ab = c * r * (0.012 + fear * 0.012);
  vec3 col = vec3(texture2D(textureSampler, vUV + w + ab).r, texture2D(textureSampler, vUV + w).g, texture2D(textureSampler, vUV + w - ab).b);
  col = pow(col, vec3(0.85)) * 1.25;
  col *= 1.0 - smoothstep(0.34, 0.74, r) * (0.88 + fear * 0.1);
  col = mix(col, vec3(0.6, 0.02, 0.01), hurt * (0.3 + 0.7 * smoothstep(0.1, 0.6, r)));
  col += (grain(vUV * 800.0) - 0.5) * 0.028;
  gl_FragColor = vec4(col * (1.0 - fade), 1.0);
}`;
const fx = { hurt: 0, fear: 0, fade: 0 };
const lens = new BABYLON.PostProcess('helmet', 'helmet', ['time', 'hurt', 'fear', 'fade'], null, 1, camera);
lens.onApply = e => { e.setFloat('time', performance.now() / 1000 % 1000); e.setFloat('hurt', fx.hurt); e.setFloat('fear', fx.fear); e.setFloat('fade', fx.fade); };

/* ------------------------------ fundo do mar ------------------------------ */
const hash2 = (x, y) => { const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - Math.floor(s); };
function vnoise(x, y) {
  const i = Math.floor(x), j = Math.floor(y), a = x - i, b = y - j, u = a * a * (3 - 2 * a), v = b * b * (3 - 2 * b);
  return lerp(lerp(hash2(i, j), hash2(i + 1, j), u), lerp(hash2(i, j + 1), hash2(i + 1, j + 1), u), v);
}
function fbm(x, y) { let s = 0, a = 0.5; for (let k = 0; k < 4; k++) { s += a * vnoise(x, y); x = x * 2.03 + 7; y = y * 2.03 + 3; a *= 0.5; } return s; }
const WORLD = 190;
const TRENCH = { x: 28, z: -105 };
function floorY(x, z) {
  let h = -72 + (fbm(x * 0.018 + 5, z * 0.018 + 9) - 0.5) * 34 + (fbm(x * 0.09, z * 0.09) - 0.5) * 3.5;
  // fenda funda no sul
  const dx = (x - TRENCH.x) * 0.55 + (z - TRENCH.z) * 0.2, dz = (z - TRENCH.z) * 0.14;
  const t = Math.hypot(dx, dz);
  h -= 34 * (1 - sstep(4, 19, t));
  // paredões nos limites do vale
  const e = Math.max(Math.abs(x), Math.abs(z));
  h += 60 * sstep(WORLD - 45, WORLD, e);
  return h;
}
{
  const n = 240, ground = MB.CreateGround('sea', { width: WORLD * 2 + 40, height: WORLD * 2 + 40, subdivisions: n, updatable: true }, scene);
  const pos = ground.getVerticesData('position');
  for (let i = 0; i < pos.length; i += 3) pos[i + 1] = floorY(pos[i], pos[i + 2]);
  ground.updateVerticesData('position', pos);
  const nor = []; BABYLON.VertexData.ComputeNormals(pos, ground.getIndices(), nor); ground.updateVerticesData('normal', nor);
  const tex = canvasTex(1024, (c, s) => {
    c.fillStyle = '#4c5650'; c.fillRect(0, 0, s, s);
    for (let i = 0; i < 5000; i++) { const g = 44 + rnd() * 54; c.fillStyle = `rgba(${g},${g + 8},${g + 2},0.28)`; c.beginPath(); c.arc(rnd() * s, rnd() * s, 1 + rnd() * 16, 0, 7); c.fill(); }
    for (let i = 0; i < 500; i++) { c.fillStyle = `rgba(15,22,22,${0.15 + rnd() * 0.3})`; c.beginPath(); c.ellipse(rnd() * s, rnd() * s, 2 + rnd() * 12, 1 + rnd() * 3, rnd() * 3, 0, 7); c.fill(); }
  }, 34);
  const m = mat([1, 1, 1]); m.diffuseTexture = tex; ground.material = m; ground.isPickable = false;
}

/* ------------------------------ colisores ------------------------------ */
const spheres = [], boxes = [];   // esferas {x,y,z,r} e caixas giradas no eixo y {x,y,z,hx,hy,hz,yaw}
function pushOut(p, r) {
  for (const s of spheres) {
    const dx = p.x - s.x, dy = p.y - s.y, dz = p.z - s.z, d = Math.hypot(dx, dy, dz), min = s.r + r;
    if (d < min && d > 1e-4) { const k = min / d; p.x = s.x + dx * k; p.y = s.y + dy * k; p.z = s.z + dz * k; }
  }
  for (const b of boxes) {
    const c = Math.cos(b.yaw), sn = Math.sin(b.yaw), rx = p.x - b.x, rz = p.z - b.z;
    const lx = rx * c - rz * sn, ly = p.y - b.y, lz = rx * sn + rz * c;
    const qx = clamp(lx, -b.hx, b.hx), qy = clamp(ly, -b.hy, b.hy), qz = clamp(lz, -b.hz, b.hz);
    let dx = lx - qx, dy = ly - qy, dz = lz - qz, d = Math.hypot(dx, dy, dz);
    if (d >= r) continue;
    let nx, ny, nz;
    if (d < 1e-4) { // centro dentro da caixa: sai pela face mais próxima
      const ex = b.hx - Math.abs(lx), ey = b.hy - Math.abs(ly), ez = b.hz - Math.abs(lz);
      if (ex < ey && ex < ez) { nx = lx + Math.sign(lx || 1) * (ex + r); ny = ly; nz = lz; }
      else if (ey < ez) { nx = lx; ny = ly + Math.sign(ly || 1) * (ey + r); nz = lz; }
      else { nx = lx; ny = ly; nz = lz + Math.sign(lz || 1) * (ez + r); }
    } else { const k = r / d; nx = qx + dx * k; ny = qy + dy * k; nz = qz + dz * k; }
    p.x = b.x + nx * c + nz * sn; p.y = b.y + ny; p.z = b.z - nx * sn + nz * c;
  }
}
const rock = mat([0.26, 0.29, 0.28]); rock.diffuseTexture = canvasTex(256, (c, s) => {
  c.fillStyle = '#54605a'; c.fillRect(0, 0, s, s);
  for (let i = 0; i < 600; i++) { const g = 62 + rnd() * 34; c.fillStyle = `rgba(${g},${g + 5},${g},0.3)`; c.beginPath(); c.arc(rnd() * s, rnd() * s, 1 + rnd() * 6, 0, 7); c.fill(); }
}, 2);
function addRock(x, z, r) {
  const m = MB.CreateIcoSphere('rock', { radius: r, subdivisions: 2, flat: true }, scene);
  const pos = m.getVerticesData('position');
  for (let i = 0; i < pos.length; i += 3) { const k = 0.75 + 0.45 * hash2(Math.round(pos[i] * 9), Math.round(pos[i + 1] * 9 + pos[i + 2] * 5)); pos[i] *= k; pos[i + 1] *= k * 0.8; pos[i + 2] *= k; }
  m.updateVerticesData('position', pos);
  const y = floorY(x, z) + r * 0.25;
  m.position.set(x, y, z); m.rotation.y = rnd() * 6.28; m.material = rock; m.isPickable = false; m.freezeWorldMatrix();
  spheres.push({ x, y, z, r: r * 0.85 });
}

/* ------------------------------ naufrágio ------------------------------ */
const rust = mat([0.5, 0.42, 0.36], null, 0.1); rust.diffuseTexture = canvasTex(512, (c, s) => {
  c.fillStyle = '#5b4a3e'; c.fillRect(0, 0, s, s);
  for (let i = 0; i < 1500; i++) { const a = rnd(); c.fillStyle = a < 0.5 ? `rgba(120,62,30,${rnd() * 0.45})` : `rgba(26,34,30,${rnd() * 0.45})`; c.beginPath(); c.arc(rnd() * s, rnd() * s, 1 + rnd() * 18, 0, 7); c.fill(); }
  c.strokeStyle = 'rgba(15,12,10,.7)'; c.lineWidth = 2; for (let y = 0; y < s; y += 64) { c.beginPath(); c.moveTo(0, y); c.lineTo(s, y); c.stroke(); }
  for (let x = 0; x < s; x += 128) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, s); c.stroke(); }
}, 1);
const WRECK = { x: 52, z: 42, yaw: 0.65 };
WRECK.y = floorY(WRECK.x, WRECK.z) + 1;
function wreckPoint(lx, ly, lz) { // local do naufrágio -> mundo
  const c = Math.cos(WRECK.yaw), s = Math.sin(WRECK.yaw);
  return new V3(WRECK.x + lx * c + lz * s, WRECK.y + ly, WRECK.z - lx * s + lz * c);
}
function plate(lx, ly, lz, w, h, d, solid = true) {
  const m = MB.CreateBox('hull', { width: w, height: h, depth: d }, scene), p = wreckPoint(lx, ly, lz);
  m.position.copyFrom(p); m.rotation.y = WRECK.yaw; m.material = rust; m.isPickable = false; m.freezeWorldMatrix();
  if (solid) boxes.push({ x: p.x, y: p.y, z: p.z, hx: w / 2, hy: h / 2, hz: d / 2, yaw: WRECK.yaw });
  return m;
}
{
  const L = 22, W = 5.2, H = 8, DOOR = 1.1;   // meia-largura da porta menor que a cabeça da criatura
  plate(0, 0, 0, W * 2, 0.4, L * 2);                             // piso
  plate(-W, H / 2, 0, 0.4, H, L * 2);                            // bombordo inteiro
  // estibordo com rombo no meio
  plate(W, H / 2, -(L + DOOR) / 2, 0.4, H, L - DOOR); plate(W, H / 2, (L + DOOR) / 2, 0.4, H, L - DOOR);
  plate(W, (H + 3.2) / 2, 0, 0.4, H - 3.2, DOOR * 2);
  // teto com um buraco na popa (a popa fica aberta por cima)
  plate(0, H, -6, W * 2, 0.4, L * 2 - 12); plate(-W / 2 - DOOR / 2, H, L - 6, W - DOOR, 0.4, 12); plate(W / 2 + DOOR / 2, H, L - 6, W - DOOR, 0.4, 12);
  // anteparas com portas estreitas
  for (const z of [-9, 9]) {
    plate(-(W + DOOR) / 2, H / 2, z, W - DOOR, H, 0.3); plate((W + DOOR) / 2, H / 2, z, W - DOOR, H, 0.3);
    plate(0, (H + 2.8) / 2, z, DOOR * 2, H - 2.8, 0.3);
  }
  // proa e popa
  plate(0, H / 2, -L, W * 2, H, 0.4); plate(0, H / 2, L, W * 2, H, 0.4);
  plate(0, H + 2, -L + 7, 7, 4, 8);                              // casario
  // mastro caído e destroços
  const mast = MB.CreateCylinder('mast', { diameterTop: 0.35, diameterBottom: 0.6, height: 18, tessellation: 8 }, scene);
  mast.position.copyFrom(wreckPoint(0, H + 6.5, 4)); mast.rotation.set(0.5, WRECK.yaw, 0.3); mast.material = rust; mast.isPickable = false;
  for (let i = 0; i < 14; i++) {
    const a = rnd() * 6.28, d = 14 + rnd() * 18, p = wreckPoint(Math.cos(a) * d, 0, Math.sin(a) * (d + 12)), w = 0.5 + rnd() * 2.5;
    const b = MB.CreateBox('junk', { width: w, height: 0.25 + rnd(), depth: 1 + rnd() * 3 }, scene);
    b.position.set(p.x, floorY(p.x, p.z) + 0.3, p.z); b.rotation.set(rnd() * 0.6, rnd() * 6, rnd() * 0.6); b.material = rust; b.isPickable = false; b.freezeWorldMatrix();
  }
}

/* ------------------------------ estação, ossada, cabo ------------------------------ */
const STATION = { x: -72, z: 58 }; STATION.y = floorY(STATION.x, STATION.z);
{
  const steel = mat([0.34, 0.38, 0.4], null, 0.3), sy = STATION.y + 7;
  const body = MB.CreateSphere('hab', { diameterX: 16, diameterY: 8, diameterZ: 16, segments: 16 }, scene);
  body.position.set(STATION.x, sy, STATION.z); body.material = steel; body.isPickable = false;
  spheres.push({ x: STATION.x, y: sy, z: STATION.z, r: 5.4 });
  for (let i = 0; i < 6; i++) {
    const a = i / 6 * 6.283 + 0.26, x = STATION.x + Math.cos(a) * 5.2, z = STATION.z + Math.sin(a) * 5.2;
    const leg = MB.CreateCylinder('leg', { diameter: 0.9, height: 9, tessellation: 8 }, scene);
    leg.position.set(x, STATION.y + 3.6, z); leg.material = steel; leg.isPickable = false;
    for (let h = 0; h < 3; h++) spheres.push({ x, y: STATION.y + 1 + h * 2.6, z, r: 1.15 });
  }
  const win = mat([0.02, 0.05, 0.05], [0.22, 0.05, 0.02]);
  for (let i = 0; i < 5; i++) { const a = i / 5 * 6.283, w = MB.CreateSphere('win', { diameter: 1.2, segments: 8 }, scene); w.position.set(STATION.x + Math.cos(a) * 7.2, sy + 1, STATION.z + Math.sin(a) * 7.2); w.material = win; w.isPickable = false; }
}
{ // ossada gigante: uma costela depois da outra, para dizer o que vive aqui
  const bone = mat([0.62, 0.6, 0.5]), bx = -28, bz = -22;
  for (let i = 0; i < 13; i++) {
    const z = bz + i * 2.6, r = 8 * Math.sin((i + 1.5) / 15 * Math.PI) + 1.2;
    const y = floorY(bx, z) - 0.4;
    for (const sgn of [-1, 1]) {
      const pts = []; for (let k = 0; k <= 12; k++) { const a = k / 12 * Math.PI * 0.86; pts.push(new V3(bx + sgn * Math.sin(a) * r, y + (1 - Math.cos(a)) * r, z)); }
      const rib = MB.CreateTube('rib', { path: pts, radius: 0.28, tessellation: 6, cap: BABYLON.Mesh.CAP_END }, scene);
      rib.material = bone; rib.isPickable = false; rib.freezeWorldMatrix();
    }
  }
}
// cabo do barco: é o caminho de volta
const CABLE = { x: 0, z: 0 };
{
  const y0 = floorY(CABLE.x, CABLE.z);
  const cable = MB.CreateCylinder('cable', { diameter: 0.14, height: 150, tessellation: 6 }, scene);
  cable.position.set(CABLE.x, y0 + 75, CABLE.z); cable.material = mat([0.75, 0.7, 0.4], [0.1, 0.09, 0.03]); cable.isPickable = false;
  const weight = MB.CreateCylinder('w', { diameter: 1.8, height: 0.9, tessellation: 12 }, scene);
  weight.position.set(CABLE.x, y0 + 0.4, CABLE.z); weight.material = rust; weight.isPickable = false;
  const lamp = MB.CreateSphere('lamp', { diameter: 0.35, segments: 8 }, scene);
  lamp.position.set(CABLE.x, y0 + 3.5, CABLE.z); lamp.material = mat([0, 0, 0], [0.9, 0.75, 0.3]); lamp.isPickable = false;
}
for (let i = 0; i < 120; i++) {
  const x = (rnd() - 0.5) * WORLD * 1.9, z = (rnd() - 0.5) * WORLD * 1.9;
  if (Math.hypot(x - CABLE.x, z - CABLE.z) < 12 || Math.hypot(x - WRECK.x, z - WRECK.z) < 30 || Math.hypot(x - STATION.x, z - STATION.z) < 14) continue;
  addRock(x, z, 0.8 + rnd() * rnd() * 7);
}
// algas que balançam
const kelp = [];
{
  const km = mat([0.12, 0.2, 0.1]); km.backFaceCulling = false;
  for (let i = 0; i < 90; i++) {
    const x = (rnd() - 0.5) * WORLD * 1.6, z = (rnd() - 0.5) * WORLD * 1.6, h = 3 + rnd() * 9;
    if (Math.hypot(x - WRECK.x, z - WRECK.z) < 26) continue;
    const k = MB.CreatePlane('kelp', { width: 0.5, height: h }, scene);
    k.setPivotPoint(new V3(0, -h / 2, 0)); k.position.set(x, floorY(x, z) + h / 2, z); k.rotation.y = rnd() * 3; k.material = km; k.isPickable = false; k.phase = rnd() * 6;
    kelp.push(k);
  }
}

/* ------------------------------ neve marinha e bolhas ------------------------------ */
const dot = canvasTex(32, (c, s) => { const g = c.createRadialGradient(16, 16, 0, 16, 16, 16); g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(1, 'rgba(255,255,255,0)'); c.fillStyle = g; c.fillRect(0, 0, s, s); });
dot.hasAlpha = true;
const snow = new BABYLON.ParticleSystem('snow', 900, scene);
snow.particleTexture = dot; snow.emitter = new V3(0, 0, 0);
snow.minEmitBox = new V3(-13, -9, -13); snow.maxEmitBox = new V3(13, 9, 13);
snow.color1 = new C4(0.7, 0.85, 0.8, 0.55); snow.color2 = new C4(0.5, 0.7, 0.7, 0.3); snow.colorDead = new C4(0.4, 0.6, 0.6, 0);
snow.minSize = 0.02; snow.maxSize = 0.07; snow.minLifeTime = 4; snow.maxLifeTime = 9; snow.emitRate = 110; snow.minEmitPower = 0.02; snow.maxEmitPower = 0.14;
snow.direction1 = new V3(-1, -1, -1); snow.direction2 = new V3(1, -0.2, 1); snow.gravity = new V3(0, -0.015, 0); snow.preWarmCycles = 120; snow.start();
const bubbles = new BABYLON.ParticleSystem('bubbles', 90, scene);
bubbles.particleTexture = dot; bubbles.emitter = new V3(0, 0, 0);
bubbles.minEmitBox = new V3(-0.2, -0.3, -0.2); bubbles.maxEmitBox = new V3(0.2, 0, 0.2);
bubbles.color1 = new C4(0.8, 1, 1, 0.5); bubbles.color2 = new C4(0.6, 0.9, 0.9, 0.3); bubbles.colorDead = new C4(0.6, 0.9, 0.9, 0);
bubbles.minSize = 0.015; bubbles.maxSize = 0.06; bubbles.minLifeTime = 1; bubbles.maxLifeTime = 2.4; bubbles.emitRate = 0; bubbles.minEmitPower = 0.4; bubbles.maxEmitPower = 1.1;
bubbles.direction1 = new V3(-0.3, 1, -0.3); bubbles.direction2 = new V3(0.3, 2, 0.3); bubbles.gravity = new V3(0, 0.5, 0); bubbles.start();

/* ------------------------------ som sintetizado ------------------------------ */
let ac = null, noiseBuf = null, master = null;
function initAudio() {
  try { ac = new (window.AudioContext || window.webkitAudioContext)(); } catch (_) { return; }
  master = ac.createGain(); master.gain.value = 0.9; master.connect(ac.destination);
  noiseBuf = ac.createBuffer(1, ac.sampleRate * 3, ac.sampleRate);
  const d = noiseBuf.getChannelData(0); let last = 0;
  for (let i = 0; i < d.length; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; d[i] = last * 3.5; }
  // o peso da água: ruído grave contínuo e um zumbido quase inaudível
  const src = ac.createBufferSource(); src.buffer = noiseBuf; src.loop = true;
  const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 170;
  const g = ac.createGain(); g.gain.value = 0.55; src.connect(lp).connect(g).connect(master); src.start();
  const hum = ac.createOscillator(); hum.frequency.value = 41; const hg = ac.createGain(); hg.gain.value = 0.05; hum.connect(hg).connect(master); hum.start();
}
function noiseHit(freq, q, dur, vol, type = 'bandpass', attack = 0.01, sweep) {
  if (!ac) return; const t = ac.currentTime, s = ac.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
  const f = ac.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q; if (sweep) f.frequency.exponentialRampToValueAtTime(sweep, t + dur);
  const g = ac.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + attack); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  s.connect(f).connect(g).connect(master); s.start(t, Math.random() * 2); s.stop(t + dur + 0.05);
}
function tone(f0, f1, dur, vol, type = 'sine', delay = 0, pan = 0) {
  if (!ac) return; const t = ac.currentTime + delay, o = ac.createOscillator(), g = ac.createGain();
  o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + Math.min(0.03, dur / 3)); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  const p = ac.createStereoPanner(); p.pan.value = pan; o.connect(g).connect(p).connect(master); o.start(t); o.stop(t + dur + 0.05);
}
const SND = {
  breathIn(k) { noiseHit(620, 1.2, 1.1, 0.16 + k * 0.1, 'bandpass', 0.35); },
  breathOut(k) { noiseHit(240, 0.8, 1.5, 0.22 + k * 0.1, 'bandpass', 0.1, 900); for (let i = 0; i < 6; i++) tone(300 + Math.random() * 500, 700 + Math.random() * 900, 0.08, 0.018, 'sine', 0.1 + i * 0.16); },
  heart(k) { tone(62, 38, 0.15, 0.3 * k); tone(55, 34, 0.16, 0.22 * k, 'sine', 0.22); },
  ping() { for (let i = 0; i < 4; i++) tone(1500, 1320, 0.35, 0.16 / (i + 1), 'sine', i * 0.34); },
  pickup() { tone(520, 780, 0.2, 0.1); tone(780, 1040, 0.25, 0.08, 'sine', 0.14); },
  bite() { noiseHit(1400, 0.7, 0.5, 1.3, 'lowpass', 0.005, 120); tone(130, 34, 0.7, 0.8, 'sawtooth'); tone(900, 200, 0.3, 0.2, 'square'); },
  flare() { noiseHit(2600, 0.5, 1.2, 0.2, 'highpass', 0.02); },
  moan(dist, pan, angry) { // canto da criatura: atravessa a água de longe
    const v = clamp(1.25 - dist / 150, 0.1, 1) * (angry ? 0.5 : 0.34), base = angry ? 74 : 52;
    tone(base * 1.7, base, 2.8, v, 'sawtooth', 0, pan); tone(base * 2.52, base * 1.4, 2.2, v * 0.45, 'triangle', 0.35, pan); tone(base / 1.5, base / 2.1, 3.2, v, 'sine', 0.1, pan);
  },
  swoosh(dist, pan) { tone(90, 44, 0.9, clamp(0.6 - dist / 60, 0, 0.5), 'sine', 0, pan); noiseHit(260, 0.8, 0.8, clamp(0.5 - dist / 60, 0.01, 0.4), 'bandpass', 0.2); },
};

/* ------------------------------ objetivos e itens ------------------------------ */
const goals = [
  { name: 'Porão do naufrágio', x: wreckPoint(0, 1, 0).x, y: wreckPoint(0, 1, 0).y, z: wreckPoint(0, 1, 0).z, got: false },
  { name: 'Sob a estação', x: STATION.x, y: STATION.y + 1, z: STATION.z, got: false },
  { name: 'Fundo da fenda', x: TRENCH.x, y: floorY(TRENCH.x, TRENCH.z) + 1, z: TRENCH.z, got: false },
];
const beaconMat = mat([0, 0, 0], [1, 0.1, 0.06]);
for (const g of goals) {
  const b = MB.CreateBox('rec', { width: 0.9, height: 0.55, depth: 0.6 }, scene);
  b.position.set(g.x, g.y, g.z); b.material = mat([0.75, 0.42, 0.06], [0.14, 0.07, 0.01], 0.3); b.isPickable = false;
  const led = MB.CreateSphere('led', { diameter: 0.14, segments: 6 }, scene); led.parent = b; led.position.set(0, 0.34, 0); led.material = beaconMat; led.isPickable = false;
  g.mesh = b;
}
const tanks = [[35, 24], [-58, 42], [12, -88], [-40, -60]].map(([x, z]) => {
  const y = floorY(x, z) + 0.9, m = MB.CreateCapsule('tank', { radius: 0.2, height: 1.1, tessellation: 10 }, scene);
  m.position.set(x, y, z); m.rotation.z = 1.2; m.material = mat([0.75, 0.75, 0.15], [0.12, 0.12, 0.02], 0.4); m.isPickable = false;
  return { x, y, z, mesh: m, got: false };
});

/* ------------------------------ estado ------------------------------ */
const game = { started: false, over: false, t: 0, cut: null, sonarCd: 0, sonarShow: 0, enraged: false, flare: null, bossMsg: 0 };
const keys = {}, pressed = {};
const D = {
  pos: new V3(CABLE.x + 2.5, floorY(CABLE.x, CABLE.z) + 15, CABLE.z + 2.5), vel: new V3(0, 0, 0),
  yaw: 0.9, pitch: 0.15, roll: 0, o2: CONFIG.o2.seconds, o2Max: CONFIG.o2.seconds, bat: CONFIG.light.seconds, light: true, health: CONFIG.diver.health, flares: CONFIG.flares.count, sprinting: false,
  fear: 0, breathT: 1, heartT: 0, inhale: true, bob: 0,
};
let msgTimer = 0;
function say(text, ms = 3000) { const m = $('msg'); m.textContent = text; m.classList.add('show'); clearTimeout(msgTimer); msgTimer = setTimeout(() => m.classList.remove('show'), ms); }

/* ------------------------------ a criatura ------------------------------ */
const SEG = 34, GAP = 1.25;
const creature = (() => {
  const skinTex = canvasTex(256, (c, s) => {
    c.fillStyle = '#20282a'; c.fillRect(0, 0, s, s);
    for (let i = 0; i < 900; i++) { const g = 10 + rnd() * 40; c.fillStyle = `rgba(${g},${g + 6},${g + 6},0.6)`; c.beginPath(); c.arc(rnd() * s, rnd() * s, 1 + rnd() * 7, 0, 7); c.fill(); }
  }, 2);
  const skin = mat([0.5, 0.58, 0.56], null, 0.12); skin.diffuseTexture = skinTex; skin.specularPower = 12;
  const glowDot = mat([0, 0, 0], [0.2, 0.85, 0.75]), eye = mat([0, 0, 0], [1, 0.72, 0.28]);
  const segs = [];
  for (let i = 0; i < SEG; i++) {
    const t = i / (SEG - 1), r = lerp(0.65, 1.7, sstep(0, 0.2, t)) * (1 - sstep(0.3, 1, t) * 0.93);
    const s = MB.CreateSphere('body', { diameter: r * 2, segments: 10 }, scene); s.material = skin; s.isPickable = false; s.scaling.z = 1.7; s.r = r;
    if (i % 3 === 1 && t < 0.85) for (const side of [-1, 1]) {
      const d = MB.CreateSphere('spot', { diameter: 0.16 + r * 0.07, segments: 4 }, scene); d.parent = s; d.position.set(side * r * 0.86, r * 0.3, 0); d.material = glowDot; d.isPickable = false;
    }
    if (i % 4 === 2 && t > 0.08 && t < 0.8) { // barbatana dorsal
      const fin = MB.CreateCylinder('fin', { diameterTop: 0, diameterBottom: r * 0.75, height: r * 1.3, tessellation: 4 }, scene); fin.parent = s; fin.position.set(0, r * 1.1, -r * 0.2); fin.rotation.x = -0.7; fin.scaling.x = 0.18; fin.material = skin; fin.isPickable = false;
    }
    segs.push(s);
  }
  const head = new BABYLON.TransformNode('head', scene);
  const skull = MB.CreateSphere('skull', { diameterX: 2.5, diameterY: 1.5, diameterZ: 4.4, segments: 10 }, scene); skull.parent = head; skull.position.set(0, 0.28, 0.9); skull.material = skin; skull.isPickable = false;
  const jawPivot = new BABYLON.TransformNode('jawP', scene); jawPivot.parent = head; jawPivot.position.set(0, -0.1, -0.5);
  const jaw = MB.CreateSphere('jaw', { diameterX: 2.2, diameterY: 0.8, diameterZ: 4, segments: 8 }, scene); jaw.parent = jawPivot; jaw.position.set(0, -0.2, 1.5); jaw.material = skin; jaw.isPickable = false;
  const toothM = mat([0.85, 0.85, 0.72], [0.09, 0.09, 0.07]);
  const tooth = (par, x, y, z, h, up) => { const c = MB.CreateCylinder('tooth', { diameterTop: 0, diameterBottom: 0.16, height: h, tessellation: 4 }, scene); c.parent = par; c.position.set(x, y, z); c.rotation.x = up ? 0 : Math.PI; c.material = toothM; c.isPickable = false; };
  for (let i = 0; i < 9; i++) {
    const a = (i - 4) / 4 * 1.25, x = Math.sin(a) * 1.02, z = Math.cos(a) * 1.75;
    tooth(head, x, -0.3, 0.95 + z, 0.75 + (i % 2) * 0.35, false);
    tooth(jawPivot, x * 0.9, 0.3, 1.45 + z * 0.92, 0.55 + ((i + 1) % 2) * 0.3, true);
  }
  for (const side of [-1, 1]) for (const [z, y, d] of [[1.85, 0.72, 0.3], [1.2, 0.86, 0.2], [0.55, 0.92, 0.15]]) {
    const e = MB.CreateSphere('eye', { diameter: d, segments: 6 }, scene); e.parent = head; e.position.set(side * (0.98 - (1.85 - z) * 0.03), y * 0.72 + 0.1, z); e.material = eye; e.isPickable = false;
  }
  const pts = []; for (let i = 0; i < SEG * 2; i++) pts.push(new V3(0, 0, 0));
  const c = {
    segs, head, jawPivot, skin, eye, pts, pos: new V3(WRECK.x - 20, WRECK.y + 14, WRECK.z + 50), dir: new V3(-0.5, 0, -0.8).normalize(), speed: 0,
    state: 'roam', t: 0, target: null, lead: null, aware: 0, lostT: 0, scentT: 12, moanT: 8, swooshT: 0, wig: 0, biteT: 0, jaw: 0,
  };
  for (let i = 0; i < SEG; i++) c.segs[i].position.copyFrom(c.pos.subtract(c.dir.scale(i * GAP)));
  return c;
})();
const panFor = p => { const a = Math.atan2(p.x - D.pos.x, p.z - D.pos.z); return clamp(Math.sin(a - D.yaw), -1, 1) * 0.85; };
const distToDiver = () => V3.Distance(creature.pos, D.pos);
function pickRoam() {
  const a = Math.random() * 6.283, r = 25 + Math.random() * 110;
  const x = clamp(Math.cos(a) * r, -WORLD + 45, WORLD - 45), z = clamp(Math.sin(a) * r, -WORLD + 45, WORLD - 45);
  return new V3(x, floorY(x, z) + 5 + Math.random() * 16, z);
}
function insideWreck(p) { // dentro do casco, com a luz abafada pelo metal
  const c = Math.cos(WRECK.yaw), s = Math.sin(WRECK.yaw), rx = p.x - WRECK.x, rz = p.z - WRECK.z;
  return Math.abs(rx * c - rz * s) < 5.2 && Math.abs(rx * s + rz * c) < 22 && p.y > WRECK.y && p.y < WRECK.y + 8;
}
function updateCreature(dt) {
  const C = CONFIG.creature, c = creature, d = distToDiver();
  const pace = game.enraged ? C.enraged : 1;
  c.t += dt;
  // sentidos: a luz e a pressa denunciam; o casco do naufrágio abafa
  let hear = D.light ? C.hearLightOn : C.hearLightOff;
  if (D.sprinting) hear += C.hearSprint;
  if (insideWreck(D.pos)) hear *= 0.45;
  const noticed = d < hear && D.health > 0;
  c.aware = clamp(c.aware + (noticed ? dt * (d < hear * 0.5 ? 1.4 : 0.6) : -dt * 0.18), 0, 1);
  // sinalizador aceso chama mais que você
  const fl = game.flare;
  if (fl && V3.Distance(fl.pos, c.pos) < CONFIG.flares.lure && c.state !== 'retreat' && c.state !== 'lunge') { c.state = 'lured'; c.lead = fl.pos; }
  else if (c.state === 'lured') { c.state = 'roam'; c.target = null; c.lead = null; }
  // olfato: de vez em quando sabe mais ou menos onde você anda, por isso nunca some de vez
  if ((c.scentT -= dt) <= 0) {
    c.scentT = C.scentEvery / pace * (0.7 + Math.random() * 0.6);
    if (c.state === 'roam' || c.state === 'investigate') {
      const a = Math.random() * 6.283, err = (game.enraged ? 0.4 : 1) * C.scentErr;
      c.lead = new V3(D.pos.x + Math.cos(a) * err, D.pos.y, D.pos.z + Math.sin(a) * err); c.state = 'investigate'; c.t = 0;
    }
  }
  if (c.aware >= 1 && (c.state === 'roam' || c.state === 'investigate')) {
    c.state = 'hunt'; c.t = 0; c.lostT = 0; SND.moan(d, panFor(c.pos), true);
  }
  let want = c.pos, speed = C.roam * pace;
  switch (c.state) {
    case 'roam':
      if (!c.target || V3.Distance(c.target, c.pos) < 8) c.target = pickRoam();
      want = c.target; break;
    case 'investigate':
      want = c.lead; speed = C.investigate * pace;
      if (V3.Distance(c.lead, c.pos) < 8) { c.state = 'roam'; c.target = null; c.lead = null; }
      break;
    case 'lured':
      // circula em volta do sinalizador
      want = fl.pos.add(new V3(Math.cos(game.t * 0.9) * 7, 2 + Math.sin(game.t) * 2, Math.sin(game.t * 0.9) * 7)); speed = C.investigate * pace;
      break;
    case 'hunt':
      // só sabe de você enquanto percebe: apagar a luz e sair dali faz ela chegar em um lugar vazio
      c.lostT = noticed ? 0 : c.lostT + dt;
      if (noticed || !c.lead) c.lead = D.pos.clone();
      want = c.lead; speed = C.hunt * pace;
      if (c.lostT > C.loseAfter || (!noticed && V3.Distance(c.lead, c.pos) < 5)) { c.state = 'investigate'; c.t = 0; c.aware = 0.35; c.lead = c.lead.clone(); break; }
      if (noticed && d < 22 && c.t > 1.4 && !insideWreck(D.pos)) { c.state = 'lunge'; c.t = 0; SND.moan(d, panFor(c.pos), true); }
      break;
    case 'lunge':
      want = D.pos; speed = C.lunge * pace * sstep(0, 0.5, c.t);
      c.jaw = Math.min(1, c.jaw + dt * 2.5);
      if (d < C.biteReach + 0.6) biteDiver();
      else if (c.t > 3.2) { c.state = 'hunt'; c.t = 0; }
      break;
    case 'retreat':
      want = c.target; speed = C.hunt * pace;
      if (c.t > C.retreatFor || V3.Distance(c.target, c.pos) < 10) { c.state = 'roam'; c.target = null; c.aware = 0; c.scentT = Math.min(c.scentT, 5); }
      break;
    case 'frustrated': // bate no casco, sem conseguir entrar
      want = D.pos; speed = C.investigate;
      if (c.t > 4) { c.state = 'roam'; c.target = null; c.aware = 0.2; }
      break;
  }
  if (c.state !== 'lunge') c.jaw = Math.max(0, c.jaw - dt * 1.5);
  // nado: vira aos poucos, sobe por cima do chão e ondula o corpo inteiro
  const to = want.subtract(c.pos); if (to.lengthSquared() > 0.01) to.normalize();
  const turn = (c.state === 'lunge' ? 1.5 : 1.15) * dt;
  c.dir = V3.Lerp(c.dir, to, clamp(turn, 0, 1)).normalize();
  c.speed = lerp(c.speed, speed, clamp(dt * 1.4, 0, 1));
  c.wig += dt * (1.6 + c.speed * 0.42);
  const side = new V3(c.dir.z, 0, -c.dir.x);
  c.pos.addInPlace(c.dir.scale(c.speed * dt)).addInPlace(side.scale(Math.sin(c.wig) * 0.8 * dt));
  const before = c.pos.clone(); pushOut(c.pos, C.headRadius);
  if (V3.DistanceSquared(before, c.pos) > 1e-5 && c.state === 'hunt' && insideWreck(D.pos) && d < 16) { c.state = 'frustrated'; c.t = 0; shakeCam(0.6 * clamp(1 - d / 22, 0.2, 1)); }
  c.pos.y = Math.max(c.pos.y, floorY(c.pos.x, c.pos.z) + 2.2);
  c.pos.y = Math.min(c.pos.y, -8);
  // corpo: cada gomo segue o anterior a uma distância fixa
  c.segs[0].position.copyFrom(c.pos);
  for (let i = 1; i < SEG; i++) {
    const a = c.segs[i - 1].position, b = c.segs[i].position, v = b.subtract(a), L = v.length() || 1;
    b.copyFrom(a.add(v.scale(GAP / L)));
    const wave = Math.sin(c.wig - i * 0.42) * 0.012 * (i + 3) * (0.5 + c.speed * 0.12);
    b.addInPlace(side.scale(wave));
    b.y = Math.max(b.y, floorY(b.x, b.z) + c.segs[i].r * 0.8);
    c.segs[i].lookAt(a);
  }
  c.head.position.copyFrom(c.pos);
  c.head.lookAt(c.pos.add(c.dir));
  c.jawPivot.rotation.x = 0.04 + c.jaw * 0.85 + Math.sin(game.t * 1.3) * 0.03;
  // canto e passagem
  if ((c.moanT -= dt) <= 0) { c.moanT = 16 + Math.random() * 22; SND.moan(d, panFor(c.pos), false); }
  if (d < 34 && (c.swooshT -= dt) <= 0) { c.swooshT = 1.6 + Math.random() * 1.6; SND.swoosh(d, panFor(c.pos)); }
}
function biteDiver() {
  const c = creature, C = CONFIG.creature;
  SND.bite(); D.health -= C.bite; fx.hurt = 1; shakeCam(1.6);
  const push = D.pos.subtract(c.pos); if (push.lengthSquared() > 0.01) push.normalize();
  D.vel.addInPlace(push.scale(10)); D.vel.addInPlace(c.dir.scale(5));
  D.o2 = Math.max(0, D.o2 - 25);      // o traje rasga: perde ar
  bubbles.manualEmitCount = 80;
  // satisfeita, some na escuridão
  const a = Math.atan2(c.dir.x, c.dir.z) + (Math.random() - 0.5) * 1.5, x = clamp(c.pos.x + Math.sin(a) * 110, -WORLD + 45, WORLD - 45), z = clamp(c.pos.z + Math.cos(a) * 110, -WORLD + 45, WORLD - 45);
  c.state = 'retreat'; c.t = 0; c.target = new V3(x, floorY(x, z) + 12, z); c.aware = 0; c.lead = null;
  if (D.health <= 0) endGame('dead', 'DEVORADO', 'Ninguém encontrou o traje.');
  else say('O TRAJE RASGOU — O₂ VAZANDO', 3000);
}

/* ------------------------------ mergulhador ------------------------------ */
let shake = 0;
function shakeCam(v) { shake = Math.max(shake, v); }
function updateDiver(dt) {
  const F = CONFIG.diver, O = CONFIG.o2, sy = Math.sin(D.yaw), cy = Math.cos(D.yaw), sp = Math.sin(D.pitch), cp = Math.cos(D.pitch);
  const fwd = new V3(sy * cp, -sp, cy * cp), right = new V3(cy, 0, -sy);
  let mv = fwd.scale((keys.KeyW ? 1 : 0) - (keys.KeyS ? 1 : 0)).add(right.scale((keys.KeyD ? 1 : 0) - (keys.KeyA ? 1 : 0)));
  mv.y += (keys.Space ? 1 : 0) - ((keys.ControlLeft || keys.KeyC) ? 1 : 0);
  const moving = mv.lengthSquared() > 0.01;
  D.sprinting = moving && (keys.ShiftLeft || keys.ShiftRight) && D.o2 > 0;
  if (moving) mv.normalize();
  const top = D.sprinting ? F.sprint : F.swim;
  D.vel.addInPlace(mv.scale(top * F.accel * dt));
  D.vel.scaleInPlace(Math.exp(-F.drag * dt));
  const speed = D.vel.length(); if (speed > top * 3) D.vel.scaleInPlace(top * 3 / speed);
  D.vel.y -= 0.12 * dt;                 // leve lastro
  D.pos.addInPlace(D.vel.scale(dt));
  pushOut(D.pos, F.radius);
  const fy = floorY(D.pos.x, D.pos.z) + F.radius + 0.25;
  if (D.pos.y < fy) { D.pos.y = fy; D.vel.y = Math.max(D.vel.y, 0); }
  if (D.pos.y > -22) { D.pos.y = -22; D.vel.y = Math.min(D.vel.y, 0); if (!game.ceilMsg) { game.ceilMsg = true; say('SUBIR SEM O CABO É A MORTE: USE O CABO DO BARCO', 3500); setTimeout(() => game.ceilMsg = false, 8000); } }
  D.pos.x = clamp(D.pos.x, -WORLD + 8, WORLD - 8); D.pos.z = clamp(D.pos.z, -WORLD + 8, WORLD - 8);

  // medo: proximidade e ser caçado
  const d = distToDiver(), danger = sstep(55, 8, d) * (creature.state === 'hunt' || creature.state === 'lunge' ? 1 : 0.55) + (creature.state === 'lunge' ? 0.3 : 0);
  D.fear = lerp(D.fear, clamp(danger, 0, 1), clamp(dt * 1.2, 0, 1));
  fx.fear = D.fear; fx.hurt = Math.max(0, fx.hurt - dt * 0.8);

  // oxigênio e bateria
  const use = (D.sprinting ? O.sprintMult : 1) * (1 + D.fear * (O.fearMult - 1));
  D.o2 = Math.max(0, D.o2 - use * dt);
  if (D.o2 <= 0) {
    D.health -= O.drownDps * dt; fx.hurt = Math.max(fx.hurt, 0.5 + Math.sin(game.t * 5) * 0.2);
    if (D.health <= 0) return endGame('dead', 'SEM AR', 'O último fôlego virou bolhas subindo no escuro.');
  }
  if (D.light) { D.bat = Math.max(0, D.bat - dt); if (D.bat <= 0) { D.light = false; say('BATERIA ESGOTADA', 2500); } }
  else D.bat = Math.min(CONFIG.light.seconds, D.bat + CONFIG.light.offRecharge * dt);
  const low = D.bat < 25 && D.light ? (Math.sin(game.t * 19) * Math.sin(game.t * 7) > 0.55 ? 0.15 : 1) : 1;
  torch.intensity = D.light ? TORCH_POWER * low : 0;
  beam.setEnabled(D.light && low === 1);

  // respiração e coração
  if ((D.breathT -= dt) <= 0) {
    D.inhale = !D.inhale;
    const k = D.fear, pace = lerp(1, 0.48, k) * (D.sprinting ? 0.72 : 1);
    D.breathT = (D.inhale ? 1.5 : 1.9) * pace;
    if (D.inhale) SND.breathIn(k); else { SND.breathOut(k); bubbles.manualEmitCount = 14 + Math.floor(k * 30); }
  }
  if (D.fear > 0.18 && (D.heartT -= dt) <= 0) { D.heartT = lerp(1.15, 0.42, D.fear); SND.heart(0.4 + D.fear * 0.8); }

  // ações
  if (pressed.KeyF) { if (D.bat > 0 || D.light) { D.light = !D.light; tone(1800, 1200, 0.03, 0.06, 'square'); } }
  if (pressed.KeyQ && game.sonarCd <= 0) {
    game.sonarCd = CONFIG.sonar.cooldown; game.sonarShow = CONFIG.sonar.showFor; SND.ping(); renderRadar();
    creature.lead = D.pos.clone(); if (creature.state === 'roam') { creature.state = 'investigate'; creature.t = 0; } creature.aware = Math.max(creature.aware, 0.55);
  }
  if (pressed.KeyG && D.flares > 0 && !game.flare) throwFlare(fwd);
  updateInteract();
}
function throwFlare(fwd) {
  D.flares--; SND.flare();
  const m = MB.CreateSphere('flare', { diameter: 0.14, segments: 6 }, scene); m.material = mat([0, 0, 0], [1, 0.18, 0.08]); m.isPickable = false;
  const pos = D.pos.add(fwd.scale(0.8));
  m.position.copyFrom(pos);
  const ps = new BABYLON.ParticleSystem('fs', 120, scene); ps.particleTexture = dot; ps.emitter = m; ps.minSize = 0.05; ps.maxSize = 0.3; ps.minLifeTime = 0.4; ps.maxLifeTime = 1.4; ps.emitRate = 70;
  ps.color1 = new C4(1, 0.4, 0.2, 0.8); ps.color2 = new C4(1, 0.15, 0.05, 0.5); ps.colorDead = new C4(0.3, 0, 0, 0); ps.direction1 = new V3(-0.2, 0.5, -0.2); ps.direction2 = new V3(0.2, 1.2, 0.2); ps.minEmitPower = 0.3; ps.maxEmitPower = 0.8; ps.start();
  game.flare = { mesh: m, ps, pos: m.position, vel: fwd.scale(13), life: CONFIG.flares.life };
}
function updateFlare(dt) {
  const f = game.flare; if (!f) { flareLight.intensity = 0; return; }
  f.life -= dt; f.vel.scaleInPlace(Math.exp(-1.8 * dt)); f.vel.y -= 1.1 * dt; f.pos.addInPlace(f.vel.scale(dt));
  const fy = floorY(f.pos.x, f.pos.z) + 0.1; if (f.pos.y < fy) { f.pos.y = fy; f.vel.scaleInPlace(0.2); }
  flareLight.position.copyFrom(f.pos); flareLight.intensity = 9 * clamp(f.life, 0, 1) * (0.85 + Math.random() * 0.3);
  if (f.life <= 0) { f.ps.stop(); f.mesh.dispose(); setTimeout(() => f.ps.dispose(), 1500); game.flare = null; }
}
function updateInteract() {
  let prompt = '';
  for (const g of goals) {
    if (g.got || V3.Distance(D.pos, g.mesh.position) > 3) continue;
    prompt = '[E] Pegar a caixa de registro';
    if (pressed.KeyE) {
      g.got = true; g.mesh.setEnabled(false); SND.pickup(); renderGoals();
      const left = goals.filter(x => !x.got).length;
      if (left === 0) { game.enraged = true; creature.state = 'hunt'; creature.t = 0; creature.aware = 1; SND.moan(distToDiver(), panFor(creature.pos), true); say('ELE SABE. VOLTE AO CABO, AGORA.', 5000); }
      else say(left + (left === 1 ? ' CAIXA RESTANTE' : ' CAIXAS RESTANTES'), 2500);
    }
  }
  for (const t of tanks) {
    if (t.got || V3.Distance(D.pos, t.mesh.position) > 3) continue;
    prompt = '[E] Trocar o cilindro de O₂';
    if (pressed.KeyE) { t.got = true; t.mesh.setEnabled(false); D.o2 = Math.min(D.o2Max, D.o2 + CONFIG.o2.tankBonus); SND.pickup(); say('+ OXIGÊNIO', 1800); }
  }
  if (Math.hypot(D.pos.x - CABLE.x, D.pos.z - CABLE.z) < 3.5) {
    if (goals.every(g => g.got)) { prompt = '[E] Subir pelo cabo'; if (pressed.KeyE) startAscent(); }
    else prompt = 'Cabo do barco: faltam caixas de registro';
  }
  $('prompt').textContent = prompt;
}
function startAscent() {
  game.cut = { t: 0, from: D.pos.clone() }; $('prompt').textContent = ''; say('', 1);
}
function updateAscent(dt) {
  const c = game.cut; c.t += dt; const k = sstep(0, 11, c.t);
  D.pos.set(CABLE.x + 1.2, lerp(c.from.y, -4, k * k), CABLE.z + 1.2);
  D.pitch = lerp(D.pitch, -1.05, clamp(dt * 0.6, 0, 1));
  const lit = sstep(0.35, 1, k);
  scene.fogDensity = lerp(depthFog(), 0.012, lit);
  const col = C3.Lerp(WATER, new C3(0.18, 0.5, 0.62), lit); scene.fogColor.copyFrom(col); scene.clearColor.set(col.r, col.g, col.b, 1);
  hemi.intensity = lerp(0.28, 1.6, lit);
  // ela persegue até quase a superfície e desiste na claridade
  const cc = creature; if (c.t < 5) { cc.pos.addInPlace(D.pos.subtract(cc.pos).normalize().scale(9 * dt)); }
  if (c.t > 11) { fx.fade = clamp((c.t - 11) / 1.2, 0, 1); }
  if (c.t > 12.2) endGame('win');
}
const depthFog = () => lerp(0.035, 0.075, sstep(-40, -95, D.pos.y));

function endGame(kind, title, text) {
  if (game.over) return; game.over = true;
  try { document.exitPointerLock(); } catch (_) { }
  $('prompt').textContent = '';
  const t = Math.floor(game.t), time = Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
  if (kind === 'win') { $('win').classList.remove('hidden'); $('winS').textContent = 'Você voltou com as 3 caixas em ' + time + '. Não ouça as gravações.'; }
  else { $('dead').classList.remove('hidden'); $('deadT').textContent = title; $('deadS').textContent = text + ' Tempo no fundo: ' + time + '. Caixas recuperadas: ' + goals.filter(g => g.got).length + '/3.'; }
}

/* ------------------------------ HUD ------------------------------ */
function renderGoals() { $('goalList').innerHTML = goals.map(g => `<div class="${g.got ? 'done' : ''}">${g.name}</div>`).join(''); }
function renderRadar() {
  const r = $('radar'), R = CONFIG.sonar.range, dots = goals.filter(g => !g.got).map(g => [g.x, g.z, false]);
  if (distToDiver() < R) dots.push([creature.pos.x, creature.pos.z, true]);
  dots.push([CABLE.x, CABLE.z, false, true]);
  r.innerHTML = dots.map(([x, z, bad]) => {
    const dx = x - D.pos.x, dz = z - D.pos.z, dist = Math.min(Math.hypot(dx, dz), R), a = Math.atan2(dx, dz) - D.yaw;
    const u = 50 + Math.sin(a) * dist / R * 46, v = 50 - Math.cos(a) * dist / R * 46;
    return `<i class="${bad ? 'bad' : ''}" style="left:${u}%;top:${v}%"></i>`;
  }).join('');
}
function updateHud(dt) {
  const o = D.o2 / D.o2Max;
  $('o2Bar').firstElementChild.style.width = o * 100 + '%'; $('o2Bar').classList.toggle('low', o < 0.2);
  $('o2Txt').textContent = Math.floor(D.o2 / 60) + ':' + String(Math.floor(D.o2 % 60)).padStart(2, '0');
  const b = D.bat / CONFIG.light.seconds; $('batBar').firstElementChild.style.width = b * 100 + '%';
  $('batTxt').textContent = D.light ? Math.round(b * 100) + '%' : 'DESLIGADA';
  $('flareN').textContent = '×' + D.flares; $('depth').textContent = Math.round(-D.pos.y) + ' m';
  game.sonarCd = Math.max(0, game.sonarCd - dt);
  game.sonarShow = Math.max(0, game.sonarShow - dt);
  $('radar').classList.toggle('on', game.sonarShow > 0);
  $('sonarTxt').textContent = game.sonarCd > 0 ? 'SONAR ' + Math.ceil(game.sonarCd) + 's' : 'SONAR PRONTO [Q]';
}

/* ------------------------------ entrada ------------------------------ */
addEventListener('keydown', e => {
  if (!e.repeat) pressed[e.code] = true; keys[e.code] = true;
  if (game.started && (e.code === 'Space' || e.code === 'ControlLeft' || e.code.startsWith('Arrow'))) e.preventDefault();
});
addEventListener('keyup', e => { keys[e.code] = false; });
canvas.addEventListener('contextmenu', e => e.preventDefault());
const lockMouse = () => { try { Promise.resolve(canvas.requestPointerLock()).catch(() => { }); } catch (_) { } };
canvas.addEventListener('pointerdown', () => { if (game.started && !game.over && document.pointerLockElement !== canvas) lockMouse(); });
document.addEventListener('mousemove', e => {
  if (document.pointerLockElement !== canvas || game.cut) return;
  D.yaw += e.movementX * 0.0021; D.pitch = clamp(D.pitch + e.movementY * 0.0021, -1.45, 1.45);
});
$('start').addEventListener('click', () => {
  game.started = true; $('start').classList.add('hidden'); initAudio(); lockMouse();
  renderGoals(); say('ENCONTRE AS CAIXAS. O SONAR [Q] MOSTRA ONDE ESTÃO.', 6000);
  setTimeout(() => { if (!game.over) SND.moan(distToDiver(), panFor(creature.pos), false); }, 3500);
});
for (const id of ['dead', 'win']) $(id).addEventListener('click', () => location.reload());
addEventListener('resize', () => engine.resize());

/* ------------------------------ loop ------------------------------ */
scene.onBeforeRenderObservable.add(() => {
  const dt = Math.min(engine.getDeltaTime() / 1000, 0.05);
  if (game.started && !game.over) {
    game.t += dt;
    if (game.cut) updateAscent(dt);
    else {
      updateDiver(dt);
      if (!game.over) { updateCreature(dt); scene.fogDensity = depthFog(); }
    }
    updateFlare(dt);
    updateHud(dt);
  }
  // câmera do capacete
  if (!keys.__none) {
    D.bob += dt; D.roll = lerp(D.roll, ((keys.KeyD ? 1 : 0) - (keys.KeyA ? 1 : 0)) * -0.05, clamp(dt * 2, 0, 1));
    const swayX = Math.sin(D.bob * 0.7) * 0.012, swayY = Math.sin(D.bob * 1.05) * 0.016;
    if (shake > 0) shake = Math.max(0, shake - dt * 1.4);
    const sk = shake * shake;
    camera.position.set(D.pos.x + (Math.random() - 0.5) * sk * 0.3, D.pos.y + swayY * 3 + (Math.random() - 0.5) * sk * 0.3, D.pos.z);
    camera.rotation.set(D.pitch + swayY + (Math.random() - 0.5) * sk * 0.05, D.yaw + swayX + (Math.random() - 0.5) * sk * 0.05, D.roll + Math.sin(D.bob * 0.5) * 0.012);
  }
  snow.emitter.copyFrom(D.pos); bubbles.emitter.copyFrom(D.pos);
  const time = performance.now() / 1000;
  for (const k of kelp) k.rotation.z = Math.sin(time * 0.6 + k.phase) * 0.09;
  beaconMat.emissiveColor.r = Math.sin(time * 4) > 0.6 ? 1 : 0.08;
  for (const k in pressed) pressed[k] = false;
});
engine.runRenderLoop(() => scene.render());

// atalho de depuração para testes
window.__abissal = { game, D, creature, goals, tanks, CONFIG, floorY, endGame, startAscent };
