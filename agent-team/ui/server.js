const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PORT = process.env.AGENT_TEAM_UI_PORT || 8090;
const HEALTH_PORT = process.env.HEALTH_MONITOR_PORT || 8091;
const WORKSPACE = process.env.WORKSPACE || '/home/node/.openclaw/workspace';
const UI_DIR = path.join(WORKSPACE, 'agent-team', 'ui');
const CONFIG_FILE = path.join(WORKSPACE, 'agent-team', 'config.json');

// ── 启动健康监控子进程 ──
let healthProc = null;

function startHealthMonitor() {
  const script = path.join(WORKSPACE, 'agent-team', 'health-monitor.js');
  if (!fs.existsSync(script)) return;

  healthProc = spawn('node', [script], {
    env: { ...process.env, WORKSPACE },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  healthProc.stdout.on('data', d => process.stdout.write(`[health] ${d}`));
  healthProc.stderr.on('data', d => process.stderr.write(`[health] ${d}`));
  healthProc.on('exit', code => {
    console.log(`[health] 监控进程退出 (${code})，5s 后重启...`);
    setTimeout(startHealthMonitor, 5000);
  });
}

startHealthMonitor();

// ── 代理到健康监控 API ──
async function proxyHealthApi(req, res, pathSuffix) {
  const options = {
    hostname: '127.0.0.1',
    port: HEALTH_PORT,
    path: pathSuffix,
    method: req.method,
    headers: { ...req.headers, host: `127.0.0.1:${HEALTH_PORT}` },
  };

  return new Promise((resolve) => {
    const proxyReq = http.request(options, (proxyRes) => {
      let body = '';
      proxyRes.on('data', c => body += c);
      proxyRes.on('end', () => {
        res.writeHead(proxyRes.statusCode, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(body);
        resolve();
      });
    });

    proxyReq.on('error', () => {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'health monitor not available' }));
      resolve();
    });

    if (req.body) proxyReq.write(req.body);
    proxyReq.end();
  });
}

// ── 主服务 ──
const server = http.createServer((req, res) => {
  const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST', 'Access-Control-Allow-Headers': 'Content-Type' };

  // CORS preflight
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); res.end(); return; }

  // 容器内只接收内网请求，外网通过 Docker 端口映射进来时源 IP 为 172.x 或 127.0.0.1
  const ip = req.socket.remoteAddress || '';
  const isAllowed = ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1'
    || ip.startsWith('172.') || ip.startsWith('::ffff:172.')
    || ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('::ffff:192.168.') || ip.startsWith('::ffff:10.');
  if (!isAllowed) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden: LAN only');
    return;
  }

  // 静态页面
  if (req.url === '/' || req.url === '/index.html') {
    const html = fs.readFileSync(path.join(UI_DIR, 'index.html'), 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  }
  // 配置读取
  else if (req.url === '/api/config' && req.method === 'GET') {
    try {
      const config = fs.readFileSync(CONFIG_FILE, 'utf8');
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
      res.end(config);
    } catch (e) {
      res.writeHead(404, { ...cors, 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'config not found' }));
    }
  }
  // 配置写入
  else if (req.url === '/api/config' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        JSON.parse(body);
        fs.writeFileSync(CONFIG_FILE, body, 'utf8');
        res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { ...cors, 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'invalid JSON' }));
      }
    });
  }
  // 文档读取
  else if (req.url.startsWith('/api/doc/') && req.method === 'GET') {
    const docName = req.url.replace('/api/doc/', '').replace(/\.\./g, '');
    const docPath = path.join(WORKSPACE, docName);
    try {
      const content = fs.readFileSync(docPath, 'utf8');
      res.writeHead(200, { ...cors, 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(content);
    } catch (e) {
      res.writeHead(404, { ...cors, 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'doc not found' }));
    }
  }
  // 健康状态代理
  else if (req.url === '/api/health' && req.method === 'GET') {
    proxyHealthApi(req, res, '/api/health');
  }
  else if (req.url === '/api/health/logs' && req.method === 'GET') {
    proxyHealthApi(req, res, '/api/health/logs');
  }
  else if (req.url === '/api/health/check' && req.method === 'POST') {
    proxyHealthApi(req, res, '/api/health/check');
  }
  else if (req.url === '/api/health/check-model' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      req.body = body;
      proxyHealthApi(req, res, '/api/health/check-model');
    });
  }
  else if (req.url === '/api/health/recover' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      req.body = body;
      proxyHealthApi(req, res, '/api/health/recover');
    });
  }
  else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Agent Team UI 运行在 http://0.0.0.0:${PORT}`);
});
