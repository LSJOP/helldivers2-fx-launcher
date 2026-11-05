// Local protocol fixture: no Steam, SSH, authentication, or external network.
const http=require('http'),crypto=require('crypto'),fs=require('fs'),vm=require('vm');
const data={strLaunchOptions:'%command%',strCompatToolName:'proton_11-arm64',strCompatToolDisplayName:'Proton ARM64'};
const callbacks=new Set();
const context=vm.createContext({setTimeout,JSON,Array,Error,SteamUIStore:{RunningApps:[]},appDetailsStore:{RegisterForAppData(id,cb){if(id!==553850)throw Error('appid');callbacks.add(cb);cb({...data});return {unregister(){callbacks.delete(cb);}};}},SteamClient:{Apps:{SetAppLaunchOptions(id,v){if(id!==553850)throw Error('appid');data.strLaunchOptions=v;for(const cb of callbacks)cb({...data});},SpecifyCompatTool(id,v){if(id!==553850)throw Error('appid');data.strCompatToolName=v;data.strCompatToolDisplayName=v;for(const cb of callbacks)cb({...data});}}}});
const server=http.createServer((req,res)=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify([{title:'SharedJSContext',webSocketDebuggerUrl:`ws://127.0.0.1:${server.address().port}/devtools/page/fixture`}]))});
function send(socket,message){const body=Buffer.from(JSON.stringify(message));let header=Buffer.alloc(body.length<126?2:4);header[0]=0x81;if(body.length<126)header[1]=body.length;else{header[1]=126;header.writeUInt16BE(body.length,2);}socket.write(Buffer.concat([header,body]));}
server.on('upgrade',(req,socket)=>{
 const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
 socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
 let buffer=Buffer.alloc(0);
 socket.on('data',bytes=>{buffer=Buffer.concat([buffer,bytes]);while(buffer.length>=2){const opcode=buffer[0]&15;let length=buffer[1]&127,offset=2;if(length===126){if(buffer.length<4)return;length=buffer.readUInt16BE(2);offset=4;}if(length===127){socket.destroy();return;}const masked=!!(buffer[1]&128),mask=masked?buffer.subarray(offset,offset+4):null;if(masked)offset+=4;if(buffer.length<offset+length)return;const payload=Buffer.from(buffer.subarray(offset,offset+length));buffer=buffer.subarray(offset+length);if(masked)for(let i=0;i<payload.length;i++)payload[i]^=mask[i%4];if(opcode===8){socket.end();return;}if(opcode!==1)continue;let request;try{request=JSON.parse(payload.toString());}catch{socket.destroy();return;}Promise.resolve().then(()=>vm.runInContext(request.params.expression,context)).then(value=>send(socket,{id:request.id,result:{result:{type:'string',value}}})).catch(error=>send(socket,{id:request.id,result:{exceptionDetails:{exception:{description:String(error)}}}}));}});
 socket.on('error',()=>{});
});
server.listen(0,'127.0.0.1',()=>fs.writeFileSync(process.argv[2],String(server.address().port)));
