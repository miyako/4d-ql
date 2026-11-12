import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { strFromU8, unzipSync, zipSync, strToU8 } from 'fflate';

const fixtures = fileURLToPath(new URL('../../../Tests/FourDFileKitTests/Fixtures/WritePro/', import.meta.url));
const objectFiles = unzipSync(readFileSync(`${fixtures}objects.4wp`));
const xml = strFromU8(Object.values(objectFiles)[0]);
const png = Buffer.from(/src="data:image\/png;base64,([^"]+)"/.exec(xml)[1], 'base64');
const imageFile = { name: 'reading-room.png', mimeType: 'image/png', buffer: png };

async function blank(page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
}
async function select(page, first, start, last, end) {
  await page.locator('#paper').evaluate((paper, bounds) => {
    const runs = paper.querySelectorAll('[data-run]');
    const range = document.createRange();
    range.setStart(runs[bounds.first].firstChild, bounds.start);
    range.setEnd(runs[bounds.last].firstChild, bounds.end);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
  }, { first, start, last, end });
}

test('cross-run typing, paragraph splitting, merging and grouped undo', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('Hello world');
  await select(page, 0, 6, 0, 11);
  await page.getByRole('button', { name: 'Bold', exact: true }).click();
  await select(page, 0, 3, 1, 3);
  await page.keyboard.type('X');
  await expect(page.locator('#paper p')).toHaveText('HelXld');
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('#paper p')).toHaveText('Hello world');
  await page.locator('[contenteditable]').first().click();
  await select(page, 0, 3, 0, 3);
  await page.keyboard.press('Enter');
  await expect(page.locator('#paper > p')).toHaveCount(2);
  await expect(page.locator('#paper > p').first()).toHaveText('Hel');
  await expect(page.locator('#paper > p').last()).toHaveText('lo world');
  await page.keyboard.press('Backspace');
  await expect(page.locator('#paper > p')).toHaveCount(1);
  await expect(page.locator('#paper > p')).toHaveText('Hello world');
});

test('named styles, lists, paragraph tools, tables, find and zoom', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('A proper heading');
  await page.locator('#paragraph-style').selectOption('Heading_1');
  await expect(page.locator('#paper > p')).toHaveCSS('font-size', '32px');
  await expect(page.getByRole('button', { name: 'Bold', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: 'Bulleted list', exact: true }).click();
  await expect(page.locator('#paper ul li')).toContainText('A proper heading');
  await page.getByRole('button', { name: 'Bulleted list', exact: true }).click();
  await page.getByRole('button', { name: 'Increase indent', exact: true }).click();
  await expect(page.locator('#paper > p')).toHaveCSS('margin-left', '24px');
  await page.locator('summary').click();
  await page.locator('#spacing').selectOption('18');
  await page.getByRole('button', { name: 'Insert table', exact: true }).click();
  await expect(page.locator('#paper table td')).toHaveCount(4);
  await page.locator('#paper table [contenteditable]').first().fill('Heading cell');
  await page.getByRole('button', { name: 'Add row', exact: true }).click();
  await expect(page.locator('#paper table tr')).toHaveCount(3);
  await page.getByRole('button', { name: 'Add column', exact: true }).click();
  await expect(page.locator('#paper table td')).toHaveCount(9);
  await page.locator('#paper table tr').first().locator('[contenteditable]').nth(1).click();
  await page.getByRole('button', { name: 'Remove column', exact: true }).click();
  await expect(page.locator('#paper table td')).toHaveCount(6);
  await page.getByRole('button', { name: 'Find', exact: true }).click();
  await page.locator('#find-query').fill('heading');
  await expect(page.locator('#find-count')).toHaveText('1 / 2');
  await page.locator('#replacement').fill('title');
  await page.getByRole('button', { name: 'Replace all', exact: true }).click();
  await expect(page.locator('#paper > p').first()).toContainText('A proper title');
  await expect(page.locator('#paper table')).toContainText('title cell');
  await expect(page.locator('#find-count')).toHaveText('0 / 0');
  await page.locator('#find-query').fill('title');
  await expect(page.locator('#find-count')).toHaveText('1 / 2');
  await page.locator('#paper > p [contenteditable]').filter({ hasText: /^title$/ }).fill('subject');
  await expect(page.locator('#find-count')).toHaveText('1 / 1');
  await page.locator('#zoom').selectOption('1.5');
  await expect(page.locator('#paper')).toHaveCSS('zoom', '1.5');
  await expect(page.locator('#statistics')).toContainText('words');
});

