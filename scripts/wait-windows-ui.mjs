import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
const report = { ready: false, endpoint: 'loopback WebView2 CDP', attempts: 0 };
const deadline = Date.now() + 90_000;
while (Date.now() < deadline) {
  report.attempts++;
  try {
    const targets = await fetch('http://127.0.0.1:9223/json/list').then(r => r.json());
    const target = targets.find(t => t.type === 'page' && t.url.startsWith('http://127.0.0.1:8788/'));
    report.page_targets = targets.filter(t => t.type === 'page').length;
    if (target) {
      const value = await new Promise((resolve, reject) => {
        const ws = new WebSocket(target.webSocketDebuggerUrl);
        const timer = setTimeout(() => { ws.close(); reject(new Error('DOM readiness timed out')); }, 5000);
        ws.onopen = () => ws.send(JSON.stringify({id:1, method:'Runtime.evaluate', params:{expression:'JSON.stringify({state:document.readyState,title:document.title,inputs:document.querySelectorAll("input").length,textLength:document.body?.innerText.length??0})',returnByValue:true}}));
        ws.onerror = () => { clearTimeout(timer); reject(new Error('WebView2 debug connection failed')); };
        ws.onmessage = event => {
          const data = JSON.parse(event.data);
          if (data.id !== 1) return;
          clearTimeout(timer); ws.close();
          if (data.result?.result?.value) resolve(JSON.parse(data.result.result.value));
          else reject(new Error('WebView2 DOM unavailable'));
        };
      });
      Object.assign(report, value);
      if (value.state === 'complete' && value.inputs >= 4 && value.textLength > 80) { report.ready = true; break; }
    }
  } catch (error) { report.last_error = error.message; }
  await new Promise(r => setTimeout(r, 2000));
}
await writeFile(join(process.env.HT_WINDOWS_UI_OUTPUT || 'outputs/windows-ui', 'readiness.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
if (!report.ready) process.exitCode=1;
