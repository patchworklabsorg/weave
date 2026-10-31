// Screenshot routine for the Playwright MCP tool browser_run_code_unsafe.
//
// Copy this file to .playwright-mcp/shoot.js (git ignores that folder), fill
// in CONFIG, then call browser_run_code_unsafe with `filename` set to that
// path. The tool can load files only inside the worktree; page.screenshot can
// write anywhere.
//
// For each shot and each viewer it signs in, opens the page in light and dark
// at each width, and saves <name>-<scheme>-<width>.png. It returns one line per
// image with the HTTP status and any element wider than the viewport, so a 500
// (Bullet N+1 in the test env) or a phone overflow is visible in the result.
async (page) => {
  const CONFIG = {
    base: 'http://127.0.0.1:3077',
    out: '/ABSOLUTE/PATH/TO/SCRATCHPAD/shots',
    widths: [1280, 390],
    schemes: ['light', 'dark'],
    // One entry per signed-in viewer. Tokens come from sign_in_links.rb and
    // work once each.
    viewers: [
      { token: 'TOKEN', shots: [{ name: '1-example', path: '/profile' }] },
    ],
  };

  const signIn = async (token) => {
    await page.context().clearCookies();
    await page.goto(CONFIG.base + '/auth/magic_link/' + token);
    await Promise.all([
      page.waitForNavigation(),
      page.getByRole('button', { name: 'Sign in', exact: true }).click(),
    ]);
  };

  const results = [];
  for (const viewer of CONFIG.viewers) {
    await signIn(viewer.token);
    for (const shot of viewer.shots) {
      for (const scheme of CONFIG.schemes) {
        await page.emulateMedia({ colorScheme: scheme });
        for (const width of CONFIG.widths) {
          await page.setViewportSize({ width, height: 900 });
          const response = await page.goto(CONFIG.base + shot.path);
          await page.waitForLoadState('networkidle');
          await page.screenshot({ path: `${CONFIG.out}/${shot.name}-${scheme}-${width}.png`, fullPage: true });
          const wide = await page.evaluate(() =>
            [...document.querySelectorAll('body *')]
              .filter((el) => el.getBoundingClientRect().right > window.innerWidth + 1)
              .slice(0, 3)
              .map((el) => `${el.tagName}.${String(el.className).slice(0, 40)}`));
          results.push(`${response.status()} ${shot.name} ${scheme} ${width}${wide.length ? ' OVERFLOW ' + wide.join(' | ') : ''}`);
        }
      }
    }
  }
  return results;
}
