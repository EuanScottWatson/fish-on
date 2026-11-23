/**
 * Read a recorded ISO date only when it represents a real calendar day.
 */
function recordedDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value ? date : null;
}

/**
 * Count saved labels case-insensitively while retaining their original spelling.
 */
function countLabels(items, field) {
  const counts = new Map();
  for (const item of items) {
    const label = typeof item[field] === 'string' ? item[field].trim() : '';
    if (!label) continue;
    const key = label.toLocaleLowerCase();
    const entry = counts.get(key) || {label, count: 0};
    entry.count++;
    counts.set(key, entry);
  }
  return [...counts.values()].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

/**
 * Summarise only explicitly recorded catches and trips without inventing history.
 */
export function fishingSummary(catches, trips, year) {
  const species = countLabels(catches, 'species');
  const places = countLabels(catches, 'place');
  const years = new Map();
  const months = Array(12).fill(0);
  let caughtThisYear = 0, undatedCatches = 0;
  for (const item of catches) {
    const date = recordedDate(item.date);
    if (!date) { undatedCatches++; continue; }
    const recordedYear = date.getUTCFullYear();
    years.set(recordedYear, (years.get(recordedYear) || 0) + 1);
    months[date.getUTCMonth()]++;
    if (recordedYear === year) caughtThisYear++;
  }
  const knownTrips = Array.isArray(trips) ? trips : null;
  return {
    catches: catches.length,
    species: species.length,
    caughtThisYear,
    trips: knownTrips ? knownTrips.length : null,
    tripsWithLinkedCatches: knownTrips ? knownTrips.filter(trip => Array.isArray(trip.catch_ids) && trip.catch_ids.length > 0).length : null,
    years: [...years].sort((a, b) => b[0] - a[0]).map(([label, count]) => ({label: String(label), count})),
    months,
    topSpecies: species,
    topPlaces: places,
    undatedCatches,
  };
}
