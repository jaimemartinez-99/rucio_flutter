# AGENTS.md — Rucio Flutter Rebuild

> Feed this file to an AI coding agent. Work through phases sequentially.
> Each phase includes: context, what to build, specific files, verification steps.
> **Do not skip phases. Do not proceed until verification passes.**

---

## Global Rules

1. **Package**: Use `supabase_flutter` (not `supabase`). Use `go_router` for routing. Use `riverpod` for state. Use `webview_flutter` for EPUB rendering.
2. **Database schema**: Set to `rucio` on the Supabase client. Every query targets this schema.
3. **Auth**: Every DB operation must filter by `user_id = supabase.auth.currentUser!.id`. RLS backs this up server-side.
4. **No comments** in code unless explicitly asked.
5. **Verify each phase** before moving on. Run `flutter analyze` after each phase.
6. **Style**: Use Material 3. Use `const` constructors where possible. Follow Dart conventions.
7. **Colors**:
   ```
   #0f0e17   Primary background
   #1a1827   Card / secondary background
   #252336   Surface / tertiary background
   #f2a65a   Accent (warm amber) — buttons, highlights, progress
   #e8e4f0   Primary text
   #7c748e   Muted / secondary text
   #f87171   Error red
   #ff9e9e / #ff8f8f   Delete / destructive actions
   #10b981   Emerald green (Claude button)
   ```

---

## Environment Setup

Create a `.env` file at the project root. Flutter reads it at compile time via `--dart-define-from-file=.env`.
**Do not commit `.env` — add it to `.gitignore`.**

```
SUPABASE_URL=https://dmxkbaezodourxuspnyq.supabase.co
SUPABASE_ANON_KEY=<paste-anon-key-from-supabase-dashboard>
VOCABLINGO_SUPABASE_URL=https://ievnahbenydiwxoohewq.supabase.co
VOCABLINGO_SUPABASE_ANON_KEY=<paste-anon-key>
CLAUDE_API_KEY=<paste-claude-key>
```

All `flutter run` and `flutter build` commands must include the flag:

```
flutter run --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
flutter build windows --dart-define-from-file=.env
```

Also add it to `.vscode/launch.json` (create if missing):

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

Values are accessed in Dart via `String.fromEnvironment('KEY')` — no package needed.

---

## PHASE 1: Project Scaffold + Auth

**Context**: We are building Rucio, an EPUB reader with cloud sync via Supabase. This phase sets up the Flutter project, Supabase client, and email/password authentication.

### Tasks

1. Create Flutter project: `flutter create rucio_flutter`
2. Create `.env` file at project root with the keys listed in Environment Setup above
3. Add `.env` to `.gitignore`
4. Add dependencies to `pubspec.yaml`:
   ```yaml
   dependencies:
     supabase_flutter: ^2.8.4
     go_router: ^14.8.1
     flutter_riverpod: ^2.6.1
     shared_preferences: ^2.3.4
   ```
5. Create `lib/main.dart`:
   - Initialize Supabase with `Supabase.initialize(url, anonKey)`
   - Wrap app in `ProviderScope` (Riverpod)
   - MaterialApp.router with GoRouter
6. Create `lib/config/supabase_config.dart`:
   ```dart
   class SupabaseConfig {
     static const url = String.fromEnvironment('SUPABASE_URL');
     static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
   }
   ```
7. Create `lib/providers/auth_provider.dart`:
   - `AuthNotifier` extends `StateNotifier<AuthState>` where `AuthState` = `{User? user, bool isLoading}`
   - Methods: `signIn(email, password)`, `signUp(email, password)`, `signOut()`, `checkSession()`
   - On `signOut`: call `supabase.auth.signOut()`
   - On init: check existing session via `supabase.auth.currentSession`
   - Listen to `supabase.auth.onAuthStateChange` stream to react to auth changes
   - Export a `authProvider` StateNotifierProvider
