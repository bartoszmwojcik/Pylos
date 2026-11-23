// board.js — the 3D view of one Pylos position, drawn with Three.js.
//
// BoardView owns a <canvas> inside a container element. The app calls
//   view.setPosition(position, lastMove, animate)
// whenever the game changes. The view rebuilds the balls from the position
// (at most 30, so rebuilding is cheap and keeps the code simple), then plays
// a short animation for the last move if asked to.

import * as THREE from './vendor/three.module.min.js';
import { OrbitControls } from './vendor/OrbitControls.js';
import { ALL_SQUARES, parseSquare, sideOf, placeableSquares } from './notation.js';

// ---------------------------------------------------------------------------
// Geometry: where does the ball on a square sit?
//
// All balls have diameter D (we use D = 1, so one unit = one ball).
//
// Height. Level a balls rest on the board, so their centres are at D/2.
// A ball on a higher level rests on four touching balls whose centres form a
// square of side D. Its centre is straight above the middle of that square.
// The horizontal distance from that middle to each lower centre is half the
// square's diagonal: D·√2 / 2 = D/√2. The upper ball touches each lower ball,
// so the distance between the centres is exactly D. By Pythagoras the
// vertical rise h satisfies h² + (D/√2)² = D², so h² = D²/2 and h = D/√2.
// Every level adds the same rise, so level L (a=0, b=1, c=2, d=3) has its
// centre at   y = D/2 + L · D/√2.
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
const RISE = D / Math.SQRT2;
const BALL_RADIUS = (D / 2) * 0.995; // a hair smaller, so touching balls don't flicker

/** The centre of a ball on the named square, as a THREE.Vector3. */
export function squareCentre(name) {
  const { level, row, col } = parseSquare(name);
  const n = sideOf(level);
  const mid = (n - 1) / 2;
  return new THREE.Vector3((col - 1 - mid) * D, D / 2 + level * RISE, (row - 1 - mid) * D);
}

// Animation timing (milliseconds). `?slowmo=5` in the URL makes every
// animation 5 times slower, to see (or screenshot) what happens.
const SLOWMO = Number(new URLSearchParams(window.location.search).get('slowmo')) || 1;
const MOVE_MS = 450 * SLOWMO; // drop of a placed ball, or flight of a raised one
const TAKE_MS = 450 * SLOWMO; // lift-and-fade of each take-back, after the move

const COLOURS = { white: 0xf2e8cf, black: 0x2b2420 }; // ivory and dark wood

