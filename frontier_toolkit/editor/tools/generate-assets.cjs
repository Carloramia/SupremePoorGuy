/* Code-native SVG assets; no generated raster dependency or network request. */
const fs = require('node:fs');
const path = require('node:path');
const target = path.resolve(__dirname, '../assets');
const common = '<ellipse cx="64" cy="101" rx="46" ry="14" fill="#152b1b" opacity=".25"/>';
const shapes = {
  rock: '<path d="M20 80 32 43 68 28 105 48 114 82 86 103 41 99Z" fill="#737d71" stroke="#485749" stroke-width="3"/><path d="m32 43 32 21 41-16-19 36-45 15 23-35Z" fill="#9a9f8a"/><path d="m64 64 22 20 28-2-9-34Z" fill="#657260"/>',
  tree: '<path d="m58 76-4 32 20 2-5-40" fill="#8e7350" stroke="#4c4c31" stroke-width="3"/><path d="M20 57 31 38 45 35 44 23 67 16 85 30 91 45 109 57 105 74 84 83 62 79 41 84 22 73Z" fill="#66885c" stroke="#384d32" stroke-width="3"/><path d="m33 40 17 17 31-4 8-15-20-15Z" fill="#87a46f"/><path d="m49 67 22 7 20-10" fill="none" stroke="#4c6d44" stroke-width="4"/>',
  barricade: '<path d="M23 109 40 29M92 108 82 29" stroke="#56432d" stroke-width="11"/><path d="m14 47 97 38m-94 2 98-36" stroke="#bb9761" stroke-width="15"/><path d="m17 44 97 38m-94 2 92-35" stroke="#d7b77f" stroke-width="3"/><circle cx="40" cy="60" r="4" fill="#51482d"/><circle cx="86" cy="75" r="4" fill="#51482d"/>',
  rubble: '<path d="m16 91 41-13m-20 30 36-50m-2 29 38 10M61 102l26-14" stroke="#9e8053" stroke-width="12"/><path d="m44 72 14-2-3 17m31-16-3-19 13 4" fill="#d5ad70"/><path d="m17 105 11-13 15 13-11 10m54-9 10-9 15 12-10 8" fill="#747b66"/>',
  house: '<path d="M29 57h70v48H29Z" fill="#c6b68a" stroke="#5c5940" stroke-width="3"/><path d="m16 60 47-42 49 42Z" fill="#7c5440" stroke="#463d2e" stroke-width="3"/><path d="m25 52 38-33 37 33Z" fill="#a27851"/><path d="M54 75h21v30H54Z" fill="#4c4e38"/><path d="M35 70h13v15H35Zm45 0h13v15H80Z" fill="#e3cc86"/>',
  town: '<path d="M18 67h29v39H18Zm66-13h30v52H84Z" fill="#a4a886"/><path d="m12 67 20-24 22 24m23-13 22-25 23 25" fill="#7d684b"/><path d="M43 46h44v62H43Z" fill="#c8ba8d" stroke="#5d6146" stroke-width="3"/><path d="m34 46 31-32 31 32Z" fill="#9a7350"/><path d="M58 79h15v29H58Z" fill="#50583b"/><path d="M55 57h19v14H55Z" fill="#d7cd97"/>',
  camp: '<path d="m19 98 39-70 49 70Z" fill="#baa56c" stroke="#5e6040" stroke-width="3"/><path d="m58 28 15 70H43Z" fill="#6b7450"/><path d="M92 28v64" stroke="#635d3d" stroke-width="5"/><path d="m95 26 27 7-10 18-17-2Z" fill="#bb7754"/><path d="m25 106 25-4m40 1 24 2" stroke="#7e7a55" stroke-width="5"/>',
  grass: '<path d="m17 105 4-37 18 28-1-50 20 41 9-64 10 59 25-36-8 47 20-12-9 29Z" fill="#7b9a56"/><path d="m42 100 6-25 14 25 12-45 8 43" fill="#adc07a"/>',
  thorns: '<path d="m17 98 18-51 18 38 15-65 13 54 20-29 9 50" fill="#728151" stroke="#4c5d36" stroke-width="5"/><path d="m27 78-17-8m33-2 15-9m12-5-15-8m31 29 17-6" stroke="#b0ac70" stroke-width="5"/>',
  mud: '<path d="M12 74Q21 49 42 57T84 50Q115 51 115 77T71 106Q23 113 12 74" fill="#70634a" stroke="#504e38" stroke-width="4"/><path d="M28 75q19-11 39 1m-17 14 39-4m-7-21 15 4" fill="none" stroke="#8b7958" stroke-width="4"/>',
  web: '<g fill="none" stroke="#c6cfac" stroke-width="2"><path d="M64 15v94M17 62h94M30 28l67 67m1-68L30 97"/><path d="m64 32 22 11 9 20-9 21-22 9-21-9-10-21 10-20Zm0 14 11 7 6 10-6 12-11 6-11-6-6-12 6-10Zm0-30 35 13 14 34-14 35-35 14-35-14-14-35 14-34Z"/></g>',
  pit: '<ellipse cx="64" cy="76" rx="51" ry="28" fill="#8b8964"/><ellipse cx="64" cy="75" rx="44" ry="23" fill="#303b29"/><ellipse cx="66" cy="78" rx="29" ry="14" fill="#17251c"/><path d="m19 63 20 7m57-10-11 10M34 93l10-10" stroke="#b3a37b" stroke-width="5"/>',
  monster: '<path d="m39 51-9-24 25 12 21-2 24-15-8 31 12 25-15 24-45 3-21-23Z" fill="#c39667" stroke="#5c6745" stroke-width="3"/><path d="m43 63 12 4m20 0 13-5" stroke="#293e2a" stroke-width="5"/><path d="m52 84 23-1-8 8Z" fill="#72563e"/>',
  altar: '<path d="M28 77h72l9 29H17Z" fill="#8e947a"/><path d="m36 62 28-15 29 16-29 16Z" fill="#bdba91"/><path d="M36 62v23l28 15 29-15V63L64 79Z" fill="#737e64"/><path d="m64 16 13 20-13 20-13-20Z" fill="#d9b56e" stroke="#f3dc97" stroke-width="3"/>',
  road: '<path d="M45 113Q24 75 67 66T88 10" fill="none" stroke="#6d6040" stroke-width="33"/><path d="M45 113Q24 75 67 66T88 10" fill="none" stroke="#af9870" stroke-width="26"/><path d="m49 97 7-3m1-19 6 1m14-25 7 2M86 26l8 2" stroke="#d4bd92" stroke-width="4"/>',
  cloth: '<path d="m13 22 95-6 8 88-96 7Z" fill="#8c8564" stroke="#a89b76" stroke-width="4"/><path d="m22 29 78-5 7 73-78 6Z" fill="none" stroke="#bcaa7e" stroke-width="2" stroke-dasharray="4 4"/>'
};
fs.mkdirSync(target, { recursive: true });
for (const [name, shape] of Object.entries(shapes)) fs.writeFileSync(path.join(target, name + '.svg'), `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">${common}${shape}</svg>\n`);
console.log('Created', Object.keys(shapes).length, 'SVG assets');
