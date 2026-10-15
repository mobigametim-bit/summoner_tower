// Development-only: requires Playwright and Microsoft Edge; no runtime dependency.
const {chromium}=require(process.env.SUMMONER_PLAYWRIGHT || 'playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
const fs=require('node:fs');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1200,height:630},deviceScaleFactor:1});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error')errors.push(message.text())});
  await page.goto(pathToFileURL(path.join(root,'web/branding/preview.html')).href);
  await page.evaluate(async()=>{
   await document.fonts.ready;
   await Promise.all([...document.images].map(image=>image.decode()));
  });
  await page.screenshot({path:path.join(root,'web/branding/og-image-v1.png')});
  await page.setViewportSize({width:512,height:512});
  await page.goto(pathToFileURL(path.join(root,'assets/branding/app_icon.svg')).href);
  await page.screenshot({path:path.join(root,'web/branding/app-icon-v1.png'),omitBackground:true});
  fs.copyFileSync(path.join(root,'web/branding/app-icon-v1.png'),path.join(root,'assets/branding/boot_splash.png'));
  if(errors.length)throw new Error(errors.join('\n'));
  console.log(JSON.stringify({previewBytes:fs.statSync(path.join(root,'web/branding/og-image-v1.png')).size,
   iconBytes:fs.statSync(path.join(root,'web/branding/app-icon-v1.png')).size}));
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
