// 3D Pylos board for the viewer prototype (three.js r170, pinned on jsDelivr).
// One Board3D per canvas. It draws a snapshot from pylos.js and animates the
// difference to the next one. Rendering choices are a design proposal.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { squareOf, allSquares } from './pylos.js';

const R = 0.5;                       // ball radius; balls on one level touch
const LIFT = (2 * R) / Math.SQRT2;   // height gained per level in a square pyramid
const PLATE = 5.3;
const ICE = 0x8fdcff;
// Base cups: round holes in the steel whose spherical floor is concentric with
// a resting ball. The hole diameter at the surface stays 2 x 0.416, so a level-a
// ball sinks until its centre is SINK above the surface.
const HOLE = 0.416;
const SINK = Math.sqrt(R * R - HOLE * HOLE);   // ≈ 0.277
const CUP = R + 0.006;                         // floor radius, a hair larger than the ball
const SLAB = 0.3;                              // thickness of the drilled top plate

export function worldOf(id) {
  const s = squareOf(id);
  const n = 4 - s.level;
  return new THREE.Vector3(s.col - (n + 1) / 2, SINK + s.level * LIFT, s.row - (n + 1) / 2);
}

const PRESETS = {
  perspective: { pos: [0, 6.4, 7.9], target: [0, 0.55, 0] },
  top:         { pos: [0, 11.2, 0.01], target: [0, 0, 0] },
  side:        { pos: [0, 1.6, 9.6], target: [0, 1.0, 0] },
  corner:      { pos: [6.9, 5.0, 6.9], target: [0, 0.8, 0] },
};

