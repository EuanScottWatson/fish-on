// Observations and survey sites have different schemas; species can be an object.
export function detailTitle(selection) {
  const data = selection?.data || {};
  const nonempty = value => typeof value === 'string' && value.trim() ? value : '';
  if (selection?.kind === 'observation') return nonempty(data.taxon?.preferred_common_name) || nonempty(data.taxon?.name) || 'Observation';
  if (selection?.kind === 'survey') return nonempty(data.name) || nonempty(data.water) || 'Survey site';
  return nonempty(data.common) || nonempty(data.species) || nonempty(data.name) || 'Details';
}
export function safeSpeciesEntries(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
  return Object.entries(value).filter(([name, year]) => typeof name === 'string' && (typeof year === 'string' || typeof year === 'number'));
}
