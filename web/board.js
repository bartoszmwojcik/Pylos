// board.js — the 3D view of one Pylos position, drawn with Three.js.
//
// The look is the owner-accepted design prototype (.ai/prototypes/viewer-3d,
// accepted 2026-11-23): a brushed, engraved steel plate with 16 drilled cups,
// polished silver (White) and gunmetal (Black) balls, a cool key light and a
// blue rim light.
//
// BoardView owns a <canvas> inside a container element. The app calls
//   view.show(entry, animate)
// with one entry of the game history (see buildHistory in notation.js):
//   { position, move }   — move is null for the start position.
// The view compares the balls it shows with the new position and changes only
// what differs, so a move can be animated from where the balls are now:
//   * a placed ball drops into its square,
//   * a raised ball flies along an arc from its old square,
//   * each taken-back ball shrinks away after the move has landed.
// It also draws the marks of the move: an ice ring on the moved ball, thin
// rings on the balls of a completed shape (R07), translucent "ghosts" where
// a ball left (raise origin, take-backs) and a dashed arc for a raise.

import * as THREE from './vendor/three.module.min.js';
import { OrbitControls } from './vendor/OrbitControls.js';
import { RoomEnvironment } from './vendor/RoomEnvironment.js';
import { RoundedBoxGeometry } from './vendor/RoundedBoxGeometry.js';
import { parseSquare, sideOf, placeableSquares } from './notation.js';

// ---------------------------------------------------------------------------
// Geometry: where does the ball on a square sit?
//
// All balls have diameter D = 1 (radius R = 0.5), so one unit = one ball.
//
// Level a. The plate is drilled with 16 round cups. A cup's hole at the
// surface has radius HOLE = 0.416, i.e. a diameter 0.83 of the ball's, so a
// ball sinks into it until it touches the hole's rim. The rim, the ball's
// centre and the point of contact form a right triangle with hypotenuse R:
// the centre sits SINK = √(R² − HOLE²) ≈ 0.28 above the surface (y = 0).
//
// Higher levels. A ball on level b, c or d rests on four touching balls whose
// centres form a square of side D. Its centre is straight above the middle of
// that square. The horizontal distance from that middle to each lower centre
// is half the square's diagonal: D·√2 / 2 = D/√2. The upper ball touches each
// lower ball, so the distance between the centres is exactly D. By Pythagoras
// the rise h satisfies h² + (D/√2)² = D², so h = D/√2. Every level adds the
// same rise, so level L (a=0, b=1, c=2, d=3) has its centre at
//   y = SINK + L · D/√2.
//
// Horizontal position. Level L has n = 4 − L squares per side, spaced D
// apart. We centre each level on the origin: column c (1-based) is at
//   x = (c − 1 − (n − 1)/2) · D,   and row r likewise gives z.
// Check: square (r,c) on level b should sit between columns c and c+1 of
// level a. Level a gives ((c−1) + c)/2 − 3/2 = c − 2; level b gives
// c − 1 − 1 = c − 2. The same holds for every level, so the formula puts each
// ball exactly in the hollow between its four supports (R08).
// ---------------------------------------------------------------------------
const D = 1;
const R = D / 2;
const RISE = D / Math.SQRT2;
const HOLE = 0.416; // radius of a cup's hole at the plate surface
const SINK = Math.sqrt(R * R - HOLE * HOLE); // ≈ 0.277: a level-a centre above the surface
const CUP = R + 0.006; // the cup's spherical floor, a hair larger than the ball
const SLAB = 0.3; // thickness of the drilled top plate
const PLATE = 5.3; // width of the steel plate
const ICE = 0x8fdcff; // the one accent colour of the design

/** The centre of a ball on the named square, as a THREE.Vector3. */
export function squareCentre(name) {
  const { level, row, col } = parseSquare(name);
  const mid = (sideOf(level) - 1) / 2;
  return new THREE.Vector3((col - 1 - mid) * D, SINK + level * RISE, (row - 1 - mid) * D);
}

const levelOf = (name) => parseSquare(name).level;

