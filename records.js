/**
 * Convert an explicitly labelled weight to grams, rejecting ambiguous values.
 */
export function weightInGrams(value) {
  if (typeof value !== 'string') return null;
  const text=value.trim().toLowerCase();
  let match=text.match(/^(\d+(?:\.\d+)?)\s*(kg|kilograms?|g|grams?|oz|ounces?)$/);
  if (match) {
    const n=Number(match[1]), unit=match[2];
    if (!Number.isFinite(n) || n<=0) return null;
    if (unit==='kg'||unit.startsWith('kilogram')) return n*1000;
    if (unit==='oz'||unit.startsWith('ounce')) return n*28.349523125;
    return n;
  }
  match=text.match(/^(\d+(?:\.\d+)?)\s*(?:lb|lbs|pounds?)(?:\s*(\d+(?:\.\d+)?)\s*(?:oz|ounces?))?$/);
  if (!match) return null;
  const pounds=Number(match[1]), ounces=Number(match[2]||0);
  if (!Number.isFinite(pounds)||!Number.isFinite(ounces)||ounces>=16||pounds*16+ounces<=0) return null;
  return pounds*453.59237+ounces*28.349523125;
}

/**
 * Find the heaviest recognisable weight for each saved species name.
 */
export function personalBests(catches) {
  const best=new Map();
  for (const item of catches) {
    const name=typeof item.species==='string'?item.species.trim():'';
    const grams=weightInGrams(item.weight);
    if (!name||grams===null) continue;
    const key=name.toLocaleLowerCase(), prior=best.get(key);
    if (!prior||grams>prior.grams) best.set(key,{catchItem:item,grams});
  }
  return [...best.values()].sort((a,b)=>a.catchItem.species.localeCompare(b.catchItem.species));
}
