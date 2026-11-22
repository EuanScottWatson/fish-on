// Expo's fetch expects a File/Blob, not React Native's legacy { uri, name, type } object.
export function appendPhoto(form, asset, File) {
  if (!asset?.uri) throw new Error('The selected photo is unavailable. Please choose it again.');
  form.append('photo', new File(asset.uri));
}
