const assert=require('node:assert/strict');const fs=require('node:fs/promises');const path=require('node:path');
require('../schema.js');require('../seed.js');require('../model.js');globalThis.JSZip=require('../vendor/jszip.min.js');require('../xlsx.js');
(async()=>{
 const p=EventModel.normalize(EventSeed);p.tables.events[0].summary='=SUM(1,2) <怪物> & 测试';
 const blob=await EventXlsx.write(p),buffer=Buffer.from(await blob.arrayBuffer());
 const zip=await JSZip.loadAsync(buffer);assert(zip.file('xl/workbook.xml'));assert(zip.file('xl/worksheets/sheet8.xml'));
 const goals=await zip.file('xl/worksheets/sheet3.xml').async('string');assert(goals.includes('<v>3</v>'));assert(goals.includes('<v>7</v>'));
 const conditions=await zip.file('xl/worksheets/sheet6.xml').async('string');assert(conditions.includes('t="b"'));
 const events=await zip.file('xl/worksheets/sheet2.xml').async('string');assert(!events.includes('<f>'));assert(events.includes('=SUM(1,2) &lt;怪物&gt; &amp; 测试'));
 const out=path.join(__dirname,'../output/tests');await fs.mkdir(out,{recursive:true});await fs.writeFile(path.join(out,'roundtrip.xlsx'),buffer);
 console.log('PASS: offline XLSX package, 8 sheets, typed numbers/booleans, escaped XML, formula-like text not executable.');
})().catch(e=>{console.error(e.message);process.exitCode=1});
