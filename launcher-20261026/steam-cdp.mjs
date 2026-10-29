const localPort = Number(process.argv[3] || '18094');
if (!Number.isInteger(localPort) || localPort < 1 || localPort > 65535) throw Error('Invalid local port');
const pages = await (await fetch(`http://127.0.0.1:${localPort}/json/list`)).json();
const page = pages.find(p => p.title === 'SharedJSContext');
if (!page) throw Error('Steam SharedJSContext is not ready');
const endpoint = new URL(page.webSocketDebuggerUrl);
if (endpoint.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '[::1]'].includes(endpoint.hostname)
    || !['8080', String(localPort)].includes(endpoint.port)) throw Error('Unexpected Steam CDP endpoint');
endpoint.hostname = '127.0.0.1';
endpoint.port = String(localPort);
const socket = new WebSocket(endpoint);
const timer = setTimeout(() => { socket.close(); process.exitCode = 1; }, 15000);
socket.onopen = () => socket.send(JSON.stringify({
  id: 1, method: 'Runtime.evaluate',
  params: { expression: process.argv[2], returnByValue: true, awaitPromise: true }
}));
socket.onmessage = e => {
  const result = JSON.parse(e.data);
  if (result.id === 1) {
    console.log(JSON.stringify(result));
    clearTimeout(timer);
    socket.close();
  }
};
socket.onerror = e => { console.error(String(e)); clearTimeout(timer); socket.close(); process.exitCode = 1; };
