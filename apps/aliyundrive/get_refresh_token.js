'use strict'
const puppeteer = require('puppeteer');

async function saveLocalStorage(page, filePath) {
  const json = await page.evaluate(() => {
    const json = {};
    for (const i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      json[key] = localStorage.getItem(key);
    }
    return json;
  });
  fs.writeFileSync(filePath, 'utf8', JSON.stringify(json));
}

async function restoreLocalStorage(page, filePath) {
  const json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  await page.evaluate(json => {
    localStorage.clear();
    for (let key in json)
      localStorage.setItem(key, json[key]);
  }, json);
}

(async () => {
  const { ALIYUNDRIVE_USERNAME, ALIYUNDRIVE_PASSWORD } = process.env;
  // if (!ALIYUNDRIVE_USERNAME || !ALIYUNDRIVE_PASSWORD) {
  //   console.log('[ERR] ALIYUNDRIVE_USERNAME / ALIYUNDRIVE_PASSWORD are required.');
  //   return;
  // }
  // console.log('[INFO] Start fetching REFRESH_TOKEN');
  const browser = await puppeteer.launch({
    headless: true,
    args: [ '--remote-debugging-port=9222', '--remote-debugging-address=0.0.0.0' ]
  });
  const page = await browser.newPage();
  return
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'webdriver', {
      get: () => false
    })
  });
  await page.setViewport({ width: 1920, height: 1080 });
  await page.goto('https://www.aliyundrive.com/sign/in', { waitUntil: 'networkidle0' });
  console.log('[INFO] Opened login page.');
  await page.waitForSelector('iframe');
  // console.log(page.frames())
  const loginFrame = await page.frames().find(f => f.name() === 'alibaba-login-box');
  await page.screenshot({ path: '001.png' });
  await loginFrame.waitForSelector('.sms-login-link');
  const button = await loginFrame.$('.sms-login-link');
  await button.click();
  await loginFrame.type('#fm-login-id', ALIYUNDRIVE_USERNAME);
  await loginFrame.type('#fm-login-password', ALIYUNDRIVE_PASSWORD);
  await page.screenshot({ path: '002.png' });
  // Slider Captcha
  // const sliderElement = await loginFrame.$('.slidetounlock');
  // const slider = await sliderElement.boundingBox();
  // const sliderHandle = await loginFrame.$('.nc_iconfont.btn-slide');
  // const handle = await sliderHandle.boundingBox();
  // await loginFrame.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2);
  // await loginFrame.mouse.down();
  // await loginFrame.mouse.move(handle.x + slider.width, handle.y + handle.height / 2, { steps: 50 });
  // await loginFrame.mouse.up();
  await loginFrame.click('.fm-button.fm-submit.password-login');
  try {
    await page.waitForSelector('div[class^="content--"]', { timeout: 60000 });
  } catch (e) {
    if (e instanceof puppeteer.errors.TimeoutError) {
      // Do something if this is a timeout.
      await page.screenshot({ path: 'failed.png' });
    }
  }
  
  const localStorageJson = await page.evaluate(() => {
    const _json = {};
    for (let index = 0; index < localStorage.length; index++) {
      _json[localStorage.key(index)] = localStorage.getItem(localStorage.key(index));
    }
    return _json;
  });
//   console.log(localStorageJson)
  if (localStorageJson && localStorageJson.token) {
    const tokenJson = JSON.parse(localStorageJson.token);
    if (tokenJson.refresh_token) {
      console.log('REFRESH_TOKEN:' + tokenJson.refresh_token);
    }
  }
  await page.screenshot({ path: 'finish.png' });
  await browser.close();
  console.log('[INFO] Browser was closed.')
})();
