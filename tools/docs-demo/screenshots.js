// Screenshots for the guide, taken from the demo stack (demo.sh up, http://localhost:13000).
// A Playwright function: run it with a Playwright runner that passes `page`, for example the
// Playwright MCP tool "run code" with filename tools/docs-demo/screenshots.js, from the repo root.
// Writes docs/assets/<name>.png (English dashboards) and docs/assets/ru/<name>.png (the Russian
// copies, uid <uid>-ru, same names and ranges) at 1920 px, Grafana's dark theme, the menu undocked.
async (page) => {
  const base = 'http://localhost:13000';
  await page.setViewportSize({ width: 1920, height: 1080 });

  // Log in with the demo password set in demo.sh (skipped when the browser is logged in).
  await page.goto(base + '/login');
  await page.waitForTimeout(2000);
  if (await page.locator('input[name="user"]').count()) {
    await page.fill('input[name="user"]', 'admin');
    await page.fill('input[name="password"]', 'demo-grafana');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(3000);
  }
  // Grafana asks to change the password on the first login: skip it.
  const skip = page.getByRole('button', { name: /skip/i });
  if (await skip.count()) await skip.first().click();
  // Keep the Grafana menu closed so the dashboard gets the full width.
  await page.evaluate(() => localStorage.setItem('grafana.navigation.docked', 'false'));

  const settle = async () => {
    await page.waitForTimeout(6000);
    for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 900); await page.waitForTimeout(1000); }
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(4000);
  };
  const shot = async (out, name, url) => {
    await page.goto(base + url);
    await settle();
    await page.screenshot({ path: out + name + '.png', fullPage: true });
  };

  // English dashboards, then the Russian copies (uid + '-ru', translated "Open session" link).
  for (const [out, suffix, openTitle] of [['docs/assets/', '', 'Open session'],
                                         ['docs/assets/ru/', '-ru', 'Открыть сессию']]) {
    await shot(out, 'overview', '/d/cc-usage' + suffix + '?from=now-30d&to=now&refresh=');
    await shot(out, 'sessions', '/d/cc-sessions' + suffix + '?from=now-7d&to=now&refresh=');
    await shot(out, 'prompts', '/d/cc-prompts' + suffix + '?from=now-7d&to=now&refresh=');
    await shot(out, 'efficiency', '/d/cc-efficiency' + suffix + '?from=now-7d&to=now&refresh=');
    await shot(out, 'agents', '/d/cc-agents' + suffix + '?from=now-7d&to=now&refresh=');
    await shot(out, 'tools', '/d/cc-tools' + suffix + '?from=now-7d&to=now&refresh=');
    await shot(out, 'health', '/d/cc-health' + suffix + '?from=now-7d&to=now&refresh=');

    // One session opened from the Sessions table: the link zooms the range to that session.
    await page.goto(base + '/d/cc-sessions' + suffix + '?from=now-7d&to=now&refresh=');
    await page.waitForTimeout(8000);
    const href = await page.locator('a[title="' + openTitle + '"]').first().getAttribute('href');
    await shot(out, 'session-selected', href + '&refresh=');
  }
  return 'done';
}