8. Create `lib/router/app_router.dart`:
   - GoRouter with two routes:
     - `/login` → LoginScreen
     - `/` → LibraryScreen (placeholder for now, just show user email + logout button)
   - Redirect logic: if not authenticated → `/login`, if authenticated on `/login` → `/`
9. Create `lib/screens/login_screen.dart`:
   - Email TextField + Password TextField + "Sign In" button + "Sign Up" toggle
   - Show loading indicator during auth
   - Show error snackbar on failure
   - Use `authProvider` to call signIn/signUp
10. Create placeholder `lib/screens/library_screen.dart`:
   - Display "Welcome, {user.email}"
   - Logout button
   - Scaffold with AppBar

### Verification
```
flutter pub get
flutter analyze
flutter run --dart-define-from-file=.env  # Test: sign up, sign in, sign out
```

---

## PHASE 2: Library — Book Grid + Upload + Delete

**Context**: Books are stored in Supabase (`rucio.books` table) and files in Storage (`libros` bucket). Metadata (title, author, cover) is extracted from the EPUB at upload time.

### Tasks

1. Add dependencies:
   ```yaml
   file_picker: ^8.1.7
   path_provider: ^2.1.5
   dio: ^5.7.0
   cached_network_image: ^3.4.1
   ```
2. Create `lib/models/book.dart`:
   ```dart
   class Book {
     final String id;
     final String userId;
     final String title;
     final String? author;
     final String? coverUrl; // base64 data URL
     final String filePath;
     final int? fileSize;
     final DateTime createdAt;
     // fromJson, toJson, copyWith
   }
   ```
3. Create `lib/providers/books_provider.dart`:
   - `BooksNotifier` with:
     - `List<Book> books`, `bool isLoading`, `String searchQuery`
     - `fetchBooks()`: `supabase.from('books').select().eq('user_id', userId).order('created_at', ascending: false)`
     - `searchBooks(query)`: filter books list locally by title or author (case-insensitive contains)
     - `uploadEpub()`: pick file via FilePicker → extract metadata → upload to storage → insert DB row
     - `deleteBook(bookId)`: delete DB row (cascade deletes progress/highlights) → delete storage file
   - For EPUB metadata extraction: read the EPUB file bytes, parse title/author/cover from the EPUB ZIP structure (or use the `archive` package to read `META-INF/container.xml` + `content.opf`).
   - Cover: extract cover image bytes, convert to base64 data URL (`data:image/jpeg;base64,...`), store in `cover_url`.
   - Storage upload: `supabase.storage.from('libros').upload('$userId/$fileName', bytes)`
   - Storage signed URL: `supabase.storage.from('libros').createSignedUrl(path, 3600)`
4. Create `lib/widgets/book_card.dart`:
   - Card with cover image (from base64 or placeholder), title, author
   - Long press → show delete confirmation dialog
   - Show progress bar overlay (percentage from reading_progress — stub for now, value 0)
   - Tap → navigate to reader (placeholder route `/reader/:id` for now)
5. Rewrite `lib/screens/library_screen.dart`:
   - AppBar with title "Rucio", search icon that expands to search field
   - RefreshIndicator wrapping a GridView.builder (2 columns mobile, 3+ tablet/desktop)
   - FAB to upload EPUB
   - Empty state: "No books yet. Tap + to upload."
   - Loading state: CircularProgressIndicator
   - Search: TextField below AppBar, filters books client-side by title/author
6. Update `lib/router/app_router.dart`:
   - Add `/reader/:bookId` route (placeholder screen that shows book title)
   - Update redirect logic

### EPUB Metadata Extraction Detail
```dart
// Use the 'archive' or 'epubx' package. Fallback approach:
// 1. Unzip EPUB (it's a ZIP file)
// 2. Read META-INF/container.xml → get rootfile path (usually content.opf)
// 3. Parse OPF XML → dc:title, dc:creator, cover image reference
// 4. Extract cover image from EPUB, convert to base64
```

