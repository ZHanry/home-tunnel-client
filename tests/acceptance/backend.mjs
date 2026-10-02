// HOMEDESK: 临时 HTTP/HTTPS/TCP/UDP 后端，只返回本次验收标记，不接触 NAS 数据。
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import dgram from 'node:dgram';
import fs from 'node:fs';

const marker = process.env.ACCEPTANCE_MARKER;
if (!/^hd-portal-acceptance-[a-z0-9_-]+$/.test(marker ?? '')) {
  throw new Error('缺少有效的验收标记');
}
const handle = (_request, response) => {
  response.writeHead(200, {'content-type': 'application/json'});
  response.end(JSON.stringify({scope: 'LOCAL_BACKEND_ONLY', marker}));
};
http.createServer(handle).listen(18080, '0.0.0.0');
https.createServer({
  cert: fs.readFileSync('/run/secrets/edge_cert'),
  key: fs.readFileSync('/run/secrets/edge_key'),
}, handle).listen(18444, '0.0.0.0');
net.createServer(socket => socket.on('data', data => {
  if (data.length <= 4096) socket.write(Buffer.concat([Buffer.from(`${marker}:`), data]));
  else socket.destroy();
})).listen(12000, '0.0.0.0');
const udp = dgram.createSocket('udp4');
udp.on('message', (data, source) => {
  if (data.length <= 512) udp.send(Buffer.concat([Buffer.from(`${marker}:`), data]), source.port, source.address);
});
udp.bind(12001, '0.0.0.0');
console.log('独立临时后端已启动；不记录请求体、账号或令牌。');
