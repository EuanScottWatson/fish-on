const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const Module=require('node:module');
const babel=require('@babel/core');
function loadModule(file,stub){const source=fs.readFileSync(file,'utf8');const compiled=babel.transformSync(source,{filename:file,configFile:false,babelrc:false,plugins:['@babel/plugin-transform-modules-commonjs']}).code;const m=new Module(file,module);m.filename=file;m.paths=module.paths;const fallback=m.require.bind(m);m.require=(name)=>name==='../../utils/blobUtils'?{blobToArrayBufferAsync:async x=>x.arrayBuffer()}:stub?.[name]||fallback(name);m._compile(compiled,file);return m.exports}
const root=path.resolve(__dirname,'..');
const {makeDraft,putDraft,removeDraft,photoMetadata}=loadModule(path.join(root,'drafts.js'));
const {appendPhoto}=loadModule(path.join(root,'photo-upload.js'));
const {convertFormDataAsync}=loadModule(path.join(root,'node_modules/expo/build/winter/fetch/convertFormData.js'));
(async()=>{
 assert.deepEqual(photoMetadata({GPSLatitude:51.5,GPSLatitudeRef:'N',GPSLongitude:.125,GPSLongitudeRef:'W',DateTimeOriginal:'2026:05:17 12:15:00'}),{lat:'51.5',lon:'-0.125',date:'17/05/2026'});
 assert.deepEqual(photoMetadata({GPSLatitude:91,GPSLongitude:1}),{});assert.deepEqual(photoMetadata(null),{});
 let id='a'.repeat(32),draft=makeDraft(id,{species:'Common carp',date:'17/05/2026'},null,false);assert.equal(draft.ready,false);let drafts=putDraft([],draft);drafts=putDraft(drafts,makeDraft(id,draft.fields,null,true));assert.equal(drafts.length,1);assert.equal(drafts[0].ready,true);assert.deepEqual(removeDraft(drafts,id),[]);
 class ExpoFile {constructor(uri){this.uri=uri;this.name='fish.jpg';this.type='image/jpeg'}async bytes(){return new Uint8Array(fs.readFileSync(this.uri))}}
 const pairs=[];let form={append:(name,value)=>pairs.push([name,value]),entries:()=>pairs};appendPhoto(form,{uri:path.join(__dirname,'fixtures/catch.jpg')},ExpoFile);for(const [k,v] of Object.entries({id,species:'Common carp',date:'2026-05-17',lat:'51.5',lon:'-0.125'}))form.append(k,v);
 assert.throws(()=>appendPhoto(form,{},ExpoFile),/choose it again/);
 await assert.rejects(()=>convertFormDataAsync({entries:()=>[['photo',{uri:'file:///old.jpg',name:'old.jpg',type:'image/jpeg'}]]}),/Unsupported FormDataPart/);
 let {body,boundary}=await convertFormDataAsync(form,'----fish-on-test');let url=process.env.FISH_TEST_URL||'http://127.0.0.1:7784';let response=await fetch(url+'/api/catches',{method:'POST',headers:{'Content-Type':'multipart/form-data; boundary='+boundary},body});let result=await response.json();assert.equal(response.status,200,JSON.stringify(result));assert.equal(result.id,id);let catches=await(await fetch(url+'/api/catches')).json();let saved=catches.find(c=>c.id===id);assert.equal(saved.species,'Common carp');assert.equal(saved.date,'2026-05-17');assert.equal(saved.lat,51.5);assert.ok(saved.photo);
 // A retry with the same id updates the same record, even after a lost response.
 response=await fetch(url+'/api/catches',{method:'POST',headers:{'Content-Type':'multipart/form-data; boundary='+boundary},body});assert.equal(response.status,200);catches=await(await fetch(url+'/api/catches')).json();assert.equal(catches.filter(c=>c.id===id).length,1);await fetch(url+'/api/catches/'+id,{method:'DELETE'});
 console.log('PASS Expo multipart converter, real server photo save, idempotent retry, offline drafts and metadata');
})().catch(error=>{console.error(error);process.exit(1)});