### Verification
```
flutter analyze
flutter run --dart-define-from-file=.env  # Upload an EPUB, see it in grid, search, delete
```

---

## PHASE 3: EPUB Reader

**Context**: The reader uses a WebView loading a local HTML file that embeds epub.js. Communication between Flutter and the WebView happens via JavaScript channels.

### Tasks

1. Add dependency: `webview_flutter: ^4.10.0`
2. Download epub.js from https://github.com/futurepress/epub.js/releases — place `epub.min.js` in `assets/epubjs/`
3. Create `assets/reader.html`:
   ```html
   <!DOCTYPE html>
   <html>
   <head>
     <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
     <style>
       * { margin: 0; padding: 0; box-sizing: border-box; }
       body { overflow: hidden; }
       #viewer { width: 100vw; height: 100vh; }
       .tap-left { position: fixed; left: 0; top: 0; width: 25%; height: 100%; z-index: 10; }
       .tap-center { position: fixed; left: 25%; top: 0; width: 50%; height: 100%; z-index: 10; }
       .tap-right { position: fixed; right: 0; top: 0; width: 25%; height: 100%; z-index: 10; }
       #rucio-styles { display: none; }
     </style>
   </head>
   <body>
     <div id="viewer"></div>
     <div class="tap-left" onclick="prevPage()"></div>
     <div class="tap-center" onclick="toggleUI()"></div>
     <div class="tap-right" onclick="nextPage()"></div>
     <script src="epub.min.js"></script>
     <script>
       let book, rendition;
       function initBook(epubUrl) {
         book = ePub(epubUrl);
         rendition = book.renderTo("viewer", { width: "100%", height: "100%", flow: "paginated" });
         rendition.display();
         rendition.on("relocated", function(loc) {
           var cfi = loc.start.cfi;
           var pct = book.locations.percentageFromCfi(cfi);
           Relocated.postMessage(JSON.stringify({ cfi: cfi, percentage: Math.round(pct * 10000) / 100 }));
         });
         book.ready.then(function() {
           Toc.postMessage(JSON.stringify(book.navigation.toc));
         });
         rendition.on("selected", function(cfiRange, contents) {
           Selection.postMessage(JSON.stringify({ cfiRange: cfiRange, text: contents.window.getSelection().toString() }));
         });
       }
       function prevPage() { rendition.prev(); }
       function nextPage() { rendition.next(); }
       function goToCfi(cfi) { rendition.display(cfi); }
       function setStyles(css) {
         var el = document.getElementById("rucio-styles");
         if (!el) { el = document.createElement("style"); el.id = "rucio-styles"; document.head.appendChild(el); }
         el.textContent = css;
       }
       function search(query) {
         // epub.js search — simplified
         return Promise.resolve([]);
       }
       function toggleUI() { ToggleUI.postMessage(""); }
     </script>
   </body>
   </html>
   ```
