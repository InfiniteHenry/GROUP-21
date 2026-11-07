# Recall

## Contract SDK (v1)

The backend contract SDK is `frontend/recall-api.js`. Load it from a plain
`<script>` tag and create it with `{ backend: 'mock' }` for local use or
`{ backend: 'supabase', supabase: client }` for cloud sync. Await `api.ready()`
before calling other methods. The mock stores its data in IndexedDB (`recall`)
and keeps its mock sign-in in localStorage. The Supabase client must be created
with the project's URL and publishable key only.

Apply `supabase/migrations/202611070001_recall_contract_v1.sql` with the
Supabase CLI (`supabase db push`) or run it in the SQL editor. It creates
per-user tables, row-level security, and RPC entry points. The browser is
granted read access to its own rows and all writes are intended to go through
the SDK RPCs.

Run the contract checks with `npm test`. The shared vectors are in
`tests/contract-vectors.json`. The current test suite exercises the mock and
checks migration definitions, but it does not execute the SQL against a local
Postgres/Supabase instance. Install and start Supabase CLI/Postgres to validate
the migration and RLS behavior against a live database.

Scheduling defaults where v1 is silent: a successful review schedules 1 day,
then doubles the interval to a 30-day cap; a failed review returns after 10
minutes. Mastery means a correct streak of at least three. Shuffle uses a
random order each call. Legacy `importData` expects `{ decks: [{ name,
cards: [{ front, back }] }] }` and imports it once per device.

Recall is a small, presentation-ready flashcard study app inspired by spaced-repetition tools such as Anki. It uses plain HTML, CSS, and JavaScript, plus Supabase for user accounts and cloud sync.

Recall is also a Progressive Web App. Once hosted over HTTPS, supported browsers can install it, and the app shell is cached for faster repeat visits and offline launch. Guest data remains on that browser; account sign-in and cloud sync require an internet connection.

## Run it

1. Download or unzip the `Recall` project folder.
2. Open `index.html` in a modern browser.
3. Follow **Set up accounts and cloud sync** below, then create an account and add your own cards.

## Set up accounts and cloud sync

1. Create a Supabase project.
2. In the Supabase SQL Editor, run the contents of `supabase-setup.sql`.
3. Copy the project URL and publishable key from the Supabase project API settings into `config.js`. The browser key is public by design; never use a `service_role` or secret key here.
4. Upload the whole Recall folder to a static website host. Supabase Auth will send an email confirmation by default; set the deployed site URL in the Supabase Auth URL settings.
5. The welcome page offers Google sign-in and guest access. Signed-in users see their Google profile name and photo, and their decks and progress sync across devices. Guest data stays on that device and does not sync.

## Install Recall

Deploy the contents of the `frontend` folder (or this project folder) to a host that serves HTTPS, such as Netlify. On supported browsers, use **Install app** on the welcome screen. If that button is not offered, use the browser menu’s **Install app** or **Add to Home Screen** action. On iPhone/iPad, open the deployed site in Safari, tap **Share**, then **Add to Home Screen**.

The service worker caches the app shell and icons, not Google/Supabase API requests. Guest use can start offline after the first online visit; account authentication and sync need a connection.

## Google sign-in setup

Google sign-in uses Supabase Auth as the OAuth broker. The Google client secret belongs in Supabase's provider settings and must never be added to the public website files.

1. In Google Cloud Console, create or choose a project and configure the Google Auth Platform consent screen/branding. For an external testing app, add your own Google account as a test user.
2. Open **Google Auth Platform → Clients → Create client**. Choose **Web application**.
3. Add your deployed website origin to **Authorized JavaScript origins** (for local preview, add the local web origin such as `http://localhost:8000`).
4. In Supabase, open **Authentication → Sign In / Providers → Google** and copy the callback URL shown there.
5. Add that exact Supabase callback URL under the Google OAuth client’s **Authorized redirect URIs**. Create the client and copy its ID and secret.
6. Paste the Google Client ID and Client Secret into the Google provider settings in Supabase, then enable Google.
7. In Supabase **Authentication → URL Configuration**, set the deployed site as the Site URL and add local/deployed app URLs to the redirect URL allow list.
8. Put only the Supabase project URL and publishable/anon key into `config.js`. Never put the Google client secret or a Supabase service-role key there.

The app calls Supabase `signInWithOAuth({ provider: 'google' })`; Google returns the user's name and profile image as auth metadata. The database row-level security in `supabase-setup.sql` isolates each signed-in user's saved decks.

The SQL enables row-level security so each account can only access its own saved Recall data. The Supabase project URL and publishable key are still required before sign-up and cloud sync can work.

`supabase-setup.sql` creates one `recall_data` row per account. Its `data` JSONB field stores that account's decks, flashcards, review scheduling, and study sessions together. Run the SQL once in the Supabase SQL Editor before trying to save cloud data.

To run the included smoke checks from this folder, use `node checks.js` (Node.js 18 or newer).

All deck, card, and study-session data is stored in the browser's local storage. It stays on that device and browser. Clearing browser data removes the saved app data.

## Features

- Dashboard with review queue, deck overview, accuracy, and study streak
- Create, edit, and delete decks
- Add, edit, and delete flashcards
- Search and sort decks
- Study a deck in its saved order or shuffle the questions for a fresh order
- Study mode with answer reveal and “Got it” / “Study again” self-assessment
- “Study again” returns to the same question; decks can also be manually reviewed any time, including cards scheduled for later
- Lightweight spaced repetition: correct answers schedule the card in 1, 2, 4, 8… up to 30 days; missed cards return in 10 minutes
- Study activity, accuracy, streak, and deck mastery statistics
- Responsive layout for smaller screens
- Starts with an empty study space, ready for your own content

## Project files

- `index.html` — app structure
- `styles.css` — visual design and responsive layout
- `app.js` — interactions, local storage, study scheduling, and statistics
- `checks.js` — dependency-free smoke checks for core study behavior
- `config.js` — Supabase project URL and publishable key placeholders (not Google credentials)
- `supabase-setup.sql` — private per-account data table and access policies
- `manifest.webmanifest` — install name, display mode, and app icons
- `sw.js` — app-shell caching for install and offline launch
- `icons/` — install icons at 192px and 512px

## Demo tip

Create a deck, add a few cards, then study them with both ratings to demonstrate progress and accuracy. Visit **Study stats** to review the results.