function plateTexture() {
  const S = 1024, c = document.createElement('canvas');
  c.width = c.height = S;
  const g = c.getContext('2d');
  // brushed steel: base + many faint horizontal strokes
  g.fillStyle = '#7d8790'; g.fillRect(0, 0, S, S);
  for (let i = 0; i < 2600; i++) {
    const y = Math.random() * S, a = Math.random() * 0.06;
    g.strokeStyle = Math.random() < 0.5 ? `rgba(255,255,255,${a})` : `rgba(10,20,30,${a})`;
    g.lineWidth = Math.random() * 1.6;
    g.beginPath(); g.moveTo(0, y); g.lineTo(S, y + (Math.random() - 0.5) * 4); g.stroke();
  }
  const px = (u) => ((u + PLATE / 2) / PLATE) * S; // world -> texture
  // a darker machined ring around each hole (the holes themselves are geometry)
  for (let r = 1; r <= 4; r++) for (let col = 1; col <= 4; col++) {
    const x = px(col - 2.5), y = px(r - 2.5), rad = (HOLE / PLATE) * S;
    g.strokeStyle = 'rgba(12,18,24,0.55)'; g.lineWidth = 7;
    g.beginPath(); g.arc(x, y, rad + 4, 0, Math.PI * 2); g.stroke();
    g.strokeStyle = 'rgba(255,255,255,0.18)'; g.lineWidth = 2;
    g.beginPath(); g.arc(x, y, rad + 9, 0, Math.PI * 2); g.stroke();
  }
  // engraved frame and coordinates (row 1 at the back, column 1 on the left)
  g.strokeStyle = 'rgba(20,28,34,0.55)'; g.lineWidth = 4;
  g.strokeRect(px(-2.3), px(-2.3), px(2.3) - px(-2.3), px(2.3) - px(-2.3));
  g.fillStyle = 'rgba(18,26,32,0.85)';
  g.font = '600 38px "Chakra Petch", "Barlow", sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  for (let i = 1; i <= 4; i++) {
    g.fillText(String(i), px(i - 2.5), px(-2.48));       // columns along the back edge
    g.fillText(String(i), px(-2.48), px(i - 2.5));       // rows along the left edge
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

export class Board3D {
  constructor(host, { onHover } = {}) {
    this.host = host;
    this.onHover = onHover || (() => {});
    this.balls = new Map();      // square id -> mesh
    this.anims = [];
    this.maxLevel = 3;
    this.visible = true;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    host.appendChild(renderer.domElement);
    this.renderer = renderer;

    const scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environmentIntensity = 0.75;
    this.scene = scene;

    const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100);
    this.camera = camera;
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.minDistance = 5; controls.maxDistance = 16;
    controls.maxPolarAngle = Math.PI * 0.49;
    controls.enablePan = false;
    this.controls = controls;
    this.setCamera('perspective', false);

    // cold key light from the upper left, blue rim from behind
    const key = new THREE.DirectionalLight(0xdcecff, 2.2);
    key.position.set(-4, 9, 5); key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    Object.assign(key.shadow.camera, { left: -4, right: 4, top: 4, bottom: -4 });
    key.shadow.radius = 4;
    scene.add(key);
    const rim = new THREE.DirectionalLight(0x5aa8ff, 1.4);
    rim.position.set(3, 3, -7); scene.add(rim);
    scene.add(new THREE.HemisphereLight(0xbcd8ff, 0x0b0f14, 0.35));

    // plate: a squarish block of steel with a brushed, engraved top
    const body = new THREE.Mesh(
      new RoundedBoxGeometry(PLATE, 0.16, PLATE, 3, 0.05),
      new THREE.MeshStandardMaterial({ color: 0x5f6870, metalness: 1, roughness: 0.38 }),
    );
    body.position.y = -SLAB - 0.04; body.receiveShadow = true; scene.add(body);

    // drilled top plate: a square slab with 16 round holes cut through it
    const W = PLATE - 0.1;
    const outline = new THREE.Shape();
    outline.moveTo(-W / 2, -W / 2); outline.lineTo(W / 2, -W / 2);
    outline.lineTo(W / 2, W / 2); outline.lineTo(-W / 2, W / 2); outline.closePath();
    for (let r = 1; r <= 4; r++) for (let c = 1; c <= 4; c++) {
      const hole = new THREE.Path();
      // shape y becomes -z after the slab is laid flat
      hole.absarc(c - 2.5, -(r - 2.5), HOLE + 0.002, 0, Math.PI * 2, true);
      outline.holes.push(hole);
    }
    const slabGeo = new THREE.ExtrudeGeometry(outline, { depth: SLAB, bevelEnabled: false, curveSegments: 48 });
    const tex = plateTexture();
    tex.repeat.set(1 / PLATE, 1 / PLATE); tex.offset.set(0.5, 0.5);
    tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
    // group 0 = top/bottom faces (brushed, engraved), group 1 = outer edges and hole walls (plain steel)
    const slab = new THREE.Mesh(slabGeo, [
      new THREE.MeshStandardMaterial({ map: tex, metalness: 0.85, roughness: 0.46 }),
      new THREE.MeshStandardMaterial({ color: 0x6b757e, metalness: 1, roughness: 0.34 }),
    ]);
    slab.rotation.x = -Math.PI / 2; slab.position.y = -SLAB;
    slab.receiveShadow = true; slab.castShadow = true; scene.add(slab);

    // the cups: the lower cap of a sphere centred where a resting ball's centre is,
    // seen from inside. Its rim meets the surface exactly at the hole edge.
    const theta0 = Math.acos(-SINK / CUP);
    const cupGeo = new THREE.SphereGeometry(CUP, 48, 16, 0, Math.PI * 2, theta0, Math.PI - theta0);
    const cupMat = new THREE.MeshStandardMaterial({ color: 0x3e4851, metalness: 1, roughness: 0.34, side: THREE.BackSide });
    for (let r = 1; r <= 4; r++) for (let c = 1; c <= 4; c++) {
      const cup = new THREE.Mesh(cupGeo, cupMat);
      cup.position.set(c - 2.5, SINK, r - 2.5);
      cup.receiveShadow = true; scene.add(cup);
    }

    this.geo = new THREE.SphereGeometry(R * 0.985, 64, 40);
    this.mat = {
      W: new THREE.MeshPhysicalMaterial({ color: 0xe2e9ee, metalness: 1, roughness: 0.24, clearcoat: 0.5, clearcoatRoughness: 0.08 }),
      B: new THREE.MeshPhysicalMaterial({ color: 0x2a3036, metalness: 0.9, roughness: 0.28, clearcoat: 0.6, clearcoatRoughness: 0.2 }),
    };
    this.ghostMat = new THREE.MeshStandardMaterial({ color: ICE, transparent: true, opacity: 0.16, depthWrite: false, emissive: ICE, emissiveIntensity: 0.25 });
    this.ringMat = new THREE.MeshBasicMaterial({ color: ICE, transparent: true, opacity: 0.95 });
    this.shapeMat = new THREE.MeshBasicMaterial({ color: ICE, transparent: true, opacity: 0.4 });
    this.marks = new THREE.Group(); scene.add(this.marks);

    // hover picking
    this.ray = new THREE.Raycaster(); this.pointer = new THREE.Vector2();
    renderer.domElement.addEventListener('pointermove', (e) => this.pick(e));
    renderer.domElement.addEventListener('pointerleave', () => this.onHover(null));

    new ResizeObserver(() => this.resize()).observe(host);
    new IntersectionObserver(([e]) => { this.visible = e.isIntersecting; }).observe(host);
    this.resize();
    this.clock = new THREE.Clock();
    renderer.setAnimationLoop(() => this.frame());
  }

  resize() {
    const w = this.host.clientWidth || 1, h = this.host.clientHeight || 1;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    // keep the whole plate in frame on tall/narrow canvases
    this.camera.fov = w / h < 1 ? 34 / Math.max(w / h, 0.55) : 34;
    this.camera.updateProjectionMatrix();
  }

  setCamera(name, animate = true) {
    const p = PRESETS[name];
    const to = new THREE.Vector3(...p.pos), tt = new THREE.Vector3(...p.target);
    if (!animate) { this.camera.position.copy(to); this.controls.target.copy(tt); this.controls.update(); return; }
    const from = this.camera.position.clone(), ft = this.controls.target.clone();
    this.anims.push({ t: 0, dur: 0.7, step: (k) => {
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      this.camera.position.lerpVectors(from, to, e);
      this.controls.target.lerpVectors(ft, tt, e);
    } });
  }

  setMaxLevel(l) {
    this.maxLevel = l;
    this.balls.forEach((m, id) => { m.visible = squareOf(id).level <= l; });
    this.marks.children.forEach((m) => { m.visible = m.userData.level <= l; });
  }

  ballMesh(id, colour) {
    const m = new THREE.Mesh(this.geo, this.mat[colour]);
    m.castShadow = true; m.receiveShadow = true;
    m.userData = { id, colour };
    m.position.copy(worldOf(id));
    m.visible = squareOf(id).level <= this.maxLevel;
    this.scene.add(m);
    return m;
  }

  // Draw a snapshot; when animate is true, animate the move that produced it.
  show(snap, animate = false) {
    const mv = snap.move;
    const want = snap.board;
    // finish running ball animations so positions are exact
    this.anims = this.anims.filter((a) => { if (a.ball) { a.step(1); return false; } return true; });

    if (animate && mv && mv.kind === 'raise' && this.balls.has(mv.from) && !this.balls.has(mv.to)) {
      const m = this.balls.get(mv.from); this.balls.delete(mv.from); this.balls.set(mv.to, m);
      m.userData.id = mv.to;
      const a = worldOf(mv.from), b = worldOf(mv.to);
      const peak = Math.max(a.y, b.y) + 1.1;
      m.visible = squareOf(mv.to).level <= this.maxLevel;
      this.anims.push({ ball: true, t: 0, dur: 0.55, step: (k) => {
        const e = 1 - Math.pow(1 - k, 3);
        m.position.lerpVectors(a, b, e);
        m.position.y = (1 - e) * (1 - e) * a.y + 2 * (1 - e) * e * peak + e * e * b.y;
      } });
    }
    // remove balls that are gone (take-backs shrink away when animated)
    for (const [id, m] of [...this.balls]) {
      if (want[id] === m.userData.colour) continue;
      this.balls.delete(id);
      if (animate) {
        this.anims.push({ ball: true, t: 0, dur: 0.35, step: (k) => {
          m.scale.setScalar(1 - k); if (k >= 1) this.scene.remove(m);
        } });
      } else this.scene.remove(m);
    }
    // add new balls (a placed ball drops onto its square)
    for (const id of Object.keys(want)) {
      if (this.balls.has(id)) continue;
      const m = this.ballMesh(id, want[id]);
      this.balls.set(id, m);
      if (animate && mv && mv.to === id) {
        const b = worldOf(id), a = b.clone().setY(b.y + 2.2);
        this.anims.push({ ball: true, t: 0, dur: 0.45, step: (k) => {
          const e = k * k; m.position.lerpVectors(a, b, e);
        } });
      }
    }
    this.mark(mv, want);
  }

  mark(mv, board) {
    this.marks.clear();
    if (!mv) return;
    const ring = (id, mat, r = R * 1.07, tube = 0.022) => {
      const p = worldOf(id);
      const t = new THREE.Mesh(new THREE.TorusGeometry(r, tube, 12, 64), mat);
      t.rotation.x = Math.PI / 2; t.position.copy(p);
      t.userData.level = squareOf(id).level; this.marks.add(t);
    };
    mv.shapes.forEach((s) => s.squares.forEach((id) => { if (id !== mv.to && board[id]) ring(id, this.shapeMat, R * 1.04, 0.014); }));
    if (board[mv.to]) ring(mv.to, this.ringMat);
    const ghost = (id) => {
      if (board[id]) return;
      const g = new THREE.Mesh(this.geo, this.ghostMat);
      g.position.copy(worldOf(id)); g.userData.level = squareOf(id).level; this.marks.add(g);
    };
    mv.takeBacks.forEach(ghost);
    if (mv.kind === 'raise') {
      ghost(mv.from);
      const a = worldOf(mv.from), b = worldOf(mv.to);
      const mid = a.clone().lerp(b, 0.5); mid.y = Math.max(a.y, b.y) + 1.1;
      const pts = new THREE.QuadraticBezierCurve3(a, mid, b).getPoints(40);
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts),
        new THREE.LineDashedMaterial({ color: ICE, dashSize: 0.12, gapSize: 0.08, transparent: true, opacity: 0.9 }));
      line.computeLineDistances(); line.userData.level = 0; this.marks.add(line);
    }
    this.setMaxLevel(this.maxLevel);
  }

  pick(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    this.pointer.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    this.ray.setFromCamera(this.pointer, this.camera);
    const hit = this.ray.intersectObjects([...this.balls.values()].filter((m) => m.visible))[0];
    this.onHover(hit ? { id: hit.object.userData.id, colour: hit.object.userData.colour, x: e.clientX - r.left, y: e.clientY - r.top } : null);
  }

  frame() {
    const dt = this.clock.getDelta();
    if (!this.visible && !this.anims.length) return;
    this.anims = this.anims.filter((a) => {
      a.t = Math.min(1, a.t + dt / a.dur); a.step(a.t); return a.t < 1;
    });
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }
}

export const SQUARES = allSquares();
