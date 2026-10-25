# UI

Weave is the reference implementation of the Patchwork design system. The guide lives in internal-docs: [design/README.md](https://github.com/patchworklabsorg/internal-docs/blob/main/design/README.md) (principles), [tokens.md](https://github.com/patchworklabsorg/internal-docs/blob/main/design/tokens.md), [components.md](https://github.com/patchworklabsorg/internal-docs/blob/main/design/components.md) and [icons.md](https://github.com/patchworklabsorg/internal-docs/blob/main/design/icons.md). This page covers only what is specific to Weave.

## Where things are

| What | Where |
|---|---|
| Tokens and component classes | `app/assets/tailwind/application.css` |
| Fonts (self-hosted Geist, Shantell Sans) | `app/assets/tailwind/fonts.css`, `public/fonts` |
| View helpers (`badge`, `page_header`, `nav_link`, `empty_state`, `form_errors`, `copy_button`, `avatar`, `dl_row`) | `app/helpers/ui_helper.rb` |
| Dates and times (`time_label(time, style)`, styles `:date`, `:datetime`, `:relative`, `:month`, `:day`) | `app/helpers/time_helper.rb` |
| Icons (`icon(:name)`, Lucide through `lucide-rails`) | `app/helpers/icon_helper.rb` |
| Layouts | `app/views/layouts/application.html.erb` (member), `admin.html.erb` (admin), `sessions.html.erb` and `doorkeeper/application.html.erb` (focus) |
| Shared partials | `app/views/shared/`: `_head`, `_topbar`, `_sidebar`, `_wordmark`, `_theme`, `_theme_toggle`, `_flash`, `_form_errors`, `_search_form`, `_command_bar`, `_impersonation_banner`, `_staging_badge` |
| Stimulus controllers for the UI | `app/javascript/controllers/`: `flash`, `drawer`, `command_bar`, `clipboard`, `reveal`, `search`, `address_sync` |
| Command bar search | `app/controllers/admin/search_controller.rb`, `GET /admin/search.json?q=` |

## Which layout

| Controller | Layout | Shell |
|---|---|---|
| `Admin::*` | `admin` | sidebar + top bar, content in `.page.page-wide` |
| `UsersController` (except `new`), `PasskeysController`, `PasswordsController`, `AuthController#me` | `application` | top bar, the view adds `<div class="page">` |
| `HomeController`, `AuthController` sign-in actions, `UsersController#new`, `EmailConfirmationsController#show`, `ExpiredPasswordsController`, `SlackOnboardingController`, `BirthdaysController`, `GuardianConsent*Controller` | `sessions` | one `.patch` on the quilt lattice |
| Doorkeeper | `doorkeeper/application` | same as `sessions` |

## Adding a page

1. `<% content_for :title, "Groups" %>` first. It becomes the `<title>` and the admin crumb.
2. On member pages wrap the content in `<div class="page">` (`page page-narrow` for a form). Admin pages are already wrapped.
3. Start with `page_header("Groups", lede: "…") do … end`. The one `btn-primary` goes in that block.
4. Cards for each group of content. Tables in `card card-flush`. Lists of things with actions in `.record-list`.
5. For a list that can grow, add `render "shared/search_form", url:, frame:, placeholder:` in the card header, `turbo_frame_tag` around the table, and `params[:search]` in the controller (see `Admin::GroupsController#index`).
6. For an admin page, add it to `app/views/shared/_sidebar.html.erb` and to the `pages` list in `app/views/shared/_command_bar.html.erb`.
7. Run the request spec. No rubocop on views, but keep the ERB tidy.

## Rules the audit enforces

- Show every date through `time_label`. No `strftime`, `to_fs` or `time_ago_in_words` in a view outside the mailers.
- The public identifier is the "Weave ID" everywhere. Not "PWL ID", not "P_ID".
- A form with `data: { turbo: false }` never sees `data-turbo-confirm`. Confirm through the `confirm-submit` controller on the form (`admin/users/index` has the pattern).
- Every layout starts with the `.skip-link` and gives `<main>` the id `main`. Keep both when you add a layout.
- Keyboard focus is an outline (`:focus-visible` in `application.css`). Do not set `outline: none` on a control.
- A long reference block (integration notes, an optional address) folds into `<details class="card">` with the `.card-header` as the `<summary>`.
- Faint text (`text-ink-faint`) is tuned to 4.5:1 on paper and panel. Do not lighten it for effect.


## Dark mode

Every color is a token declared once with `light-dark()`. The theme follows the device by default and switches live with it. `shared/_theme` sets `data-theme` and `data-theme-source` on `<html>` before first paint: a stored `localStorage.theme` of `light` or `dark` pins the theme, anything else means "follow the device". The toggle (`shared/_theme_toggle`) cycles system → light → dark → system. There is nothing to do per page: use token utilities (`bg-paper`, `text-ink-soft`, `border-hairline`) and never a hex or a raw Tailwind palette color.

## Assets

- CSS: `bin/rails tailwindcss:build` (or `tailwindcss:watch` through `bin/dev`). Tailwind v4 scans `app/views` and `app/helpers`; a class only present in a Ruby string interpolation (`"bg-#{name}"`) is not generated. Write the full class.
- JS: `bun run build` (Rollup). New Stimulus controllers must be registered in `app/javascript/controllers/index.js`.

## Not part of the system

- Mailer templates (`app/views/*_mailer`) use inline styles for email clients.
- `public/*.html` error pages are static and self-contained on purpose.
- Engine UIs under `/admin` (Mission Control, Flipper, Blazer, Audits1984) keep their own look.