test('image drop, resize, deletion, native export and undo', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('Before after');
  await select(page, 0, 7, 0, 7);
  const bounds = await page.locator('[contenteditable]').first().boundingBox();
  await page.locator('#paper').dispatchEvent('drop', {
    dataTransfer: await page.evaluateHandle(({ bytes }) => {
      const transfer = new DataTransfer();
      transfer.items.add(new File([new Uint8Array(bytes)], 'drop.png', { type: 'image/png' }));
      return transfer;
    }, { bytes: [...png] }),
    clientX: bounds.x + 5, clientY: bounds.y + 5,
  });
  await expect(page.locator('#paper img')).toHaveCount(1);
  await page.locator('#paper [data-image]').click();
  await page.locator('#image-width').fill('144');
  await page.getByRole('button', { name: 'Resize image', exact: true }).click();
  await expect(page.locator('#paper img')).toHaveCSS('width', '192px');
  const pending = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
  const download = await pending;
  const exported = strFromU8(unzipSync(readFileSync(await download.path()))['Document.html']);
  expect(exported).toContain('data:image/png;base64,');
  expect(exported).toContain('width:144pt');
  await page.locator('#paper [data-image]').click();
  await page.getByRole('button', { name: 'Remove image', exact: true }).click();
  await expect(page.locator('#paper img')).toHaveCount(0);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('#paper img')).toHaveCount(1);
});

test('draft recovery retains images, named versions and undo after reload', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('First version');
  await page.locator('#image-file').setInputFiles(imageFile);
  await expect(page.locator('#paper img')).toHaveCount(1);
  await page.getByRole('button', { name: 'History', exact: true }).click();
  await page.locator('#version-name').fill('With image');
  await page.getByRole('button', { name: 'Save version', exact: true }).click();
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.locator('[contenteditable]').first().fill('Second version');
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  page.on('dialog', dialog => dialog.accept());
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await expect(page.locator('#paper')).toContainText('Second version');
  await expect(page.locator('#paper img')).toHaveCount(1);
  await page.getByRole('button', { name: 'History', exact: true }).click();
  const version = page.locator('#version-list li').filter({ hasText: 'With image' });
  await version.getByRole('button', { name: 'Restore', exact: true }).click();
  await expect(page.locator('#paper')).toContainText('First version');
  await expect(page.locator('#paper img')).toHaveCount(1);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('#paper')).toContainText('Second version');
});

test('rich clipboard is sanitized and archive-relative images are displayed without network requests', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().click();
  const requests = [];
  page.on('request', request => { if (request.url().includes('example.invalid')) requests.push(request.url()); });
  await page.locator('[contenteditable]').first().evaluate(element => {
    const clipboard = new DataTransfer();
    clipboard.setData('text/html', '<div><p><b>Pasted title</b></p><p><i>Body text</i><img src="https://example.invalid/track"/><script>window.pasteExecuted=true</script></p></div>');
    clipboard.setData('text/plain', 'Pasted title\nBody text');
    element.dispatchEvent(new ClipboardEvent('paste', { clipboardData: clipboard, bubbles: true, cancelable: true }));
  });
  await expect(page.locator('#paper > p')).toHaveCount(2);
  await expect(page.locator('#paper')).toContainText('Pasted title');
  expect(await page.evaluate(() => window.pasteExecuted)).toBeUndefined();
  expect(requests).toEqual([]);
  await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
  const source = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Asset</title></head><body><p><img src="images/photo.png"/></p></body></html>';
  const archive = zipSync({ 'Nested/Doc.html': strToU8(source), 'Nested/images/photo.png': png });
  await page.locator('#file').setInputFiles({ name: 'asset.4wp', mimeType: 'application/zip', buffer: Buffer.from(archive) });
  await expect(page.locator('#paper img')).toHaveCount(1);
  await expect(page.locator('#paper img')).toHaveAttribute('src', /^data:image\/png;base64,/);
});