4. Register assets in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/reader.html
       - assets/epubjs/epub.min.js
   ```
5. Create `lib/screens/reader_screen.dart`:
   - Receives `bookId` from route parameter
   - Fetches book data + signed URL for the EPUB
   - Loads `reader.html` as asset, replaces `{{{EPUB_URL}}}` with the signed URL, sets as WebView content via `loadHtmlString()`
   - Sets up 3 JavaScript channels: `Relocated`, `Selection`, `Toc`, `ToggleUI`
   - `Relocated` handler: calls `saveProgress(cfi, percentage)` from progress provider
   - `Selection` handler: stores selected text + cfi for highlight/claude/vocablingo context menu
   - `Toc` handler: stores TOC data for the TOC drawer
   - AppBar with back button, book title, TOC button, settings button
   - Thin progress bar at bottom (percentage from relocated events)
   - Floating "save" button to force-save progress
6. Create `lib/widgets/toc_drawer.dart`:
   - Bottom sheet or drawer listing chapters from TOC
   - Tap chapter → `webViewController.runJavaScript('goToCfi("$cfi")')`
   - Highlight current chapter based on current CFI

### Verification
```
flutter analyze
flutter run --dart-define-from-file=.env  # Open a book, page through it, check TOC, verify progress bar
```

---

## PHASE 4: Reading Progress Sync

**Context**: Reading position saves to `rucio.reading_progress` via upsert. Uses 3-second debounce to avoid spamming the API. Flushes on exit.

### Tasks

1. Create `lib/models/reading_progress.dart`:
   ```dart
   class ReadingProgress {
     final String userId;
     final String bookId;
     final String? lastCfi;
     final double percentage;
     final DateTime updatedAt;
   }
   ```
2. Create `lib/providers/progress_provider.dart`:
   - `ProgressNotifier` with:
     - `String? lastCfi`, `double percentage`, `bool isLoading`
     - `fetchProgress(bookId)`: `supabase.from('reading_progress').select().eq('user_id', userId).eq('book_id', bookId).maybeSingle()`
     - `saveProgress(cfi, percentage)`: debounced (3s) upsert. Uses a Timer.
     - `flushProgress()`: cancel debounce timer, immediately upsert latest values
     - On `dispose`: flush progress
   - Debounce implementation:
     ```dart
     Timer? _debounce;
     String? _pendingCfi;
     double _pendingPct = 0;
     
     void saveProgress(String cfi, double pct) {
       _pendingCfi = cfi;
       _pendingPct = pct;
       _debounce?.cancel();
       _debounce = Timer(Duration(seconds: 3), () {
         _upsertProgress(_pendingCfi!, _pendingPct);
       });
     }
     
     Future<void> flushProgress() async {
       _debounce?.cancel();
       if (_pendingCfi != null) {
         await _upsertProgress(_pendingCfi!, _pendingPct);
       }
     }
     
     Future<void> _upsertProgress(String cfi, double pct) async {
       await supabase.from('reading_progress').upsert({
         'user_id': userId,
         'book_id': bookId,
         'last_cfi': cfi,
         'percentage': pct.clamp(0, 100),
         'updated_at': DateTime.now().toIso8601String(),
       }, onConflict: 'user_id,book_id');
     }
     ```
3. Integrate into `ReaderScreen`:
   - On init: `fetchProgress(bookId)` → if `lastCfi` exists, `webViewController.runJavaScript('goToCfi("$lastCfi")')`
   - On `Relocated` messages: call `saveProgress(cfi, percentage)`
   - On dispose: call `flushProgress()` then `webViewController.dispose()`
   - Manual save button: calls `flushProgress()`
4. Update `BookCard` to show real progress percentage:
   - When displaying books, fetch progress for each book (or do a joined query)
   - Show mini progress bar or percentage text on the card

### Verification
```
flutter run --dart-define-from-file=.env  # Read a few pages, close book, reopen → should resume at same position
```

---

## PHASE 5: Reading Settings

**Context**: User can adjust theme (4 presets), font size (12-30px), line height (1.2-2.5x), and margins (0-120px desktop, 8-48px mobile). Settings persist locally via shared_preferences. CSS is injected into the WebView.

### Tasks

1. Create `lib/providers/settings_provider.dart`:
   ```dart
   enum ReadingTheme { light, sepia, dark, night }
   
   class ReadingSettings {
     final ReadingTheme theme;
     final double fontSize;
     final double lineHeight;
     final double marginH;
   }
   
   class SettingsNotifier extends StateNotifier<ReadingSettings> {
     // Load from shared_preferences on init
     // update(key, value) → save to shared_preferences → emit new state
     // getThemeColors(theme) → {bg, text}
     // buildEpubCss() → returns CSS string to inject
   }
   ```
2. Theme color map:
   ```dart
   const themeColors = {
     ReadingTheme.light: { 'bg': '#ffffff', 'text': '#1a1a2e' },
     ReadingTheme.sepia: { 'bg': '#f5ead7', 'text': '#3d2b1f' },
     ReadingTheme.dark:  { 'bg': '#1e1e2e', 'text': '#cdd6f4' },
     ReadingTheme.night: { 'bg': '#0a0a0f', 'text': '#8899aa' },
   };
   ```
3. CSS injection method:
   ```dart
   String buildCss(ReadingSettings s) {
     final colors = themeColors[s.theme]!;
     return """
       html, body { background: ${colors['bg']} !important; color: ${colors['text']} !important; }
       body, p, div, span, li, blockquote { font-size: ${s.fontSize}px !important; line-height: ${s.lineHeight} !important; }
       body { padding: 10px ${s.marginH}px 20px !important; box-sizing: border-box !important; }
       img { max-width: 100% !important; }
       p { margin-bottom: 0.8em !important; }
     """;
   }
   ```
4. Create `lib/widgets/settings_panel.dart`:
   - Opens as bottom sheet (mobile) or side drawer (tablet/desktop)
   - Theme: 4 selectable chips/buttons with colored preview
   - Font size: Slider with value label (12-30)
   - Line height: Slider with value label (1.2-2.5)
   - Margins: Slider with value label (8-120, adaptive)
   - On change → update provider → inject CSS via `webViewController.runJavaScript('setStyles(`$css`)')`
   - Adaptive layout: detect screen width, use `showModalBottomSheet` for <600px, `Drawer` for >=600px
5. Integrate into `ReaderScreen`:
   - Settings button in AppBar opens the settings panel
   - On settings change, inject new CSS

### Verification
```
flutter run --dart-define-from-file=.env  # Open reader, change theme/font/margins, verify visual change
```

---

## PHASE 6: Highlights

**Context**: Users can highlight text in the reader. Highlights are saved to `rucio.highlights` with CFI range, text, color, and optional note. A separate screen shows all highlights across all books.

### Tasks

1. Create `lib/models/highlight.dart`:
   ```dart
   class Highlight {
     final String id;
     final String userId;
     final String bookId;
     final String cfiRange;
     final String text;
     final String color;
     final String? note;
     final DateTime createdAt;
     // fromJson, toJson
   }
   ```
2. Create `lib/providers/highlights_provider.dart`:
   - `HighlightsNotifier` with:
     - `List<Highlight> highlights`, `bool isLoading`, `String? bookId` (filter)
     - `fetchHighlights(bookId?)`: filter by bookId if provided, order by created_at DESC
     - `fetchHighlightsWithBooks()`: `supabase.from('highlights').select('*, books(id, title, author)').eq('user_id', userId).order('created_at', ascending: false)` — for global view
     - `addHighlight(cfiRange, text, color, note?)`: insert
     - `updateHighlight(highlightId, updates)`: update (for notes, color)
     - `deleteHighlight(highlightId)`: delete
3. Integrate into Reader:
   - Listen for `Selection` messages from WebView
   - On text selection → show context menu (bottom sheet or popup) with options:
     - "Highlight" → save with default color (yellow)
     - "Ask Claude" (placeholder for Phase 7)
     - "Save to Vocablingo" (placeholder for Phase 8)
   - Render existing highlights in the WebView: on book load, fetch highlights → inject JavaScript to render them:
     ```javascript
     function renderHighlights(highlights) {
       highlights.forEach(function(h) {
         rendition.annotations.add("highlight", h.cfiRange, {}, null, null, {
           "background-color": h.color, "opacity": "0.5"
         });
       });
     }
     ```
   - Show a small list of this book's highlights accessible from the reader toolbar
4. Create `lib/screens/highlights_screen.dart`:
   - Lists all highlights across all books
   - Each item shows: highlighted text, book title, author, date, note preview
   - Search bar filters by text or note content
   - Tap highlight → navigate to reader and jump to that CFI
   - Swipe to delete highlight
5. Add `/highlights` route to GoRouter

### Verification
```
flutter run --dart-define-from-file=.env  # Open book, select text, highlight it, view in highlights screen, delete
```

---

## PHASE 7: Claude AI (Optional)

**Context**: User selects text and asks Claude a question about it. Conversation stored in `rucio.claude_history`. Uses Anthropic API directly via HTTP.

### Tasks

1. Add dependency: `dio: ^5.7.0` (already added)
2. Create `lib/services/claude_service.dart`:
   ```dart
   class ClaudeService {
     final Dio _dio;
     static const _apiUrl = 'https://api.anthropic.com/v1/messages';
     static const _model = 'claude-sonnet-4-20250514';
     
     Future<String> ask(String question, String? selectedText) async {
       final response = await _dio.post(_apiUrl,
         options: Options(headers: {
           'x-api-key': apiKey,
           'anthropic-version': '2023-06-01',
         }),
         data: {
           'model': _model,
           'max_tokens': 1024,
           'messages': [
             {'role': 'user', 'content': selectedText != null ? 'Context: "$selectedText"\n\nQuestion: $question' : question}
           ],
         },
       );
       return response.data['content'][0]['text'];
     }
   }
   ```
3. Create `lib/providers/claude_provider.dart`:
   - `ClaudeNotifier` with:
     - `List<ClaudeMessage> messages` (local chat state)
     - `fetchHistory(bookId)`: load past conversations
     - `askQuestion(bookId, text, question)`: call Claude API → save to claude_history → add to local state
   - `ClaudeMessage` model: `{String question, String answer, String? selection, DateTime createdAt}`
4. Create `lib/widgets/claude_chat_sheet.dart`:
   - Bottom sheet / side panel in reader
   - Shows chat bubbles (user question + Claude answer)
   - TextField at bottom for new question
   - When opened with selected text: auto-fills context from selection
   - Markdown rendering for Claude's answers (add `flutter_markdown` package)
5. Add to selection context menu in reader: "Ask Claude" → opens chat sheet
6. Route for chat history: `/reader/:id/claude` showing past conversations

### Verification
```bash
flutter analyze
flutter run --dart-define-from-file=.env  # Select text, ask Claude, verify response and history save
```

---

## PHASE 8: Vocablingo (Optional)

**Context**: A second Supabase project stores vocabulary words (with RAE dictionary definitions) and saved phrases. Users must also authenticate to Vocablingo.

### Tasks

1. Create `lib/services/vocablingo_service.dart`:
   ```dart
   class VocablingoService {
     final SupabaseClient client;
     
     Future<void> signIn(String email, String password) async {
       await client.auth.signInWithPassword(email: email, password: password);
     }
     
     Future<void> signOut() async {
       await client.auth.signOut();
     }
     
     Future<Map<String, dynamic>> saveWord(String word) async {
       final definition = await _fetchRAEDefinition(word);
       await client.from('vocabulary').insert({
         'word': word,
         'definition': definition,
         'user_id': client.auth.currentUser!.id,
       });
       return {'type': 'word', 'text': word, 'definition': definition};
     }
     
     Future<Map<String, dynamic>> savePhrase(String phrase) async {
       await client.from('saved_phrases').insert({
         'phrase': phrase,
         'user_id': client.auth.currentUser!.id,
       });
       return {'type': 'phrase', 'text': phrase};
     }
     
     Future<String> _fetchRAEDefinition(String word) async {
       final url = 'https://rae-api.com/api/words/${Uri.encodeComponent(word.toLowerCase())}';
       final response = await Dio().get(url);
       final data = response.data['data'] ?? response.data;
       final meanings = data['meanings'] ?? [];
       final definitions = <String>[];
       for (final meaning in meanings) {
         for (final sense in (meaning['senses'] ?? [])) {
           final num = sense['meaning_number'] ?? '?';
           final text = (sense['description'] ?? sense['raw'] ?? sense['definition'] ?? '').toString().trim();
           if (text.isNotEmpty) definitions.add('$num. $text');
         }
       }
       return definitions.join('\n');
     }
   }
   ```
2. Update `auth_provider.dart`:
   - After successful main sign-in, also call `vocablingo.signIn(email, password)` silently
   - On sign-out: also call `vocablingo.signOut()`
3. Add to reader selection context menu:
   - "Save to Vocablingo" → if single word: fetch RAE definition, save word+definition. If phrase: save phrase.
   - Show success/error snackbar

### Verification
```
flutter run --dart-define-from-file=.env  # Select a word, save to Vocablingo, verify in Vocablingo Dashboard
```

---

## PHASE 9: Offline Support

**Context**: Cache EPUB files locally so books can be read without internet. Progress saves locally when offline, syncs when online.

### Tasks

1. Create `lib/services/cache_service.dart`:
   ```dart
   class CacheService {
     Future<String> get cacheDir async {
       final dir = await getApplicationDocumentsDirectory();
       final cacheDir = Directory('${dir.path}/rucio_epubs');
       if (!await cacheDir.exists()) await cacheDir.create();
       return cacheDir.path;
     }
     
     Future<String?> getCachedEpubPath(String bookId) async {
       final path = '${await cacheDir}/$bookId.epub';
       return File(path).existsSync() ? path : null;
     }
     
     Future<String> downloadAndCache(String bookId, String signedUrl) async {
       final path = '${await cacheDir}/$bookId.epub';
       await Dio().download(signedUrl, path);
       return path;
     }
     
     Future<void> clearCache() async {
       final dir = Directory(await cacheDir);
       if (await dir.exists()) await dir.delete(recursive: true);
     }
   }
   ```
2. Update `ReaderScreen`:
   - On open: check `cacheService.getCachedEpubPath(bookId)`
   - If cached: load local file directly in WebView (using `file://` URI)
   - If not: download from signed URL, cache it, then load
   - Show download progress indicator
