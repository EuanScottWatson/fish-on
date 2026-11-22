/**
 * Summarise only explicitly recorded catches and trips without inventing history.
 */
export function fishingSummary(catches, trips, year) {
  const species = new Set();
  let caughtThisYear = 0;
  for (const item of catches) {
    const name = typeof item.species === 'string' ? item.species.trim().toLocaleLowerCase() : '';
    if (name) species.add(name);
    if (typeof item.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(item.date)) {
      const parsed = new Date(item.date + 'T00:00:00Z');
      if (!Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0,10) === item.date && parsed.getUTCFullYear() === year) caughtThisYear++;
    }
  }
  const knownTrips = Array.isArray(trips) ? trips : null;
  return {
    catches:catches.length,
    species:species.size,
    caughtThisYear,
    trips:knownTrips ? knownTrips.length : null,
    tripsWithLinkedCatches:knownTrips ? knownTrips.filter(trip=>Array.isArray(trip.catch_ids) && trip.catch_ids.length>0).length : null,
  };
}
