export const DRAFT_KEY = 'fish-on-drafts-v1';

// A stable server id makes retries safe if the connection drops after a save.
export function makeDraft(id, fields, photo, ready) {
  return {id, fields: {...fields, id}, photo: photo || null, ready: Boolean(ready), error: ''};
}
export function putDraft(drafts, draft) {
  return [...drafts.filter(item => item.id !== draft.id), draft];
}
export function removeDraft(drafts, id) {
  return drafts.filter(item => item.id !== id);
}
export function photoMetadata(exif) {
  if (!exif) return {};
  const result = {};
  let lat = Number(exif.GPSLatitude), lon = Number(exif.GPSLongitude);
  if (Number.isFinite(lat) && Number.isFinite(lon) && exif.GPSLatitude != null && exif.GPSLongitude != null) {
    if (String(exif.GPSLatitudeRef || '').toUpperCase() === 'S') lat = -Math.abs(lat);
    if (String(exif.GPSLongitudeRef || '').toUpperCase() === 'W') lon = -Math.abs(lon);
    if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) { result.lat = String(lat); result.lon = String(lon); }
  }
  const value = exif.DateTimeOriginal || exif.DateTimeDigitized || exif.DateTime;
  const match = typeof value === 'string' && /^(\d{4})[:\/-](\d{2})[:\/-](\d{2})/.exec(value);
  if (match) result.date = `${match[3]}/${match[2]}/${match[1]}`;
  return result;
}
