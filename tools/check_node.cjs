// Local capability probe only. Never connects to a URL or starts a WebSocket.
const major = Number(process.versions.node.split('.')[0]);
const checks = {
  version: process.versions.node,
  minimum: '22.0.0',
  version_ok: major >= 22,
  fetch: typeof fetch === 'function',
  WebSocket: typeof WebSocket === 'function'
};
checks.ok = checks.version_ok && checks.fetch && checks.WebSocket;
console.log(JSON.stringify(checks));
process.exitCode = checks.ok ? 0 : 1;
