// Checks the browser's copy of the rules (web/rules.js) against the reference
// engine: the perft counts it produces must equal the golden values in
// golden/perft.json, which the reference engine computed (D11, ADR 0012).
//
// web/rules.js is a JavaScript port of reference/Pylos/Reference/Rules.hs
// (ADR 0027). The cabal tests cannot see it, so without this check the two
// could drift apart and the board would accept or refuse the wrong clicks.
//
// Run from the repository root with Node 22 or newer:
//   node test/web-rules-perft.mjs
// It prints one line per golden position and exits with status 1 on any
// mismatch, so CI fails.

import fs from 'node:fs';
import { legalMoves, moveText } from '../web/rules.js';
import { applyMove, startPosition } from '../web/notation.js';

// The depths checked. Depth 3 of every golden position takes a few seconds;
// deeper counts are covered by the Haskell engines.
const DEPTHS = [1, 2, 3];

/** Number of move sequences of length `d` from position `p`. */
function perft(p, d) {
  if (d === 0) return 1;
  let n = 0;
  for (const m of legalMoves(p)) n += perft(applyMove(p, moveText(m)).position, d - 1);
  return n;
}

const golden = JSON.parse(fs.readFileSync(new URL('../golden/perft.json', import.meta.url), 'utf8'));
let failed = false;
for (const g of golden) {
  const p = g.moves.reduce((q, t) => applyMove(q, t).position, startPosition());
  const results = DEPTHS.map((d) => {
    const got = perft(p, d);
    const want = g.perft[d - 1];
    if (got !== want) failed = true;
    return got === want ? `d${d} ok (${got})` : `d${d} MISMATCH: got ${got}, golden ${want}`;
  });
  console.log(`${g.name}: ${results.join(', ')}`);
}

if (failed) {
  console.error('web/rules.js disagrees with golden/perft.json');
  process.exit(1);
}
console.log('web/rules.js matches golden/perft.json');