3. Update progress provider:
   - On save failure (network error): save progress locally as JSON
   - On app resume / next successful fetch: sync local progress to Supabase

### Verification
```
flutter run --dart-define-from-file=.env  # Open a book (downloads), enable airplane mode, reopen book (loads from cache)
```

---

## PHASE 10: Polish + Desktop

**Context**: Final polish, responsive layout, desktop-specific features.

### Tasks

1. Responsive layout:
   - Detect screen width: `LayoutBuilder` or `MediaQuery`
   - Library grid: 2 cols mobile (<600px), 3 cols tablet (600-900px), 4+ cols desktop (>900px)
   - Settings: bottom sheet on mobile, permanent side panel on wide screens
   - TOC: bottom sheet on mobile, drawer/side panel on wide
2. Desktop-specific:
   - Keyboard shortcuts: ArrowLeft/Right for page turn
   - Window title: set app title programmatically
   - File drop zone on library (drag EPUB onto window to upload)
3. Error handling:
   - Wrap all Supabase calls in try/catch, show user-friendly error messages
   - Network connectivity listener (use `connectivity_plus` package)
4. Loading states:
   - Shimmer/skeleton loading for book grid
   - Progress indicator for uploads
   - Loading overlay for reader initialization
5. Empty states:
   - "No books yet" illustration
   - "No highlights yet" illustration
6. App icon and splash screen:
   - `flutter_native_splash` for splash screen
   - `flutter_launcher_icons` for app icon
7. Run `flutter analyze` and fix all warnings
8. Test on Android emulator and desktop

### Verification
```
flutter analyze
flutter run --dart-define-from-file=.env  # Test on all target platforms
flutter build apk --release --dart-define-from-file=.env
flutter build windows --release --dart-define-from-file=.env
```
