// Copy first, then publish the draft. The app cache can be cleared by iOS.
export async function copyDraftPhoto(asset, id, {File, Directory, Paths, randomUUID}) {
  if (!asset?.uri) return null;
  if (asset.uri.includes('/fish-on-drafts/')) return asset;
  const dir = new Directory(Paths.document, 'fish-on-drafts');
  dir.create({idempotent: true, intermediates: true});
  const destination = new File(dir, id + '-' + randomUUID() + '.jpg');
  const source = new File(asset.uri);
  await source.copy(destination);
  return {...asset, uri: destination.uri, exif: null};
}
