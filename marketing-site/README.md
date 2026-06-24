# VisibilityCore — Marketing Website

A **standalone** marketing/landing site for VisibilityCore, kept completely
separate from the application. It has **no build step and no dependency** on the
main app — it's a single self-contained `index.html`.

Design inspiration: termii.com (clean, modern SaaS landing). Brand accent is the
VisibilityCore orange.

## View it locally

Just open the file in a browser:

```
marketing-site/index.html
```

Or serve it (nicer for local testing):

```bash
# from the marketing-site folder
python -m http.server 5500
# then open http://localhost:5500
```

## Point the buttons at your app

All "Get started" / "Log in" buttons read one variable near the top of
`index.html`:

```html
<script>window.APP_URL = "https://poultrymaster-web-t6tn7geswq-ew.a.run.app";</script>
```

- `Get started` / `Create account` → `APP_URL/register`
- `Log in` → `APP_URL/login`

Change `APP_URL` to your real app domain (e.g. `https://app.visibilitycore.com`)
when you have one.

## Sections

Sticky nav · hero (with a Business Office mock) · trust strip · features ·
solutions (Water / Poultry / Generic) · how it works · stats · pricing · FAQ ·
final CTA · footer. Fully responsive with a mobile menu and on-scroll reveal
animations.

## Deploy

It's a static site — host it anywhere:

- **Netlify / Vercel / Cloudflare Pages / GitHub Pages**: drop the `marketing-site`
  folder in as the publish directory.
- **Cloud Run / nginx / Apache**: serve the folder statically.
- **Firebase Hosting**: `firebase deploy` with `marketing-site` as `public`.

## Notes

- Tailwind is loaded via the Play CDN (`cdn.tailwindcss.com`) for zero-config
  styling. For a production deploy you may prefer to compile Tailwind to a small
  CSS file, but the CDN is perfectly fine to launch with.
- Copy/pricing are placeholders — edit the text directly in `index.html`.
- No tracking/analytics is included; add your own snippet in `<head>` if needed.
