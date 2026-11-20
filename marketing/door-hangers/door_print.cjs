const { chromium } = require('playwright'); const fs=require('fs'); const path=require('path');
(async()=>{ const dir=process.argv[2]; const b=await chromium.launch();
for (const f of fs.readdirSync(dir).filter(f=>f.endsWith('.html'))) {
  const p=await b.newPage({viewport:{width:408,height:1056}, deviceScaleFactor:2});
  await p.goto('file://'+path.join(dir,f), {waitUntil:'networkidle'}); await p.evaluate(()=>document.fonts.ready);
  await p.pdf({path:path.join(dir,f.replace('.html','.pdf')), width:'4.25in', height:'11in', printBackground:true});
  if (f.includes('cut-guide') && !f.includes('bilingual')) await p.screenshot({path:path.join(dir,f.replace('.html','.png'))});
  await p.close(); }
await b.close(); })();
