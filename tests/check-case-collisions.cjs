const {execFileSync} = require('node:child_process');
const files = execFileSync('git',['ls-files','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const names = new Map();
for (const file of files) {
  const key = file.toLowerCase();
  if (names.has(key)) {
    console.error(`Files collide on case-insensitive filesystems: ${names.get(key)} and ${file}`);
    process.exitCode = 1;
  } else names.set(key,file);
}
if (!process.exitCode) console.log('PASS no case-insensitive filename collisions');
