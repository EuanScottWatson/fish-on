const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const babel = require('@babel/core');
const file = path.join(__dirname, '..', 'box-geometry.js');
const code = babel.transformSync(fs.readFileSync(file, 'utf8'), {filename:file, configFile:false, babelrc:false, plugins:['@babel/plugin-transform-modules-commonjs']}).code;
const mod = new Module(file, module);mod.filename=file;mod.paths=module.paths;mod._compile(code, file);
const {boxFromDrag} = mod.exports;
function closeTo(actual, expected) {
  for (const key of Object.keys(expected)) assert.ok(Math.abs(actual[key]-expected[key]) < 1e-10, `${key}: ${actual[key]}`);
}
closeTo(boxFromDrag(10, 20, 50, 40, 100, 100), {x:0.1,y:0.2,w:0.5,h:0.4});
closeTo(boxFromDrag(80, 70, -60, -50, 100, 100), {x:0.2,y:0.2,w:0.6,h:0.5});
closeTo(boxFromDrag(50, 50, 100, -100, 100, 100), {x:0.5,y:0,w:0.5,h:0.5});
assert.equal(boxFromDrag(0, 0, 1, 1, 0, 100), null);
console.log('PASS fish selection geometry: reverse drags, clipping and invalid dimensions');
