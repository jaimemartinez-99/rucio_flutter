# Rucio — Flutter Rebuild Plan

> **Target**: Rebuild the Rucio EPUB reader as a single Flutter app (Android + Desktop) using the same Supabase backend.

---

## 1. Tech Stack (Flutter Equivalent)

| Layer | Original | Flutter Replacement |
|---|---|---|
| **Framework** | React 18 / React Native 0.81 + Expo SDK 54 | Flutter 3.x (Dart) |
| **Routing** | React Router (HashRouter) / Expo Router | `go_router` |
| **State Management** | React Context (AuthContext, SettingsContext) | `riverpod` or `flutter_bloc` |
| **Styling** | Tailwind CSS / NativeWind | Standard Flutter widgets (Material 3) |
| **EPUB Rendering** | epub.js / @epubjs-react-native/core | `flutter_epub_viewer` or WebView + epub.js injected |
| **Backend / Auth / DB / Storage** | Supabase (`@supabase/supabase-js`) | `supabase_flutter` |
| **Local Storage** | AsyncStorage / localStorage | `shared_preferences` |
| **File Picker (Upload)** | Electron dialog / expo-document-picker | `file_picker` |
| **File System (Cache)** | expo-file-system | `path_provider` + `dio` (download) |
| **Desktop Shell** | Electron | Flutter native desktop (Windows, macOS, Linux) |
| **HTTP Client** | `fetch()` | `http` or `dio` |
| **WebView** | react-native-webview | `webview_flutter` |
| **Database** | Supabase PostgreSQL (schema: `rucio`) | Same Supabase backend — NO changes needed |
| **Storage** | Supabase Storage (bucket: `libros`) | Same Supabase backend — NO changes needed |

---

## 2. Supabase Connection

The Flutter app connects to the **same** Supabase project. No backend changes required.

### Environment Variables (`.env` file)

Values are loaded at compile time via `--dart-define-from-file=.env` and accessed via `String.fromEnvironment()`.

```
SUPABASE_URL=https://dmxkbaezodourxuspnyq.supabase.co
SUPABASE_ANON_KEY=eyJhbG... (anon key from Supabase dashboard)
VOCABLINGO_SUPABASE_URL=https://ievnahbenydiwxoohewq.supabase.co
VOCABLINGO_SUPABASE_ANON_KEY=eyJhbG...
CLAUDE_API_KEY=sk-ant-...
```

### Config File (`lib/config/supabase_config.dart`)
```dart
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const vocablingoUrl = String.fromEnvironment('VOCABLINGO_SUPABASE_URL');
  static const vocablingoAnonKey = String.fromEnvironment('VOCABLINGO_SUPABASE_ANON_KEY');
  static const claudeApiKey = String.fromEnvironment('CLAUDE_API_KEY');
}
```

