(function(root){
 'use strict';
 const xml=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
 const col=i=>{let s='';for(i++;i;i=Math.floor((i-1)/26))s=String.fromCharCode(65+(i-1)%26)+s;return s;};
 const ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
 async function write(project){
  const zip=new JSZip(),tables=Object.entries(root.EventSchema),sheets=[{name:'字段说明',rows:[['表名','字段','数据类型','必填','填写提示'],['项目名称',project.name],['配置版本',1],...tables.flatMap(([key,t])=>t.fields.map(f=>[t.label,f.label,f.type,f.required?'是':'否',f.tip||(f.enum?'可选：'+f.enum.join('、'):f.ref?'引用：'+f.ref:'')]))]},...tables.map(([key,t])=>({name:t.label,rows:[t.fields.map(f=>f.label),...project.tables[key].map(r=>t.fields.map(f=>r[f.key]))]}))];
  if(root.EventStory)sheets.splice(1,0,root.EventStory.sheet(project));
  const contentTypes=sheets.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('');
  zip.file('[Content_Types].xml',`<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${contentTypes}</Types>`);
  zip.file('_rels/.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  zip.file('xl/workbook.xml',`<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="${ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map((s,i)=>`<sheet name="${xml(s.name)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')}</sheets></workbook>`);
  zip.file('xl/_rels/workbook.xml.rels',`<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((s,i)=>`<Relationship Id="rId${i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join('')}<Relationship Id="rId${sheets.length+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`);
  zip.file('xl/styles.xml',`<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="${ns}"><fonts count="2"><font><sz val="11"/><name val="Microsoft YaHei"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Microsoft YaHei"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF263F50"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`);
  sheets.forEach((s,i)=>{
   const rows=s.rows.map((row,ri)=>`<row r="${ri+1}" ht="${ri?42:30}" customHeight="1">${row.map((v,ci)=>{const attr=`r="${col(ci)}${ri+1}" s="${ri?0:1}"`;if(typeof v==='boolean')return `<c ${attr} t="b"><v>${v?1:0}</v></c>`;if(typeof v==='number'&&Number.isFinite(v))return `<c ${attr}><v>${v}</v></c>`;return `<c ${attr} t="inlineStr"><is><t xml:space="preserve">${xml(v)}</t></is></c>`;}).join('')}</row>`).join('');
   zip.file(`xl/worksheets/sheet${i+1}.xml`,`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="${ns}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${s.rows[0].map((h,ci)=>`<col min="${ci+1}" max="${ci+1}" width="${['正文','概览','说明','备注','填写提示'].includes(h)?65:25}" customWidth="1"/>`).join('')}</cols><sheetData>${rows}</sheetData><autoFilter ref="A1:${col(s.rows[0].length-1)}${s.rows.length}"/></worksheet>`);
  });return zip.generateAsync({type:'blob',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',compression:'DEFLATE'});
 }
 async function read(file){
  if(file.size>15*1024*1024)throw Error('文件超过15MB，请拆分配置。');const zip=await JSZip.loadAsync(file);if(Object.keys(zip.files).length>500)throw Error('工作簿内容过多。');
  const parse=async path=>{const f=zip.file(path);if(!f)throw Error(`缺少Excel文件：${path}`);const text=await f.async('string');if(text.length>20*1024*1024)throw Error('工作表过大');const doc=new DOMParser().parseFromString(text,'application/xml');if(doc.getElementsByTagName('parsererror').length)throw Error('Excel XML格式错误');return doc;};
  const get=(node,name)=>[...node.getElementsByTagNameNS('*',name)];
  const workbook=await parse('xl/workbook.xml'),rels=await parse('xl/_rels/workbook.xml.rels');
  const targets=Object.fromEntries(get(rels,'Relationship').map(r=>[r.getAttribute('Id'),r.getAttribute('Target')]));
  const strings=zip.file('xl/sharedStrings.xml')?get(await parse('xl/sharedStrings.xml'),'si').map(si=>get(si,'t').map(t=>t.textContent).join('')):[];
  const sheets=[];
  for(const s of get(workbook,'sheet')){
   const id=s.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships','id'),target=targets[id];if(!target)throw Error('工作表关联缺失');const path=target.startsWith('/')?target.slice(1):'xl/'+target.replace(/^\.\//,'');if(path.includes('..'))throw Error('不支持的工作表路径');const doc=await parse(path),rows=[];
   for(const row of get(doc,'row')){const ri=Number(row.getAttribute('r'))-1;if(ri<0||ri>100000)throw Error('工作表行号异常');rows[ri]=[];for(const c of get(row,'c')){const addr=c.getAttribute('r')||'',letters=addr.match(/^[A-Z]+/);if(!letters)continue;let ci=0;for(const l of letters[0])ci=ci*26+l.charCodeAt(0)-64;ci--;if(ci>500)continue;const type=c.getAttribute('t'),v=get(c,'v')[0]?.textContent||'';let value;
     if(type==='s')value=strings[Number(v)]??'';else if(type==='inlineStr')value=get(c,'t').map(t=>t.textContent).join('');else if(type==='b')value=v==='1';else if(type==='str'||type==='e')value=v;else value=v===''?'':Number(v);rows[ri][ci]=value;}}
   sheets.push({name:s.getAttribute('name'),rows:Array.from({length:rows.length},(_,i)=>rows[i]||[])});
  }return sheets;
 }
 root.EventXlsx={write,read};
})(globalThis);
