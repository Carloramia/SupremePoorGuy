export const HEX_DIRECTIONS = Object.freeze([
  [1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1],
]);

export const keyOf = ([q, r]) => `${q},${r}`;
export const fromKey = (key) => key.split(",").map(Number);

export function createHexDisk(radius = 4) {
  const cells = [];
  for (let q = -radius; q <= radius; q += 1) {
    const rMin = Math.max(-radius, -q - radius);
    const rMax = Math.min(radius, -q + radius);
    for (let r = rMin; r <= rMax; r += 1) cells.push([q, r]);
  }
  return cells;
}

export function distance([aq, ar], [bq, br]) {
  const dq = aq - bq;
  const dr = ar - br;
  return Math.max(Math.abs(dq), Math.abs(dr), Math.abs(dq + dr));
}

function axialRound(q, r) {
  const x = q; const z = r; const y = -x - z;
  let rx = Math.round(x); let ry = Math.round(y); let rz = Math.round(z);
  const dx = Math.abs(rx - x); const dy = Math.abs(ry - y); const dz = Math.abs(rz - z);
  if (dx > dy && dx > dz) rx = -ry - rz;
  else if (dy > dz) ry = -rx - rz;
  else rz = -rx - ry;
  return [rx, rz];
}

/** Every axial cell crossed by the straight segment, including both ends. */
export function hexLine(a, b) {
  const steps = distance(a, b);
  if (steps === 0) return [[...a]];
  return Array.from({ length: steps + 1 }, (_, index) => {
    const t = index / steps;
    return axialRound(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t);
  });
}

export function axialToPoint([q, r], size = 36, origin = [380, 325]) {
  return [origin[0] + size * Math.sqrt(3) * (q + r / 2), origin[1] + size * 1.5 * r];
}

export function polygonPoints(cell, size = 34, origin) {
  const [cx, cy] = axialToPoint(cell, size + 2, origin);
  return Array.from({ length: 6 }, (_, index) => {
    const angle = ((60 * index - 30) * Math.PI) / 180;
    return [cx + size * Math.cos(angle), cy + size * Math.sin(angle)];
  });
}

export function rotate([q, r]) {
  return [-r, q + r];
}

export function reflect([q, r]) {
  return [-q - r, r];
}

export function transformPath(path, rotations = 0, mirrored = false) {
  return path.map((cell) => {
    let next = mirrored ? reflect(cell) : [...cell];
    for (let index = 0; index < rotations; index += 1) next = rotate(next);
    return next;
  });
}

export function sameOrderedShape(path, pattern) {
  if (path.length !== pattern.length || path.length === 0) return false;
  const offset = [path[0][0] - pattern[0][0], path[0][1] - pattern[0][1]];
  return path.every((cell, index) => (
    cell[0] === pattern[index][0] + offset[0] && cell[1] === pattern[index][1] + offset[1]
  ));
}
