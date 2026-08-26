# Rucio

Rucio is a cross-platform EPUB reader built with Flutter. It combines a synced personal library with offline reading, reading progress, highlights, notes, configurable typography, translation, and optional AI and vocabulary tools.

## Features

- Email and password authentication with Supabase
- Private, user-scoped EPUB library stored in Supabase Storage
- EPUB metadata and cover extraction during upload
- Responsive library grid with search and book removal controls
- Paginated EPUB reading powered by epub.js
- Android/iOS WebView and dedicated Windows WebView support
- Offline EPUB caching
- Synced reading position with automatic debounce and manual save
- Reader themes, fonts, line spacing, margins, alignment, and column layout
- Table of contents and in-book search
- Highlights and notes with book-specific and global views
- English-to-Spanish on-device translation
- Optional Claude reading assistant with spoiler-aware context
- Optional Vocablingo integration for saving words, phrases, and RAE definitions

## Tech stack

- Flutter and Material 3
- Riverpod for application state
- GoRouter for navigation
- Supabase Auth, Postgres, and Storage
- epub.js rendered through `webview_flutter` and `webview_windows`
- `shared_preferences` for local reader settings
- `google_mlkit_translation` for on-device translation

## Requirements

- Flutter with a Dart SDK compatible with `^3.11.4`
- A Supabase project configured for the `rucio` schema
- Android Studio, Xcode, or Visual Studio with the appropriate Flutter desktop workload for the target platform
- Optional Anthropic and Vocablingo credentials for their respective integrations

## Configuration

Create a `.env` file in the project root. Use your own values and do not commit this file.

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-publishable-or-anon-key
VOCABLINGO_SUPABASE_URL=https://your-vocablingo-project.supabase.co
VOCABLINGO_SUPABASE_ANON_KEY=your-vocablingo-publishable-or-anon-key
CLAUDE_API_KEY=your-anthropic-api-key
```

The app reads these values at compile time with `String.fromEnvironment`. The repository's `.gitignore` excludes `.env`, and the included VS Code launch configuration already supplies `--dart-define-from-file=.env`.

## Supabase setup

The primary client targets the `rucio` schema. Configure that schema for Data API access and create these resources:

- `books`
- `reading_progress`
- `highlights`
- `notes`
- `claude_history`
- A private Storage bucket named `libros`

All tables should use row-level security so authenticated users can access only rows whose `user_id` matches `auth.uid()`. Storage policies should apply the same ownership rule to paths under each user's ID. The repository includes [`supabase_notes_setup.txt`](supabase_notes_setup.txt) for the notes table and its RLS policies; the remaining schema must already exist in the target Supabase project.

Vocablingo uses a separate Supabase project with `vocabulary` and `saved_phrases` tables. It is optional unless saving reader selections to Vocablingo is required.

## Run locally

Install packages:

```console
flutter pub get
```

Run on an available device:

```console
flutter run --dart-define-from-file=.env
```

When using VS Code, select the `rucio_flutter` launch configuration.

## Build

```console
flutter build apk --release --dart-define-from-file=.env
flutter build windows --release --dart-define-from-file=.env
```

Use the same `--dart-define-from-file=.env` option for other Flutter build targets.

## Quality checks

```console
flutter analyze
flutter test
```

## Project structure

```text
lib/
  config/      Supabase configuration and schema-scoped client
  models/      Books, progress, highlights, and notes
  providers/   Riverpod state and persistence logic
  router/      Application routes and auth redirects
  screens/     Login, library, reader, highlights, and notes
  services/    Cache, Claude, translation, and Vocablingo clients
  widgets/     Reader panels, book cards, and editors
assets/
  epubjs/      epub.js and JSZip runtime assets
  reader.html  WebView reader shell
```

## Security

- Never commit `.env`, service-role keys, private keys, or personal access tokens.
- Supabase publishable/anon keys are client-facing identifiers, but row-level security and Storage policies are still mandatory.
- `CLAUDE_API_KEY` is compiled into the client when supplied through `dart-define`. For a production release, call Anthropic through a trusted backend or edge function so the API key is not distributed inside the application binary.
- Review staged changes before every public push with `git diff --cached` and a secret scanner.

## License

No license file is currently included. All rights are reserved unless the repository owner states otherwise.
