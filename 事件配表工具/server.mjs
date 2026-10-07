import {createServer} from 'node:http';
import {readFile,stat,mkdir,writeFile} from 'node:fs/promises';
import {resolve,sep,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import './flow.js';
const root=fileURLToPath(new URL('.',import.meta.url)),port=Number(process.env.PORT||4186);
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png'};
createServer(async(req,res)=>{
 const pathname=new URL(req.url,'http://local').pathname;
 if(pathname==='/api/health'&&req.method==='GET'){
  res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify({tool:'event-flow-workbench',api_version:1,directory:root}));return;
 }
 if(pathname==='/api/export-event'){
  const send=(code,value)=>{res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value));};
  if(req.method!=='POST'||req.headers.origin!==`http://127.0.0.1:${port}`){send(403,{error:'仅允许本工具同源页面主动导出'});req.resume();return;}
  try{
   const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>2*1024*1024){send(413,{error:'事件文件超过2MB'});return;}chunks.push(chunk);}
   const data=JSON.parse(Buffer.concat(chunks).toString('utf8')),checked=globalThis.EventFlow.validate(data);
   if(!checked.ok||checked.warnings.length){send(400,{error:[...checked.errors,...checked.warnings].map(i=>i.message).join('；')});return;}
   globalThis.EventFlow.clean({[data.id]:data});
   const folder=resolve(root,'output','events'),name=data.id.replace(/[^A-Za-z0-9_.-]/g,'_').slice(0,80)+'_'+Date.now()+'_'+randomUUID().slice(0,8)+'.event.json',target=resolve(folder,name);
   if(!target.startsWith(folder+sep))throw Error('输出路径越界');
   await mkdir(folder,{recursive:true});await writeFile(target,JSON.stringify(data,null,2)+'\n',{flag:'wx'});
   send(201,{path:target,url:'/output/events/'+encodeURIComponent(name)});
  }catch(error){send(400,{error:error.message});}return;
 }
 try{
  if(!['GET','HEAD'].includes(req.method))throw Error('只读访问');
  let path=decodeURIComponent(pathname);const file=resolve(root,'.'+(path==='/'?'/index.html':path));
  if(!file.startsWith(root.endsWith(sep)?root:root+sep))throw Error('越界');const info=await stat(file);if(!info.isFile())throw Error('不是文件');
  res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(req.method==='HEAD'?'':await readFile(file));
 }catch{res.writeHead(404);res.end('Not found');}
}).listen(port,'127.0.0.1',()=>console.log(`事件配表工具 http://127.0.0.1:${port}`));
