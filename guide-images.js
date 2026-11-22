const LICENCES=new Set(['cc0','cc-by','cc-by-sa','cc-by-nc','cc-by-nc-sa','cc-by-nd','cc-by-nc-nd']);
export function licensedGuidePhoto(photo) {
  return Boolean(photo?.medium_url && photo?.attribution && LICENCES.has(String(photo.license_code||'').toLowerCase()));
}
export function matchingTaxonPhoto(results, scientificName) {
  const taxon=(results||[]).find(item=>typeof item?.name==='string' && item.name.toLowerCase()===scientificName.toLowerCase());
  return taxon && licensedGuidePhoto(taxon.default_photo) ? {name:taxon.name,id:taxon.id,default_photo:taxon.default_photo} : null;
}
