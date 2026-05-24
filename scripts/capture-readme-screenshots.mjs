#!/usr/bin/env node
/**
 * Capture README screenshots from www/ with mocked API (no router required).
 * Usage: node scripts/capture-readme-screenshots.mjs
 */
import { chromium } from 'playwright';
import { createServer } from 'http';
import { readFileSync, mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const www = path.join(repo, 'www');
const outDir = path.join(repo, 'docs', 'images');

const domains = `yandex.ru
ya.ru
yandex.com
yandex.net
yastatic.net
yandex.st
mail.ru
mail.com
imgsmail.ru
mycdn.me
vk.com
vk.me
vkuservideo.net
vkuseraudio.net
userapi.com
vk-cdn.net
ok.ru
odnoklassniki.ru
okcdn.ru`
  .trim()
  .split('\n')
  .map((d) => ({ domain: d, group: 'ru-services', upstream: 'yandex-dot' }));

const status = {
  ok: true,
  smartdns: { running: true, pid: '1842' },
  domains: domains.length,
  lan_ip: '192.168.1.1',
  web_port: 3200,
  url: 'http://192.168.1.1:3200',
  last_apply: '2026-05-24 12:04:11 reload OK',
  logs: [
    '2026-05-24 12:01:02 SmartDNS запущен, listen 0.0.0.0:53',
    '2026-05-24 12:01:03 Политика ru-services → yandex-dot (19 доменов)',
    '2026-05-24 12:04:11 lookup vk.com A → 87.240.190.78',
  ],
};

const digOutput = `; <<>> DiG 9.18.24 <<>> @127.0.0.1 vk.com A
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 48291
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;vk.com.                        IN      A

;; ANSWER SECTION:
vk.com.                 300     IN      A       87.240.190.78

;; Query time: 24 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Sun May 24 12:04:11 MSK 2026
;; MSG SIZE  rcvd: 52`;

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
};

function createStaticServer() {
  const yaml = readFileSync(path.join(repo, 'etc', 'config.yaml.example'), 'utf8');
  return createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname.startsWith('/api/')) {
      const route = url.pathname.slice(4);
      if (route === '/status') {
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(status));
        return;
      }
      if (route === '/domains') {
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ ok: true, domains }));
        return;
      }
      if (route.startsWith('/test')) {
        res.setHeader('Content-Type', 'application/json');
        res.end(
          JSON.stringify({
            ok: true,
            domain: url.searchParams.get('domain') || 'vk.com',
            type: 'A',
            ms: 24,
            output: digOutput,
          })
        );
        return;
      }
      if (route === '/config') {
        res.setHeader('Content-Type', 'application/x-yaml');
        res.end(yaml);
        return;
      }
      if (route === '/reload') {
        res.setHeader('Content-Type', 'application/json');
        res.end('{"ok":true,"message":"applied"}');
        return;
      }
      res.statusCode = 404;
      res.end('{}');
      return;
    }
    const rel = url.pathname === '/' ? '/index.html' : url.pathname;
    const file = path.join(www, rel);
    try {
      const data = readFileSync(file);
      res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
      res.end(data);
    } catch {
      res.statusCode = 404;
      res.end('not found');
    }
  });
}

async function waitDashboard(page) {
  await page.waitForFunction(
    () => document.getElementById('stat-domains')?.textContent !== '—',
    { timeout: 10000 }
  );
  await page.evaluate(() => {
    const log = document.getElementById('log-container');
    if (!log) return;
    log.innerHTML = `
      <div class="log-line"><span class="log-time">12:01:02</span> SmartDNS запущен, listen 0.0.0.0:53</div>
      <div class="log-line"><span class="log-time">12:01:03</span> Политика ru-services → yandex-dot (19 доменов)</div>
      <div class="log-line"><span class="log-time">12:04:11</span> lookup vk.com A → 87.240.190.78</div>
    `;
  });
}

async function main() {
  mkdirSync(outDir, { recursive: true });
  const server = createStaticServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const base = `http://127.0.0.1:${port}/`;

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });

  await page.goto(base);
  await page.evaluate(() => localStorage.setItem('ksd_token', 'readme-demo'));
  await page.reload();
  await waitDashboard(page);
  await page.screenshot({ path: path.join(outDir, 'overview.png') });

  await page.click('.nav-item[data-tab="upstreams"]');
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(outDir, 'upstreams-domains.png') });

  await page.click('.nav-item[data-tab="test"]');
  await page.click('#run-test');
  await page.waitForFunction(
    () => (document.getElementById('test-output')?.textContent || '').includes('vk.com'),
    { timeout: 5000 }
  );
  await page.waitForTimeout(200);
  await page.screenshot({ path: path.join(outDir, 'test-lookup.png') });

  await browser.close();
  server.close();
  console.log('Saved screenshots to', outDir);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