// The four camera presets of the design: [camera position, point looked at].
const PRESETS = {
  perspective: { pos: [0, 6.4, 7.9], target: [0, 0.55, 0] },
  top: { pos: [0, 11.2, 0.01], target: [0, 0, 0] },
  side: { pos: [0, 1.6, 9.6], target: [0, 1.0, 0] },
  corner: { pos: [6.9, 5.0, 6.9], target: [0, 0.8, 0] },
};

// Animation timing (seconds). `?slowmo=5` in the URL makes every animation
// 5 times slower, to see (or screenshot) what happens.
const SLOWMO = Number(new URLSearchParams(window.location.search).get('slowmo')) || 1;
const DROP_S = 0.45 * SLOWMO; // a placed ball falling into its square
const ARC_S = 0.55 * SLOWMO; // a raised ball flying to its new square
const TAKE_S = 0.35 * SLOWMO; // a taken-back ball shrinking away
const TAKE_GAP_S = 0.12 * SLOWMO; // pause between two take-backs

/** Deterministic pseudo-random numbers, so the plate looks the same each load. */
function seededRandom(seed) {
  return () => (seed = (seed * 16807) % 2147483647) / 2147483647;
}

/**
 * Paint the plate's top face on a canvas: brushed steel (many faint
 * horizontal strokes), a dark machined ring round each hole, an engraved
 * frame, and the row/column numbers (row 1 at the back, column 1 on the left).
 */
function paintPlate(canvas) {
  const S = canvas.width;
  const g = canvas.getContext('2d');
  const rand = seededRandom(11);
  g.fillStyle = '#7d8790';
  g.fillRect(0, 0, S, S);
  for (let i = 0; i < 2600; i++) {
    const y = rand() * S;
    const a = rand() * 0.06;
    g.strokeStyle = rand() < 0.5 ? `rgba(255,255,255,${a})` : `rgba(10,20,30,${a})`;
    g.lineWidth = rand() * 1.6;
    g.beginPath();
    g.moveTo(0, y);
    g.lineTo(S, y + (rand() - 0.5) * 4);
    g.stroke();
  }
  const px = (u) => ((u + PLATE / 2) / PLATE) * S; // world x/z -> texture pixels
  for (let r = 1; r <= 4; r++) {
    for (let c = 1; c <= 4; c++) {
      const x = px(c - 2.5);
      const y = px(r - 2.5);
      const rad = (HOLE / PLATE) * S;
      g.strokeStyle = 'rgba(12,18,24,0.55)';
      g.lineWidth = 7;
      g.beginPath();
      g.arc(x, y, rad + 4, 0, Math.PI * 2);
      g.stroke();
      g.strokeStyle = 'rgba(255,255,255,0.18)';
      g.lineWidth = 2;
      g.beginPath();
      g.arc(x, y, rad + 9, 0, Math.PI * 2);
      g.stroke();
    }
  }
  g.strokeStyle = 'rgba(20,28,34,0.55)';
  g.lineWidth = 4;
  g.strokeRect(px(-2.3), px(-2.3), px(2.3) - px(-2.3), px(2.3) - px(-2.3));
  g.fillStyle = 'rgba(18,26,32,0.85)';
  g.font = '600 38px "Chakra Petch", "Barlow", sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  for (let i = 1; i <= 4; i++) {
    g.fillText(String(i), px(i - 2.5), px(-2.48)); // columns along the back edge
    g.fillText(String(i), px(-2.48), px(i - 2.5)); // rows along the left edge
  }
}

