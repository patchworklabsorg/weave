// Entry point for the JS bundle (rollup.config.js builds app/assets/builds/application.js).
import "@hotwired/turbo-rails"
import "./controllers"

// The browser time zone, for the server to show times in (ViewerTimeZone).
// Set on every load, so it follows the device the person uses now.
try {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (zone) document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=31536000; samesite=lax; secure`
} catch {
  // Without a zone the server uses the session zone, then UTC.
}
