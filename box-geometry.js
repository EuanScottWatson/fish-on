/**
 * Convert the drag start and displacement into a bounded image-relative box.
 */
export function boxFromDrag(startX, startY, dx, dy, width, height) {
  if (!(width > 0 && height > 0)) return null;
  const clamp = value => Math.max(0, Math.min(1, value));
  const x0 = clamp(startX / width), y0 = clamp(startY / height);
  const x1 = clamp((startX + dx) / width), y1 = clamp((startY + dy) / height);
  return {x: Math.min(x0, x1), y: Math.min(y0, y1), w: Math.abs(x1 - x0), h: Math.abs(y1 - y0)};
}