export class BoardView {
  /**
   * container — the element the canvas fills.
   * onHover   — called with { square, colour, x, y } when the pointer is over
   *             a ball (x, y in container pixels), or null when it is not.
   */
  constructor(container, { onHover = () => {} } = {}) {
    this.container = container;
    this.onHover = onHover;
    this.balls = new Map(); // square name -> ball mesh currently shown
    this.anims = []; // running animations: { t, dur, delay, step(k), ball }
    this.maxLevel = 3; // the level filter: levels above this are hidden

    // Renderer. preserveDrawingBuffer lets screenshots read the canvas.
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(renderer.domElement);
    this.renderer = renderer;

    // Metal needs something to reflect: a soft built-in "room" environment.
    this.scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environmentIntensity = 0.75;

    // Camera and OrbitControls: drag rotates, wheel zooms (no panning).
    this.camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100);
    this.controls = new OrbitControls(this.camera, renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.minDistance = 5;
    this.controls.maxDistance = 16;
    this.controls.maxPolarAngle = Math.PI * 0.49; // stay above the plate
    this.controls.enablePan = false;
    this.setCamera('perspective', false);

    this.#addLights();
    this.#addPlate();

    // Shared geometry and materials (made once, reused by every ball and mark).
    this.ballGeometry = new THREE.SphereGeometry(R * 0.985, 64, 40);
    this.materials = {
      white: new THREE.MeshPhysicalMaterial({ color: 0xe2e9ee, metalness: 1, roughness: 0.24, clearcoat: 0.5, clearcoatRoughness: 0.08 }),
      black: new THREE.MeshPhysicalMaterial({ color: 0x2a3036, metalness: 0.9, roughness: 0.28, clearcoat: 0.6, clearcoatRoughness: 0.2 }),
      ghost: new THREE.MeshStandardMaterial({ color: ICE, transparent: true, opacity: 0.16, depthWrite: false, emissive: ICE, emissiveIntensity: 0.25 }),
      ring: new THREE.MeshBasicMaterial({ color: ICE, transparent: true, opacity: 0.95 }),
      shape: new THREE.MeshBasicMaterial({ color: ICE, transparent: true, opacity: 0.4 }),
      marker: new THREE.MeshBasicMaterial({ color: ICE, transparent: true, opacity: 0.35, depthWrite: false }),
      arc: new THREE.LineDashedMaterial({ color: ICE, dashSize: 0.12, gapSize: 0.08, transparent: true, opacity: 0.9 }),
    };
    this.ringGeometry = new THREE.TorusGeometry(R * 1.07, 0.022, 12, 64);
    this.shapeRingGeometry = new THREE.TorusGeometry(R * 1.04, 0.014, 12, 64);
    this.markerGeometry = new THREE.SphereGeometry(0.08, 16, 12);

    // The marks of the shown move (rings, ghosts, arc, placeable markers)
    // live in one group that is rebuilt on every show().
    this.marks = new THREE.Group();
    this.scene.add(this.marks);

    // Hover picking: cast a ray from the pointer into the scene.
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    renderer.domElement.addEventListener('pointermove', (e) => this.#pick(e));
    renderer.domElement.addEventListener('pointerleave', () => this.onHover(null));

    // Resize with the container (which resizes with the window).
    new ResizeObserver(() => this.#resize()).observe(container);
    this.#resize();

    this.clock = new THREE.Clock();
    renderer.setAnimationLoop(() => this.#frame());
  }

  #addLights() {
    // A cold key light from the upper left (it casts the shadows) ...
    const key = new THREE.DirectionalLight(0xdcecff, 2.2);
    key.position.set(-4, 9, 5);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    Object.assign(key.shadow.camera, { left: -4, right: 4, top: 4, bottom: -4 });
    key.shadow.radius = 4;
    this.scene.add(key);
    // ... a blue rim light from behind, and a faint sky/ground fill.
    const rim = new THREE.DirectionalLight(0x5aa8ff, 1.4);
    rim.position.set(3, 3, -7);
    this.scene.add(rim);
    this.scene.add(new THREE.HemisphereLight(0xbcd8ff, 0x0b0f14, 0.35));
  }

  #addPlate() {
    // The body: a squarish block of steel with slightly rounded edges.
    const body = new THREE.Mesh(
      new RoundedBoxGeometry(PLATE, 0.16, PLATE, 3, 0.05),
      new THREE.MeshStandardMaterial({ color: 0x5f6870, metalness: 1, roughness: 0.38 }),
    );
    body.position.y = -SLAB - 0.04;
    body.receiveShadow = true;
    this.scene.add(body);

    // The drilled top plate: a square outline with 16 round holes, extruded.
    const W = PLATE - 0.1;
    const outline = new THREE.Shape();
    outline.moveTo(-W / 2, -W / 2);
    outline.lineTo(W / 2, -W / 2);
    outline.lineTo(W / 2, W / 2);
    outline.lineTo(-W / 2, W / 2);
    outline.closePath();
    for (let r = 1; r <= 4; r++) {
      for (let c = 1; c <= 4; c++) {
        const hole = new THREE.Path();
        // The shape's y axis becomes −z once the slab is laid flat.
        hole.absarc(c - 2.5, -(r - 2.5), HOLE + 0.002, 0, Math.PI * 2, true);
        outline.holes.push(hole);
      }
    }
    const slabGeometry = new THREE.ExtrudeGeometry(outline, { depth: SLAB, bevelEnabled: false, curveSegments: 48 });

    // The top face's texture is painted on a canvas. The numbers use the
    // Chakra Petch font, which may still be loading: repaint once it is ready.
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1024;
    paintPlate(canvas);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    // ExtrudeGeometry's UVs are the shape's x/y in world units: map them to 0..1.
    tex.repeat.set(1 / PLATE, 1 / PLATE);
    tex.offset.set(0.5, 0.5);
    tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
    document.fonts?.load('600 38px "Chakra Petch"').then(() => {
      paintPlate(canvas);
      tex.needsUpdate = true;
    }, () => {});

    // Material 0 = top and bottom faces (brushed, engraved),
    // material 1 = outer edges and hole walls (plain steel).
    const slab = new THREE.Mesh(slabGeometry, [
      new THREE.MeshStandardMaterial({ map: tex, metalness: 0.85, roughness: 0.46 }),
      new THREE.MeshStandardMaterial({ color: 0x6b757e, metalness: 1, roughness: 0.34 }),
    ]);
    slab.rotation.x = -Math.PI / 2;
    slab.position.y = -SLAB;
    slab.receiveShadow = true;
    slab.castShadow = true;
    this.scene.add(slab);

    // The cups: the lower cap of a sphere centred where a resting ball's
    // centre is, seen from inside. theta0 is the polar angle at which that
    // sphere crosses the plate surface (y = 0), so the cap's rim meets the
    // surface exactly at the hole's edge.
    const theta0 = Math.acos(-SINK / CUP);
    const cupGeometry = new THREE.SphereGeometry(CUP, 48, 16, 0, Math.PI * 2, theta0, Math.PI - theta0);
    const cupMaterial = new THREE.MeshStandardMaterial({ color: 0x3e4851, metalness: 1, roughness: 0.34, side: THREE.BackSide });
    for (let r = 1; r <= 4; r++) {
      for (let c = 1; c <= 4; c++) {
        const cup = new THREE.Mesh(cupGeometry, cupMaterial);
        cup.position.set(c - 2.5, SINK, r - 2.5);
        cup.receiveShadow = true;
        this.scene.add(cup);
      }
    }
  }

  /** Move the camera to one of the presets: perspective, top, side, corner. */
  setCamera(name, animate = true) {
    const p = PRESETS[name];
    const to = new THREE.Vector3(...p.pos);
    const target = new THREE.Vector3(...p.target);
    if (!animate) {
      this.camera.position.copy(to);
      this.controls.target.copy(target);
      this.controls.update();
      return;
    }
    const from = this.camera.position.clone();
    const fromTarget = this.controls.target.clone();
    this.#animate(0.7, (k) => {
      const e = k < 0.5 ? 2 * k * k : 1 - (-2 * k + 2) ** 2 / 2; // ease in and out
      this.camera.position.lerpVectors(from, to, e);
      this.controls.target.lerpVectors(fromTarget, target, e);
    });
  }

  /** The level filter: show levels 0..maxLevel only (3 = all). */
  setMaxLevel(maxLevel) {
    this.maxLevel = maxLevel;
    this.balls.forEach((mesh, sq) => (mesh.visible = levelOf(sq) <= maxLevel));
    this.marks.children.forEach((m) => (m.visible = m.userData.level <= maxLevel));
  }

  /**
   * Show a history entry { position, move }. With animate = true the move is
   * animated from the balls shown now, which must be the position just
   * before it (the app only asks for that when stepping one ply forward).
   * markers = false hides the "placeable" markers (e.g. once the game is over).
   */
  show({ position, move }, animate = false, { markers = true } = {}) {
    const want = position.squares;
    // Finish ball animations that are still running, so every ball is exactly
    // where it belongs before we compare (camera moves keep running).
    this.anims = this.anims.filter((a) => {
      if (!a.ball) return true;
      a.step(1);
      return false;
    });
    let landAt = 0; // when the moving ball has landed (take-backs wait for it)

    if (animate && move) {
      // 1. The moving ball: a raise takes the ball already on `from`,
      //    a place makes a new ball above its square.
      const end = squareCentre(move.to);
      let mover = null;
      if (move.kind === 'raise' && this.balls.has(move.from)) {
        mover = this.balls.get(move.from);
        this.balls.delete(move.from);
        const start = squareCentre(move.from);
        const peak = Math.max(start.y, end.y) + 1.1;
        landAt = ARC_S;
        this.#animate(ARC_S, (k) => {
          // Ease out, along a quadratic Bézier curve through a point above both squares.
          const e = 1 - (1 - k) ** 3;
          mover.position.lerpVectors(start, end, e);
          mover.position.y = (1 - e) ** 2 * start.y + 2 * (1 - e) * e * peak + e * e * end.y;
        }, { ball: true });
      } else if (move.kind === 'place' && !this.balls.has(move.to)) {
        mover = this.#ballMesh(move.to, move.by);
        const start = end.clone().setY(end.y + 2.2);
        mover.position.copy(start);
        landAt = DROP_S;
        // Accelerating fall (k²), like gravity.
        this.#animate(DROP_S, (k) => mover.position.lerpVectors(start, end, k * k), { ball: true });
      }
      if (mover) {
        mover.userData.square = move.to;
        mover.visible = levelOf(move.to) <= this.maxLevel;
        if (want[move.to] === move.by) {
          this.balls.set(move.to, mover);
        } else {
          // The moved ball itself was taken back ("a13 x a13"): it lands, then shrinks.
          this.#shrink(mover, landAt);
        }
      }
    }

    // 2. Balls that are gone (take-backs) shrink away after the move has
    //    landed, one after the other; without animation they just vanish.
    let n = 0;
    for (const [sq, mesh] of [...this.balls]) {
      if (want[sq] === mesh.userData.colour) continue;
      this.balls.delete(sq);
      if (animate) this.#shrink(mesh, landAt + n++ * TAKE_GAP_S);
      else this.scene.remove(mesh);
    }

    // 3. Balls that are missing appear in place.
    for (const [sq, colour] of Object.entries(want)) {
      if (!this.balls.has(sq)) this.balls.set(sq, this.#ballMesh(sq, colour));
    }

    this.#drawMarks(move, position, markers);
  }

  /** Remove the "placeable" markers only (the game just ended), leaving animations alone. */
  hideMarkers() {
    for (const m of [...this.marks.children]) if (m.userData.marker) this.marks.remove(m);
  }

  /** A new ball mesh on a square, added to the scene. */
  #ballMesh(sq, colour) {
    const mesh = new THREE.Mesh(this.ballGeometry, this.materials[colour]);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.userData = { square: sq, colour };
    mesh.position.copy(squareCentre(sq));
    mesh.visible = levelOf(sq) <= this.maxLevel;
    this.scene.add(mesh);
    return mesh;
  }

  /** Shrink a ball to nothing after `delay` seconds, then remove it. */
  #shrink(mesh, delay) {
    this.#animate(TAKE_S, (k) => {
      mesh.scale.setScalar(Math.max(0.001, 1 - k));
      if (k >= 1) this.scene.remove(mesh);
    }, { ball: true, delay });
  }

  /** Queue an animation: step(k) is called with k going 0 → 1 over `dur` seconds. */
  #animate(dur, step, { ball = false, delay = 0 } = {}) {
    this.anims.push({ t: -delay / dur, dur, step, ball });
  }

  /** The marks of a move, plus faint markers on the squares a ball could go now. */
  #drawMarks(move, position, markers) {
    this.marks.clear();
    const squares = position.squares;
    const add = (obj, level) => {
      obj.userData.level = level;
      obj.visible = level <= this.maxLevel;
      this.marks.add(obj);
    };
    const ring = (sq, geometry, material) => {
      const t = new THREE.Mesh(geometry, material);
      t.rotation.x = Math.PI / 2; // lie flat round the ball's equator
      t.position.copy(squareCentre(sq));
      add(t, levelOf(sq));
    };
    const ghost = (sq) => {
      if (squares[sq]) return; // the square is occupied again: no ghost
      const g = new THREE.Mesh(this.ballGeometry, this.materials.ghost);
      g.position.copy(squareCentre(sq));
      add(g, levelOf(sq));
    };

    // Placeable markers (R08): empty squares whose supports are all occupied.
    for (const sq of markers ? placeableSquares(squares) : []) {
      const m = new THREE.Mesh(this.markerGeometry, this.materials.marker);
      m.position.copy(squareCentre(sq));
      if (levelOf(sq) === 0) m.position.y = SINK - R + 0.1; // low in the empty cup
      m.userData.marker = true;
      add(m, levelOf(sq));
    }

    if (!move) return;
    // Thin rings on the other balls of each completed shape (R07).
    for (const shape of move.shapes) {
      for (const sq of shape.squares) if (sq !== move.to && squares[sq]) ring(sq, this.shapeRingGeometry, this.materials.shape);
    }
    // The ice ring on the ball that moved (unless it was taken back).
    if (squares[move.to]) ring(move.to, this.ringGeometry, this.materials.ring);
    // Ghosts where balls left this ply.
    move.takeBack.forEach(ghost);
    if (move.kind === 'raise') {
      ghost(move.from);
      // A dashed arc from the raise's origin to its new square.
      const a = squareCentre(move.from);
      const b = squareCentre(move.to);
      const mid = a.clone().lerp(b, 0.5);
      mid.y = Math.max(a.y, b.y) + 1.1;
      const points = new THREE.QuadraticBezierCurve3(a, mid, b).getPoints(40);
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(points), this.materials.arc);
      line.computeLineDistances(); // dashes need the distance along the line
      add(line, 0);
    }
  }

  #pick(e) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.pointer.set(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const visible = [...this.balls.values()].filter((m) => m.visible);
    const hit = this.raycaster.intersectObjects(visible, false)[0];
    this.onHover(hit ? { square: hit.object.userData.square, colour: hit.object.userData.colour, x: e.clientX - rect.left, y: e.clientY - rect.top } : null);
  }

  #resize() {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';
    this.camera.aspect = w / h;
    // The camera's fov is vertical. The presets were framed for a wide stage
    // (aspect 1.4 or more) with fov 34°. On a narrower canvas we widen the
    // fov so the horizontal view stays as wide as that, and the whole plate
    // stays in frame: tan(vertical/2) = tan(17°) · 1.4 / aspect.
    const aspect = w / h;
    const wide = Math.tan((17 * Math.PI) / 180) * 1.4;
    this.camera.fov = aspect >= 1.4 ? 34 : (2 * Math.atan(wide / Math.max(aspect, 0.55)) * 180) / Math.PI;
    this.camera.updateProjectionMatrix();
  }

  #frame() {
    const dt = this.clock.getDelta();
    // Advance animations; drop the finished ones. t < 0 means "still waiting".
    this.anims = this.anims.filter((a) => {
      a.t = Math.min(1, a.t + dt / a.dur);
      if (a.t >= 0) a.step(a.t);
      return a.t < 1;
    });
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }
}