test('moving an image keeps a single native image and supports keyboard deletion and undo', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('Before after');
  await select(page, 0, 7, 0, 7);
  await page.locator('#image-file').setInputFiles(imageFile);
  await expect(page.locator('#paper img')).toHaveCount(1);
  await page.getByRole('button', { name: 'Add paragraph', exact: true }).click();
  await page.locator('#paper > p').last().locator('[contenteditable]').first().fill('Destination');
  const target = page.locator('#paper > p').last().locator('[contenteditable]').first();
  const bounds = await target.boundingBox();
  const transfer = await page.evaluateHandle(() => new DataTransfer());
  await page.locator('#paper img').dispatchEvent('dragstart', { dataTransfer: transfer });
  await target.dispatchEvent('drop', { dataTransfer: transfer, clientX: bounds.x + 5, clientY: bounds.y + 5 });
  await expect(page.locator('#paper img')).toHaveCount(1);
  await expect(page.locator('#paper > p').last().locator('img')).toHaveCount(1);
  await page.locator('#paper [data-image]').focus();
  await page.keyboard.press('Enter');
  await page.keyboard.press('Delete');
  await expect(page.locator('#paper img')).toHaveCount(0);
  await expect(page.locator('#paper')).toContainText('Destination');
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('#paper img')).toHaveCount(1);
});

test('a stale tab cannot overwrite another tab’s recovered document', async ({ page, context }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().fill('Shared initial');
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  const second = await context.newPage();
  await second.goto('/');
  await expect(second.locator('#paper')).toContainText('Shared initial');
  await page.locator('[contenteditable]').first().fill('Newest saved work');
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await second.locator('[contenteditable]').first().fill('Conflicting draft');
  await expect(second.locator('#error-message')).toContainText('Another tab saved a newer local session');
  const third = await context.newPage();
  await third.goto('/');
  await expect(third.locator('#paper')).toContainText('Newest saved work');
  await expect(second.locator('#paper')).toContainText('Conflicting draft');
});

test('unavailable recovery storage is reported without disabling editing or export', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(window, 'indexedDB', { value: {
    open() { throw new DOMException('Storage blocked', 'SecurityError'); },
  } }));
  await page.goto('/');
  await expect(page.locator('#error-message')).toContainText('Local recovery could not be saved or loaded');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await page.locator('[contenteditable]').first().fill('Keep an independent copy');
  const pending = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
  const download = await pending;
  const document = documentFromDownload(await download.path());
  expect(document).toContain('Keep an independent copy');
});

function documentFromDownload(path) {
  return strFromU8(unzipSync(readFileSync(path))['Document.html']);
}

test('IME composition, paragraph-boundary selections and select-all update source XML', async ({ page }) => {
  await blank(page);
  await page.locator('[contenteditable]').first().evaluate(element => {
    element.focus();
    element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    element.textContent = '日本語';
    element.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '日本語' }));
  });
  await expect(page.locator('#paper')).toContainText('日本語');
  await page.locator('#paper p').first().evaluate(paragraph => {
    const range = document.createRange();
    range.selectNodeContents(paragraph);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
  });
  await page.getByRole('button', { name: 'Bold', exact: true }).click();
  await expect(page.locator('[contenteditable]').filter({ hasText: '日本語' })).toHaveCSS('font-weight', '700');
  await page.locator('[contenteditable]').filter({ hasText: '日本語' }).click();
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type('Replacement');
  await expect(page.locator('#paper p')).toHaveText('Replacement');
});