### Supabase Client Initialization (Flutter)
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const RucioApp());
}
// Access client anywhere: Supabase.instance.client
// DB schema automatically set to 'rucio'
```

### Vocablingo Client (Separate Supabase Project)
```dart
final vocablingo = SupabaseClient(
  SupabaseConfig.vocablingoUrl,
  SupabaseConfig.vocablingoAnonKey,
);
```

---

## 3. Database Schema (Supabase — `rucio` schema)

### 3.1 Table: `rucio.books`
```sql
CREATE TABLE rucio.books (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  author        TEXT,
  cover_url     TEXT,          -- Base64 data URL of extracted cover
  file_path     TEXT NOT NULL, -- Path inside Supabase Storage: "{userId}/{fileName}"
  file_size     BIGINT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```
- RLS: Users can only SELECT/INSERT/UPDATE/DELETE their own rows (`auth.uid() = user_id`)

### 3.2 Table: `rucio.reading_progress`
```sql
CREATE TABLE rucio.reading_progress (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book_id     UUID NOT NULL REFERENCES rucio.books(id) ON DELETE CASCADE,
  last_cfi    TEXT,                  -- EpubCFI string (position)
  percentage  NUMERIC(5,2) DEFAULT 0, -- 0.00 – 100.00
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, book_id)         -- Enables upsert
);
```
- RLS: Users can SELECT/INSERT/UPDATE only their own rows
- Upsert target: `(user_id, book_id)` conflict

### 3.3 Table: `rucio.highlights`
```sql
CREATE TABLE rucio.highlights (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book_id     UUID NOT NULL REFERENCES rucio.books(id) ON DELETE CASCADE,
  cfi_range   TEXT NOT NULL,              -- EPUB CFI range
  text        TEXT NOT NULL,              -- Highlighted phrase
  color       TEXT NOT NULL DEFAULT 'yellow',
  note        TEXT,                       -- User annotation
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```
- RLS: Users can SELECT/INSERT/UPDATE/DELETE only their own rows
- Index: `(user_id, book_id, created_at DESC)`
- Partial index: WHERE `note IS NOT NULL AND note <> ''`

### 3.4 Table: `rucio.claude_history`
```sql
CREATE TABLE rucio.claude_history (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book_id       UUID NOT NULL REFERENCES rucio.books(id) ON DELETE CASCADE,
  question      TEXT NOT NULL,
  answer        TEXT NOT NULL,
  selection     TEXT,           -- Original selected text
  cfi_range     TEXT,           -- CFI of selection
  model         TEXT NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  metadata      JSONB,          -- Book metadata at time of question
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```
- RLS: Users can SELECT/INSERT/UPDATE/DELETE only their own rows
- Index: `(user_id, book_id, created_at DESC)`

### 3.5 Auto-Update Trigger
All 4 tables have a trigger that auto-updates `updated_at = NOW()` on UPDATE:
```sql
CREATE OR REPLACE FUNCTION rucio.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;
```

### 3.6 Storage Bucket: `libros`
- **Name**: `libros`
- **Access**: Private
- **Path convention**: `{userId}/{originalFileName.epub}`
- **RLS**: Users can only upload/read files where the first path segment matches their `auth.uid()`

### 3.7 Vocablingo Tables (Separate Supabase Project)
```
vocabulary (id, word, definition, user_id, created_at)
saved_phrases (id, phrase, user_id, created_at)
```

---

## 4. Full Feature List

### 4.1 Authentication
- **Email/Password Sign Up**
  - Form: email + password fields
  - Calls `supabase.auth.signUp(email, password)`
  - Auto-redirect to library on success
- **Email/Password Sign In**
  - Calls `supabase.auth.signInWithPassword(email, password)`
  - Auto-redirect to library on success
  - Simultaneously signs into Vocablingo with same credentials (silent)
- **Sign Out**
  - Calls `supabase.auth.signOut()`
  - Also signs out from Vocablingo
  - Redirects to login screen
- **Session Persistence**
  - `persistSession: true`, `autoRefreshToken: true`
  - On app start: restore session from local storage
  - Listen to `onAuthStateChange` for real-time session updates
- **Auth Guard**
  - Protected routes redirect to login if no session
  - Loading state while checking session

### 4.2 Library (Book Grid)
- **Grid View** of uploaded books
  - Card layout with cover image, title, author, file size
  - Responsive: adapts columns to screen width
  - Pull-to-refresh to reload
- **Search / Filter**
  - Text input that filters books by title or author (client-side)
- **Upload EPUB** (Desktop + Mobile)
  - Native file picker (file_picker package) to select `.epub` files
  - Extract metadata: title, author using epub parser
  - Extract cover image, convert to Base64 data URL
  - Upload file to Supabase Storage: `{userId}/{fileName}`
  - Insert book record into `rucio.books`
  - Show upload progress indicator
- **Delete Book**
  - Long-press or swipe-to-delete (mobile)
  - Right-click or button (desktop)
  - Confirmation dialog
  - Deletes from `rucio.books` (CASCADE deletes progress, highlights, claude_history)
  - Deletes file from Supabase Storage
- **Book Card Actions**
  - Tap to open reader
  - Show reading progress percentage as overlay/progress bar

### 4.3 EPUB Reader
- **EPUB Rendering Engine**
  - Use `webview_flutter` with epub.js library injected (recommended approach — same as original)
  - Alternative: `flutter_epub_viewer` package
  - Support for reflowable EPUBs
- **Page Navigation**
  - **Swipe/Tap**: Swipe left/right to turn pages (GestureDetector)
  - **Tap Zones**: Left 25% = previous page, right 25% = next page, center = toggle UI
  - **Keyboard**: Arrow Left/Right for page turning (desktop)
- **Table of Contents**
  - Button to open TOC drawer/bottom sheet
  - List of chapters/sections
  - Tap to navigate to section using CFI
  - Highlight current chapter
- **Search within Book**
  - Search field that searches full EPUB text
  - Navigate between search results
  - Highlight current match
- **Reading Progress Bar**
  - Thin bar at bottom of screen
  - Shows % progress through book
  - Updates on every page turn
- **Manual Save Button**
  - Force-save current position to Supabase immediately

### 4.4 Reading Settings
- **4 Themes**:
  | Theme | Background | Text Color |
  |---|---|---|
  | Claro (Light) | `#ffffff` | `#1a1a2e` |
  | Sepia | `#f5ead7` | `#3d2b1f` |
  | Oscuro (Dark) | `#1e1e2e` | `#cdd6f4` |
  | Noche (Night) | `#0a0a0f` | `#8899aa` |
- **Font Size Slider**: 12px – 30px
- **Line Height Slider**: 1.2x – 2.5x
- **Margins Slider**: 0 – 120px horizontal (desktop) / 8 – 48px (mobile)
- **Settings Persistence**: Saved to `shared_preferences`, restored on app restart
- **CSS Injection**: Styles injected as CSS into epub.js iframe/WebView
- **Adaptive UI**: Settings shown as a side panel (desktop/tablet) or bottom sheet (phone)

### 4.5 Reading Progress Sync (EpubCFI)
- **On Book Open**: Fetch `reading_progress` for `(userId, bookId)` to get `last_cfi` + `percentage`
- **On Page Turn**: epub.js fires `relocated` event with current CFI
- **Debounced Save**: Save to Supabase after **3 seconds** of inactivity (debounce)
  - Uses refs (not state) to avoid re-renders that reset the reader
- **Flush on Exit**: Immediately save latest position when:
  - User navigates away from reader
  - App goes to background / closes
  - User taps manual save button
- **Upsert**: Insert or update `reading_progress` using `(user_id, book_id)` conflict target

### 4.6 Highlights
- **Create Highlight**
  - Long-press or select text in reader
  - Context menu: "Highlight" option
  - Save to `rucio.highlights` with CFI range, selected text, color
- **Edit Highlight**
  - Tap existing highlight
  - Add/edit/delete note (annotation)
  - Change highlight color (yellow, green, blue, pink)
- **Delete Highlight**
  - Remove highlight from DB
- **In-Book Display**: Highlights rendered with colored background in the WebView
- **Highlight Navigation**: Tap a highlight in the list to jump to that location in the book
- **Global Highlights View** (separate screen):
  - Lists all highlights across all books
  - Searchable by highlighted text or note content
  - Shows book title + author for each highlight
  - Groupable by book
  - Tap to navigate to that book + position

### 4.7 Claude AI Integration (Optional)
- **Select Text + Ask Claude**
  - Select text in reader
  - Context menu: "Ask Claude"
  - Send selected text + user question to Anthropic API
  - Display answer in chat bubble
- **Claude History**
  - Chat history stored in `rucio.claude_history`
  - Grouped by book
  - Viewable in a history panel within reader
- **API**: `POST https://api.anthropic.com/v1/messages`
  - Model: `claude-sonnet-4-20250514`
  - API key from `CLAUDE_API_KEY` env var

### 4.8 Vocablingo Integration (Optional)
- **Save Selected Word/Phrase**
  - Select text in reader
  - Context menu: "Save to Vocablingo"
  - If single word: fetch definition from RAE API (`https://rae-api.com/api/words/{word}`), save word + definition to `vocabulary` table
  - If phrase (contains spaces): save directly to `saved_phrases` table
- **Auto-clean RAE Definitions**: Parse `data.meanings[].senses[]` array, extract `meaning_number` and `description`
- **Requires**: User is also signed into Vocablingo Supabase project

### 4.9 Offline Support
- **EPUB Caching**: Download EPUB to device cache (`path_provider`) on first open
- **Cache Check**: Before downloading, check if file exists locally
- **Progress Store-and-Forward**: Save progress locally when offline, sync when online
- **Book List Caching**: Cache book metadata locally for offline library browsing

### 4.10 Platform-Specific Adaptations
| Feature | Mobile | Desktop |
|---|---|---|
| Upload EPUB | File picker + mobile file system | Native file dialog |
| Page turn | Swipe + tap zones | Arrow keys + click zones + swipe |
| Settings panel | Bottom sheet | Side drawer/panel |
| Delete book | Long press → confirm modal | Button/right-click → confirm dialog |
| Window frame | Full screen | Custom title bar with drag region |
| Offline cache | Yes (path_provider) | Optional |

---

## 5. API Reference (Supabase Client — Dart/Flutter)

All database operations use `supabase.from("table")` (schema is set to `rucio` globally).

```
# Auth
supabase.auth.signUp(email: email, password: password)
supabase.auth.signInWithPassword(email: email, password: password)
supabase.auth.signOut()
supabase.auth.onAuthStateChange  // Stream<AuthState>
supabase.auth.currentUser
supabase.auth.currentSession

# Books
supabase.from("books").select("*").eq("user_id", userId).order("created_at", ascending: false)
supabase.from("books").insert(book).select().single()
supabase.from("books").delete().eq("id", bookId).eq("user_id", userId)

# Reading Progress
supabase.from("reading_progress").select("*").eq("user_id", userId).eq("book_id", bookId).maybeSingle()
supabase.from("reading_progress").upsert({ user_id, book_id, last_cfi, percentage, updated_at }, onConflict: "user_id,book_id")

# Highlights
supabase.from("highlights").select("*").eq("user_id", userId).order("created_at", ascending: false)
  .eq("book_id", bookId)  // optional filter by book
supabase.from("highlights").select("*, books(id, title, author)").eq("user_id", userId)  // with book join
supabase.from("highlights").insert({ user_id, book_id, cfi_range, text, color, note }).select().single()
supabase.from("highlights").update(updates).eq("id", highlightId).eq("user_id", userId).select().single()
supabase.from("highlights").delete().eq("id", highlightId).eq("user_id", userId)

# Claude History
supabase.from("claude_history").select("*").eq("user_id", userId).order("created_at", ascending: false)
  .eq("book_id", bookId)  // optional filter
supabase.from("claude_history").insert({ user_id, book_id, question, answer, selection, cfi_range, model, metadata }).select().single()

# Storage
supabase.storage.from("libros").upload("$userId/$fileName", fileBytes, UploadOptions(upsert: false))
supabase.storage.from("libros").createSignedUrl(filePath, 3600)  // 1-hour expiry
supabase.storage.from("libros").remove([filePath])
```

---

## 6. External APIs

### 6.1 Anthropic Claude
```
POST https://api.anthropic.com/v1/messages
Headers:
  x-api-key: $CLAUDE_API_KEY
  anthropic-version: 2023-06-01
  content-type: application/json
Body:
  {
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "messages": [
      { "role": "user", "content": "Question about: <selected_text>" }
    ]
  }
```

### 6.2 RAE Dictionary (Spanish)
```
GET https://rae-api.com/api/words/{word}
Response: { "data": { "meanings": [{ "senses": [{ "meaning_number": 1, "description": "..." }] }] } }
```
Parse: for each meaning → for each sense → extract `meaning_number` + `description`

---

## 7. Key Flutter Packages

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Supabase
  supabase_flutter: ^2.x
  
  # Routing
  go_router: ^14.x
  
  # State Management (choose one)
  flutter_riverpod: ^2.x
  # or flutter_bloc: ^8.x
  
  # EPUB Reader
  webview_flutter: ^4.x
  
  # File handling
  file_picker: ^8.x
  path_provider: ^2.x
  
  # HTTP (for Claude API, RAE API)
  dio: ^5.x  # or http: ^1.x
  
  # Local storage
  shared_preferences: ^2.x
  
  # UI
  flutter_slidable: ^3.x  # Swipe actions on list items
  cached_network_image: ^3.x  # Cover images
  
  # EPUB metadata extraction (choose one)
  epub_view: ^3.x  # Includes parsing + reading
  # OR: epub_parser: ^1.x for metadata only
```

---

## 8. App Structure (Recommended File Tree)

```
lib/
├── main.dart                         # App entry: Supabase.initialize() + runApp
├── app.dart                          # MaterialApp.router with GoRouter
│
├── config/
│   ├── supabase_config.dart          # Supabase URL, anon key, vocablingo config
│   ├── theme.dart                    # App theme (Material 3), reading themes constant
│   └── constants.dart                # Debounce time, default settings, etc.
│
├── router/
│   └── app_router.dart               # GoRouter: login, library, reader/:id, highlights, settings
│
├── models/
│   ├── book.dart                     # Book model (from rucio.books)
│   ├── reading_progress.dart         # Progress model
│   ├── highlight.dart                # Highlight model
│   └── claude_history.dart           # ClaudeHistory model
│
├── providers/                        # Riverpod providers (or bloc/ for flutter_bloc)
│   ├── auth_provider.dart            # Auth state, signIn, signUp, signOut, vocablingo signIn
│   ├── books_provider.dart           # List books, search, upload, delete
│   ├── progress_provider.dart        # Fetch/upsert reading progress, debounce logic
│   ├── highlights_provider.dart      # CRUD highlights, filter by book
│   ├── claude_provider.dart          # Claude chat, history
│   └── settings_provider.dart        # Reading settings (fontSize, lineHeight, marginH, theme)
│
├── services/
│   ├── supabase_service.dart         # Supabase client singleton, all DB queries
│   ├── storage_service.dart          # Upload/download/delete from libros bucket
│   ├── claude_service.dart           # Anthropic API calls
│   ├── rae_service.dart              # RAE dictionary API calls + response parser
│   └── vocablingo_service.dart       # Vocablingo save (word with RAE def / phrase)
│
├── screens/
│   ├── login_screen.dart             # Email/password form, sign up toggle
│   ├── library_screen.dart           # Book grid, search bar, upload FAB, pull-to-refresh
│   ├── reader_screen.dart            # WebView + epub.js, settings, TOC, highlights
│   ├── highlights_screen.dart        # Global highlights list, search, tap to navigate
│   └── claude_history_screen.dart    # Chat history per book
│
├── widgets/
│   ├── book_card.dart                # Cover image, title, author, progress indicator
│   ├── upload_progress_dialog.dart   # Upload progress modal
│   ├── settings_panel.dart           # Font size, line height, margins, theme selector
│   ├── toc_drawer.dart               # Table of contents drawer/bottom sheet
│   ├── highlight_list.dart           # List of highlights with notes
│   ├── search_bar.dart               # Reusable search bar
│   ├── reading_progress_bar.dart     # Thin progress bar at screen bottom
│   └── auth_gate.dart                # Checks auth state, shows login or main
│
└── utils/
    ├── epub_cfi_helpers.dart         # EpubCFI utilities (if needed)
    └── debounce.dart                 # Debounce utility class
```

---

## 9. EPUB Rendering Strategy

### Approach: WebView + epub.js (Same as Original)

1. **Bundle epub.js** as a local asset (`assets/epubjs/`)
2. **Create an HTML template** that loads epub.js and accepts an EPUB URL
3. **Inject CSS** for reading themes via JavaScript evaluation
4. **Bridge communication** via `JavaScriptChannel`:
   - `onRelocated(cfi, percentage)` → trigger debounced save
   - `onSelectedText(text, cfi)` → show highlight/Claude/Vocablingo menu
   - `onSearchResults(results)` → display search results in Flutter UI
5. **Navigate**: `webViewController.runJavaScript('rendition.prev()/next()')`
6. **Display CFI**: `webViewController.runJavaScript('rendition.display("' + cfi + '")')`

### HTML Template (assets/reader.html)
```html
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <script src="epub.min.js"></script>
  <style>
    /* Custom scrollbar, tap zone overlays, etc. */
  </style>
</head>
<body>
  <div id="viewer"></div>
  <script src="reader_bridge.js"></script>
</body>
</html>
```

### Bridge JavaScript (assets/reader_bridge.js)
```javascript
// Initialize epub.js, set up relocated/selected events, call Flutter via channels:
// - RelocatedChannel.postMessage(JSON.stringify({cfi, percentage}))
// - SelectionChannel.postMessage(JSON.stringify({text, cfiRange}))
// - TocChannel.postMessage(JSON.stringify(toc))
```

---

## 10. Implementation Phases

### Phase 1: Supabase Setup & Auth
- Initialize Supabase client
- Login screen (email/password)
- Sign up screen
- Auth state management
- Auth guard / redirect
- Session persistence

### Phase 2: Library
- Book model
- Fetch books from Supabase
- Book grid UI with cover images
- File picker + upload to Storage
- Extract EPUB metadata (title, author, cover)
- Delete book (DB + Storage)
- Search/filter

### Phase 3: EPUB Reader
- Set up WebView with epub.js bundled
- Load EPUB from signed URL
- Page navigation (tap zones, swipe)
- Table of contents
- Reading progress bar
- Progress sync (debounced upsert to Supabase)
- Resume from last position (last_cfi)

### Phase 4: Reading Settings
- Theme selector (4 themes)
- Font size, line height, margin sliders
- CSS injection into WebView
- Persist settings locally

### Phase 5: Highlights
- Text selection in WebView
- Highlight context menu
- Save/load highlights from Supabase
- Display highlights in reader
- Global highlights list screen
- Notes on highlights

### Phase 6: Claude AI (Optional)
- Anthropic API integration
- Chat interface in reader
- Save conversation to claude_history
- View history per book

### Phase 7: Vocablingo (Optional)
- Second Supabase client
- Silent login with main credentials
- Save word + RAE definition to vocabulary
- Save phrase to saved_phrases

### Phase 8: Polish
- Offline caching of EPUBs
- Pull-to-refresh on library
- Responsive layout (mobile/tablet/desktop)
- Error handling & loading states
- App icon & splash screen

---

## 11. Migration SQL (Run in Supabase SQL Editor)

Execute all 4 migration files in order:
1. `supabase/migrations/001_initial_schema.sql` — schema, books, reading_progress, RLS
2. `supabase/migrations/002_highlights.sql` — highlights table + RLS
3. `supabase/migrations/003_claude_history.sql` — claude_history table + RLS
4. `supabase/migrations/004_highlight_notes.sql` — note column index for highlights

Then manually create the `libros` storage bucket (private) and apply storage RLS policies.

---

## 12. Environment Variables / Configuration

Create a `.env` file at the project root. Flutter reads it natively via `--dart-define-from-file=.env` (no package needed).

```
SUPABASE_URL=https://dmxkbaezodourxuspnyq.supabase.co
SUPABASE_ANON_KEY=eyJhbG...your-anon-key...
VOCABLINGO_SUPABASE_URL=https://ievnahbenydiwxoohewq.supabase.co
VOCABLINGO_SUPABASE_ANON_KEY=eyJhbG...your-anon-key...
CLAUDE_API_KEY=sk-ant-...your-api-key...
```

Add `.env` to `.gitignore` — never commit secrets.

All `flutter run` and `flutter build` commands must include:

```bash
flutter run --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
```

VS Code `launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "rucio_flutter",
      "request": "launch",
      "type": "dart",
      "args": ["--dart-define-from-file=.env"]
    }
  ]
}
```

Values are accessed via `String.fromEnvironment('KEY')` — no extra package required.

---

## 13. Key Architecture Decisions to Replicate

1. **Debounced Sync**: 3-second debounce with refs (not state) to prevent reader re-initialization on every progress save
2. **Upsert Pattern**: Reading progress uses `UNIQUE(user_id, book_id)` + upsert — one row per user per book
3. **Cover Images**: Stored as Base64 data URLs in `cover_url` column (extracted at upload time)
4. **RLS Security**: Every DB operation includes `user_id` filter, enforced by both client-side `eq("user_id", userId)` and server-side RLS policies
5. **Signed URLs**: EPUB files never exposed as public URLs — always use `createSignedUrl()` with expiry
6. **Two Supabase Projects**: Main app (rucio schema) + Vocablingo (separate project for vocabulary)
7. **CSS Injection**: Reading themes injected as `<style>` into epub.js iframe, overriding default EPUB CSS
8. **No WebSockets**: All communication is request/response (HTTP)
9. **EpubCFI**: Canonical Fragment Identifiers for precise, cross-device position tracking
10. **Local Settings**: Reading preferences stored locally (shared_preferences), not in DB