/** A procedural wood texture painted on a canvas: warm base plus wavy grain. */
function woodTexture() {
  const size = 512;
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const g = canvas.getContext('2d');
  g.fillStyle = '#a0683a';
  g.fillRect(0, 0, size, size);
  // Deterministic pseudo-random numbers, so the board looks the same each load.
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 90; i++) {
    const y0 = rand() * size;
    const amp = 3 + rand() * 6;
    const freq = 0.005 + rand() * 0.01;
    const phase = rand() * Math.PI * 2;
    const dark = rand() < 0.5;
    g.strokeStyle = dark ? `rgba(70,38,16,${0.15 + rand() * 0.25})` : `rgba(210,150,95,${0.1 + rand() * 0.2})`;
    g.lineWidth = 0.6 + rand() * 2.2;
    g.beginPath();
    for (let x = 0; x <= size; x += 8) {
      const y = y0 + Math.sin(x * freq + phase) * amp;
      if (x === 0) g.moveTo(x, y);
      else g.lineTo(x, y);
    }
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

export class BoardView {
  constructor(container) {
    this.container = container;

    // Renderer, scene, camera.
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x1d2229);

    this.camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
    this.camera.position.set(4.2, 7.4, 9.0);

    // OrbitControls: left-drag rotates, wheel zooms, right-drag pans.
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 0.4, 0);
    this.controls.enableDamping = true;
    this.controls.minDistance = 4;
    this.controls.maxDistance = 25;
    this.controls.maxPolarAngle = Math.PI * 0.48; // stay above the table
    this.controls.update();

    this.#addLights();
    this.#addBoard();

    this.materials = {
      white: new THREE.MeshStandardMaterial({ color: COLOURS.white, roughness: 0.35, metalness: 0.0 }),
      black: new THREE.MeshStandardMaterial({ color: COLOURS.black, roughness: 0.3, metalness: 0.05 }),
      marker: new THREE.MeshBasicMaterial({ color: 0x9fe8b0, transparent: true, opacity: 0.28, depthWrite: false }),
      highlight: new THREE.MeshBasicMaterial({ color: 0xffb300 }),
    };
    this.ballGeometry = new THREE.SphereGeometry(BALL_RADIUS, 48, 32);
    this.markerGeometry = new THREE.SphereGeometry(0.14, 16, 12);
    this.reserveGeometry = new THREE.SphereGeometry(0.13, 20, 14);
    this.ringGeometry = new THREE.TorusGeometry(BALL_RADIUS * 1.04, 0.035, 10, 48);

    // Everything that depends on the position lives in this group and is
    // rebuilt by setPosition().
    this.dynamic = new THREE.Group();
    this.scene.add(this.dynamic);

    this.tweens = []; // running animations: { start, duration, update(k), done() }

    // Resize with the container (which resizes with the window).
    this.resizeObserver = new ResizeObserver(() => this.#resize());
    this.resizeObserver.observe(container);
    this.#resize();

    this.renderer.setAnimationLoop((now) => this.#frame(now));
  }

  #addLights() {
    this.scene.add(new THREE.HemisphereLight(0xfff4e0, 0x30343c, 1.1));
    const sun = new THREE.DirectionalLight(0xffffff, 2.2);
    sun.position.set(4, 9, 5);
    sun.castShadow = true;
    sun.shadow.mapSize.set(1024, 1024);
    Object.assign(sun.shadow.camera, { left: -5, right: 5, top: 5, bottom: -5, near: 1, far: 25 });
    sun.shadow.bias = -0.0005;
    this.scene.add(sun);
  }

  #addBoard() {
    // A square wooden base whose top face is the plane y = 0.
    const width = 4 * D + 0.7;
    const thickness = 0.3;
    const wood = new THREE.MeshStandardMaterial({ map: woodTexture(), roughness: 0.75 });
    const base = new THREE.Mesh(new THREE.BoxGeometry(width, thickness, width), wood);
    base.position.y = -thickness / 2;
    base.receiveShadow = true;
    this.scene.add(base);

    // Shallow-looking dimples for the 16 level-a squares.
    const dimple = new THREE.MeshStandardMaterial({ color: 0x5e3a1e, roughness: 0.9 });
    const dimpleGeo = new THREE.CircleGeometry(0.3, 32);
    for (const sq of ALL_SQUARES.filter((s) => s[0] === 'a')) {
      const m = new THREE.Mesh(dimpleGeo, dimple);
      const c = squareCentre(sq);
      m.rotation.x = -Math.PI / 2;
      m.position.set(c.x, 0.002, c.z);
      m.receiveShadow = true;
      this.scene.add(m);
    }

    // A dark table under everything, to catch shadows.
    const table = new THREE.Mesh(
      new THREE.CircleGeometry(30, 64),
      new THREE.MeshStandardMaterial({ color: 0x2a3038, roughness: 1 }),
    );
    table.rotation.x = -Math.PI / 2;
    table.position.y = -0.3;
    table.receiveShadow = true;
    this.scene.add(table);
  }

  #resize() {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  #frame(now) {
    // Advance animations; drop the finished ones.
    this.tweens = this.tweens.filter((t) => {
      if (t.start === null) t.start = now;
      const k = Math.min(1, Math.max(0, (now - t.start) / t.duration));
      if (now >= t.start) t.update(k);
      if (k >= 1) {
        if (t.done) t.done();
        return false;
      }
      return true;
    });
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  #ball(colour, centre) {
    const mesh = new THREE.Mesh(this.ballGeometry, this.materials[colour]);
    mesh.position.copy(centre);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.dynamic.add(mesh);
    return mesh;
  }

  /** Give a mesh its own material copy, so it can fade without fading others. */
  #ownMaterial(mesh) {
    mesh.material = mesh.material.clone();
    mesh.material.transparent = true;
    return mesh.material;
  }

  /**
   * Show a position.
   *   position — the protocol's Position: { squares, whiteReserve, blackReserve, toMove }
   *   lastMove — { action: { kind, from, to }, takeBack: [...], by } or null
   *   animate  — play the drop/flight and take-back animation for lastMove
   */
  setPosition(position, lastMove = null, animate = false) {
    // Forget any animation still running: the new position is the truth.
    this.tweens = [];
    this.dynamic.clear();

    const squares = position.squares;
    const balls = {};
    for (const [sq, colour] of Object.entries(squares)) balls[sq] = this.#ball(colour, squareCentre(sq));

    // Faint markers on empty squares whose supports are all occupied.
    for (const sq of placeableSquares(squares)) {
      const m = new THREE.Mesh(this.markerGeometry, this.materials.marker);
      m.position.copy(squareCentre(sq));
      if (sq[0] === 'a') m.position.y = 0.14; // sit in the dimple on level a
      this.dynamic.add(m);
    }

    this.#drawReserves(position);

    if (!lastMove) return;
    const { action, takeBack = [], by } = lastMove;
    const to = action.to;

    // Highlight: a gold ring around the ball that just moved (if it stayed).
    let mover = balls[to];
    if (mover) {
      const ring = new THREE.Mesh(this.ringGeometry, this.materials.highlight);
      ring.rotation.x = Math.PI / 2;
      mover.add(ring); // a child, so it follows the ball while it animates
    }
    if (!animate) return;

    // If the moved ball was itself taken back ("a13 x a13"), it is not in the
    // new position. Animate a temporary ball for it.
    if (!mover) mover = this.#ball(by, squareCentre(to));

    // Phase 1: the placed ball drops in / the raised ball flies over.
    const end = squareCentre(to);
    const begin = action.kind === 'raise' && action.from ? squareCentre(action.from) : end.clone().add(new THREE.Vector3(0, 3, 0));
    mover.position.copy(begin);
    const isRaise = action.kind === 'raise';
    this.tweens.push({
      start: null,
      duration: MOVE_MS,
      update: (k) => {
        if (isRaise) {
          // Straight line plus an arc, so the ball lifts over its neighbours.
          mover.position.lerpVectors(begin, end, k);
          mover.position.y += Math.sin(Math.PI * k) * 1.0;
        } else {
          // Accelerating fall (k²), like gravity.
          mover.position.lerpVectors(begin, end, k * k);
        }
      },
    });

    // Phase 2: each take-back lifts and fades out, after the move has landed.
    takeBack.forEach((sq, i) => {
      const ball = sq === to && !squares[to] ? mover : this.#ball(by, squareCentre(sq));
      const from = squareCentre(sq);
      let material = null;
      this.tweens.push({
        start: performance.now() + MOVE_MS + i * 120 * SLOWMO,
        duration: TAKE_MS,
        update: (k) => {
          material ??= this.#ownMaterial(ball);
          ball.position.set(from.x, from.y + 1.2 * k, from.z);
          material.opacity = 1 - k;
        },
        done: () => this.dynamic.remove(ball),
      });
    });
  }

  /** Small balls beside the board: White's reserve in front, Black's behind. */
  #drawReserves(position) {
    const rows = [
      ['white', position.whiteReserve, 3.05],
      ['black', position.blackReserve, -3.05],
    ];
    for (const [colour, count, z] of rows) {
      const spacing = 0.3;
      const x0 = -((15 - 1) * spacing) / 2; // a row for 15 balls, filled from the left
      for (let i = 0; i < count; i++) {
        const m = new THREE.Mesh(this.reserveGeometry, this.materials[colour]);
        m.position.set(x0 + i * spacing, -0.3 + 0.13, z);
        m.castShadow = true;
        this.dynamic.add(m);
      }
    }
  }
}
