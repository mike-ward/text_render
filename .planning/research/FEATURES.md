# Features Research: CJK IME

**Domain:** CJK (Chinese, Japanese, Korean) input method editor support
**Researched:** 2026-02-03
**Project:** VGlyph v1.4
**Confidence:** MEDIUM-HIGH (verified via official docs, Mozilla IME guide, Microsoft Learn)

## Summary

"Basic CJK IME" means: user types phonetic input (romaji, pinyin, jamo), sees preedit text with
underline, presses Space to see candidates, selects candidate, commits with Enter. The system must
handle three fundamentally different composition models:

1. **Japanese:** Multi-stage conversion (romaji -> hiragana -> kanji), clause segmentation, Space
   cycles candidates
2. **Chinese:** Phonetic input (pinyin or zhuyin), direct candidate selection, number keys for
   quick selection
3. **Korean:** Real-time syllable composition (jamo -> syllable block), no candidate window for
   basic input

All three share: marked/preedit text display, cursor inside composition, candidate window
positioning via `firstRectForCharacterRange:actualRange:`. VGlyph already has CompositionState with
clause support - v1.4 extends this for CJK-specific behaviors.

## Japanese IME

### Basic Flow

1. User types romaji: "nihongo" appears as "にほんご" (hiragana preedit, underlined)
2. Space key: triggers conversion, shows candidates like "日本語", "二本後"
3. Arrow keys or Space: cycle through candidates
4. Enter: commits selected candidate
5. Multi-clause: long input splits into segments (bunsetsu), arrow keys navigate between clauses

### Table Stakes (Must Have)

| Feature | Description | NSTextInputClient Method | Notes |
|---------|-------------|--------------------------|-------|
| **Hiragana preedit display** | Show romaji->hiragana conversion in underlined text | `setMarkedText:selectedRange:replacementRange:` | Underline indicates uncommitted |
| **Clause segmentation** | Split preedit into bunsetsu segments | Clause info in marked text attributes | Selected clause gets thick underline |
| **Space for conversion** | Space key triggers kanji candidates | Handled by IME, app shows candidates | No app-side logic needed |
| **Candidate selection** | Arrow/Space cycles candidates, numbers quick-select | IME handles, app updates marked text | App just displays |
| **Enter to commit** | Finalize composition | `insertText:replacementRange:` | Marked text removed, final text inserted |
| **Escape to cancel** | Discard preedit | `unmarkText` | Return to pre-composition state |
| **Clause navigation** | Arrow keys move between clauses | Selection within marked text | Per-clause conversion possible |

### Advanced (Defer to Post-v1.4)

| Feature | Description | Why Defer |
|---------|-------------|-----------|
| **Reconversion (再変換)** | Select committed text, convert again | Requires `selectedRange` tracking, complex |
| **User dictionary** | Custom readings/conversions | Application layer concern |
| **Prediction/auto-complete** | Predict next word | System IME feature, not app responsibility |
| **F-key conversions** | F6=hiragana, F7=katakana, etc. | System IME handles, app just receives |
| **Kana-direct input** | Type on kana keyboard layout | No romaji stage, but same composition flow |

### Japanese-Specific Behaviors

- **Clause underline styles:** Raw (thin), converted (thin), selected (thick)
- **Cursor in preedit:** User can position cursor within composition for partial editing
- **Space key semantics:** First press converts, subsequent presses cycle candidates
- **Long text:** IME auto-segments into clauses based on grammar

## Chinese IME

### Basic Flow (Pinyin)

1. User types pinyin: "nihao" appears as preedit (may show as pinyin or partial candidates)
2. Candidate window shows: "你好", "你号", "泥号", etc.
3. Number keys 1-9 select candidate directly, or Space selects first
4. Continue typing for phrase input

### Basic Flow (Zhuyin/Bopomofo - Taiwan)

1. User types zhuyin symbols: ㄋㄧˇㄏㄠˇ
2. Candidate window shows character options
3. Same selection mechanism as Pinyin

### Table Stakes (Must Have)

| Feature | Description | NSTextInputClient Method | Notes |
|---------|-------------|--------------------------|-------|
| **Pinyin preedit** | Show typed pinyin with underline | `setMarkedText:selectedRange:replacementRange:` | May show partial candidates |
| **Candidate window positioning** | Window appears near cursor | `firstRectForCharacterRange:actualRange:` | Return rect of preedit start |
| **Number key selection** | 1-9 keys select candidate | IME handles, commits via `insertText:` | No app logic needed |
| **Space for first candidate** | Quick commit most likely | IME handles | Same as Japanese |
| **Multi-character phrases** | Type "beijing" -> "北京" | IME handles phrase lookup | App just displays |
| **Tone input** | Numbers 1-4 for tones in some modes | IME handles | Transparent to app |

### Advanced (Defer to Post-v1.4)

| Feature | Description | Why Defer |
|---------|-------------|-----------|
| **Fuzzy pinyin** | Accept dialect variations | System IME setting |
| **Double pinyin** | Shortcut vowel groups | System IME setting |
| **Cloud predictions** | Bing-powered suggestions | System IME feature |
| **Simplified <-> Traditional** | Convert between scripts | Application layer |

### Chinese-Specific Behaviors

- **No clause segmentation:** Unlike Japanese, Chinese typically shows single underline
- **Continuous input:** Can type full sentences, IME segments automatically
- **Nested composition:** Traditional Chinese Zhuyin may use nested inline buffers
- **Candidate ordering:** Frequency-based, learns from usage

## Korean IME

### Basic Flow

1. User types jamo: ㄴ -> 나 -> 난 (real-time syllable composition)
2. Syllable block forms as jamo are typed (no explicit conversion step)
3. Space/Enter commits current syllable, starts next
4. For hanja (Chinese characters): additional conversion step similar to Japanese

### Table Stakes (Must Have)

| Feature | Description | NSTextInputClient Method | Notes |
|---------|-------------|--------------------------|-------|
| **Real-time jamo composition** | ㄱ+ㅏ -> 가 visually as typed | `setMarkedText:selectedRange:replacementRange:` | Syllable forms in real-time |
| **Syllable block display** | Show composing syllable with underline | Same as above | Single character preedit |
| **Jamo decomposition on backspace** | 간 -> 가 -> ㄱ -> (empty) | IME handles via marked text updates | Decompose before delete |
| **Space/punctuation commits** | Non-jamo input commits syllable | `insertText:` after commit | Standard behavior |
| **2-set (Dubeolsik) layout** | Consonants left, vowels right | IME handles | Default Korean layout |

### Advanced (Defer to Post-v1.4)

| Feature | Description | Why Defer |
|---------|-------------|-----------|
| **Hanja conversion** | Convert hangul to Chinese characters | Similar to Japanese kanji conversion |
| **Old Hangul (archaic jamo)** | Historical characters | Specialized use case |
| **3-set (Sebeolsik) layout** | Separate initial/final consonants | IME setting |
| **Romanized input** | Type "annyeong" -> 안녕 | Alternative input method |

### Korean-Specific Behaviors

- **No candidate window for basic hangul:** Syllable composition is deterministic
- **Backspace decomposition:** Unlike other scripts, backspace removes last jamo, not whole syllable
- **Continuous composition:** Each syllable auto-commits when next jamo makes it invalid
- **Short preedit:** Typically single syllable underlined at a time

## Common Features Across CJK

### Marked Text (Preedit)

All CJK input uses marked text to show uncommitted composition:

| Aspect | Japanese | Chinese | Korean |
|--------|----------|---------|--------|
| Underline style | Per-clause (raw/converted/selected) | Single underline | Single underline |
| Length | Often multiple characters/clauses | Variable, can be long phrase | Usually 1 syllable |
| Cursor inside | Yes, user can navigate | Yes, for editing pinyin | Yes, but rarely needed |

### Candidate Window

| Aspect | Japanese | Chinese | Korean |
|--------|----------|---------|--------|
| When shown | After Space press | During/after typing | Only for Hanja |
| Selection | Space/arrows/numbers | Numbers primary | Numbers if shown |
| Position | Via `firstRectForCharacterRange:` | Same | Same |

### Commit/Cancel

| Action | Japanese | Chinese | Korean |
|--------|----------|---------|--------|
| Commit | Enter | Enter or number key | Space/punctuation/next-incompatible-jamo |
| Cancel | Escape | Escape | Escape |
| Partial commit | Per-clause possible | Per-character possible | N/A (single syllable) |

## NSTextInputClient Protocol Mapping

### Required Methods for CJK

| Protocol Method | CJK Feature | Priority | Notes |
|-----------------|-------------|----------|-------|
| `setMarkedText:selectedRange:replacementRange:` | Preedit display | **P0** | Core composition |
| `markedRange` | Query preedit range | **P0** | IME needs this |
| `selectedRange` | Cursor position | **P0** | Within preedit |
| `hasMarkedText` | Check if composing | **P0** | State query |
| `unmarkText` | Cancel/commit composition | **P0** | Cleanup |
| `insertText:replacementRange:` | Commit final text | **P0** | After selection |
| `firstRectForCharacterRange:actualRange:` | Candidate window position | **P0** | Critical for UX |
| `attributedSubstringForProposedRange:actualRange:` | Context for IME | **P1** | Reconversion |
| `characterIndexForPoint:` | Click in candidate window | **P2** | Mouse selection |
| `validAttributesForMarkedText` | Supported underline styles | **P1** | Clause styling |
| `doCommandBySelector:` | Key commands during composition | **P1** | Arrow keys, etc. |

### Marked Text Attributes

The IME sends attributes with marked text to indicate clause types:

```
NSMarkedClauseSegmentAttributeName -> clause index (integer)
NSUnderlineStyleAttributeName -> underline style
  - NSUnderlineStyleSingle (0x01): raw/unconverted
  - NSUnderlineStyleThick (0x02): selected clause
```

VGlyph's existing `ClauseStyle` enum maps to these:
- `.raw` -> thin underline
- `.converted` -> thin underline
- `.selected` -> thick underline

### Coordinate System

`firstRectForCharacterRange:actualRange:` must return:
- Screen coordinates (not view coordinates)
- Rect covering the character range
- Actual range if requested range extends beyond text

Calculation: view coords -> window coords -> screen coords

## VGlyph v1.4 Scope

### Table Stakes (Include in v1.4)

**Already implemented (v1.3):**
- CompositionState with phase tracking
- Clause segmentation support
- Preedit text display
- Basic dead key composition

**New for v1.4:**
- Japanese clause navigation (arrow keys in preedit)
- Proper underline thickness per clause style
- `firstRectForCharacterRange:` returns correct screen coordinates
- Korean jamo backspace decomposition support
- Chinese continuous composition
- Candidate window positioning accuracy

### Differentiators (Nice to Have)

| Feature | Value | Complexity |
|---------|-------|------------|
| Inline candidate preview | Show top candidate in preedit | Medium |
| Custom underline colors | Match app theme | Low |
| Vertical text candidate positioning | CJK vertical writing | High |

### Anti-Features (Explicitly Skip)

| Feature | Why Skip |
|---------|----------|
| **Custom IME implementation** | Use system IME, don't reinvent |
| **Dictionary management** | System IME handles |
| **Prediction/autocomplete** | System IME feature |
| **IME switching UI** | System handles (Cmd+Space) |
| **Handwriting recognition** | Separate system feature |
| **Voice input** | Separate dictation system |

## Implementation Considerations

### Coordinate Conversion for Candidate Window

```
1. Get character rect in layout coordinates
2. Convert to view coordinates (apply view transform)
3. Convert to window coordinates: convertRect:toView:nil
4. Convert to screen coordinates: window.convertToScreen()
```

The IME positions its candidate window based on returned rect. Wrong coordinates = candidate window
in wrong place = major UX problem.

### Handling Clause Attributes

When `setMarkedText:` receives NSAttributedString:
1. Extract `NSMarkedClauseSegmentAttributeName` for clause boundaries
2. Extract `NSUnderlineStyleAttributeName` for each clause
3. Map to VGlyph's Clause struct with ClauseStyle

### Backspace Behavior

- **Japanese/Chinese:** Backspace deletes last character of preedit, or if preedit empty, previous
  committed character
- **Korean:** Backspace decomposes syllable (간 -> 가 -> ㄱ), IME handles this via marked text
  updates

### Focus Loss During Composition

Per existing CONTEXT.md decisions:
- Auto-commit preedit on focus loss
- Don't lose user's typed text
- Same behavior across CJK

## Validation Strategy

| Language | Test Case | Expected Behavior |
|----------|-----------|-------------------|
| Japanese | Type "nihongo", Space, Enter | にほんご -> 日本語 committed |
| Japanese | Type "toukyou", Space x2 | Cycle: 東京 -> 等距 -> ... |
| Japanese | Type long sentence, arrow between clauses | Per-clause conversion |
| Chinese | Type "nihao", press 1 | 你好 committed |
| Chinese | Type "beijing" | 北京 (if in dictionary) or candidates |
| Korean | Type ㄴ+ㅏ+ㄴ | 난 appears in preedit |
| Korean | Backspace on 난 | 나 (decomposed) |
| All | Escape during composition | Preedit discarded |
| All | Click outside during composition | Preedit committed, cursor moves |

**Manual testing required** with native speakers for each language.

## Confidence Assessment

| Topic | Confidence | Reason |
|-------|------------|--------|
| Japanese basic flow | HIGH | Well-documented, multiple sources agree |
| Chinese pinyin flow | HIGH | Microsoft Learn, Apple docs |
| Korean jamo composition | MEDIUM | Less documentation, behavior inferred |
| NSTextInputClient methods | HIGH | Apple docs, verified implementations |
| Clause styling attributes | MEDIUM | Inferred from Mozilla IME guide |
| Candidate window positioning | HIGH | Multiple implementations documented |

## Sources

**NSTextInputClient Protocol:**
- [Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [NSTextInputClient Protocol Reference (Leopard)](https://leopard-adc.pepas.com/documentation/Cocoa/Reference/NSTextInputClient_Protocol/Reference/Reference.html)
- [jessegrosjean/NSTextInputClient - Reference Implementation](https://github.com/jessegrosjean/NSTextInputClient)
- [Mozilla IME Handling Guide](https://firefox-source-docs.mozilla.org/editor/IMEHandlingGuide.html)
- [firstRectForCharacterRange implementation](https://gist.github.com/ishikawa/23431)

**Japanese IME:**
- [Microsoft Japanese IME](https://support.microsoft.com/en-us/windows/microsoft-japanese-ime-da40471d-6b91-4042-ae8b-713a96476916)
- [Japanese IME - Microsoft Learn](https://learn.microsoft.com/en-us/globalization/input/japanese-ime)
- [Japanese input method - Wikipedia](https://en.wikipedia.org/wiki/Japanese_input_method)
- [12 Tips to use your Japanese IME better](https://nihonshock.com/2010/04/12-japanese-ime-tips/)

**Chinese IME:**
- [Microsoft Simplified Chinese IME](https://support.microsoft.com/en-us/windows/microsoft-simplified-chinese-ime-9b962a3b-2fa4-4f37-811c-b1886320dd72)
- [Microsoft Traditional Chinese IME](https://support.microsoft.com/en-us/windows/microsoft-traditional-chinese-ime-ef596ca5-aff7-4272-b34b-0ac7c2631a38)
- [Pinyin input method - Wikipedia](https://en.wikipedia.org/wiki/Pinyin_input_method)
- [Zhuyin vs Pinyin - Chineasy](https://www.chineasy.com/zhuyin-vs-pinyin-exploring-the-unique-chinese-phonetic-system-of-bopomofo/)

**Korean IME:**
- [Korean IME - Microsoft Learn](https://learn.microsoft.com/en-us/globalization/input/korean-ime)
- [Hangul - Wikipedia](https://en.wikipedia.org/wiki/Hangul)
- [hangul-jamo library](https://github.com/jonghwanhyeon/hangul-jamo)

**IME Composition Visual Styling:**
- [React Native Paper IME underline issue](https://github.com/callstack/react-native-paper/issues/4779)
- [Mozilla Bug 875674 - NSTextInputClient implementation](https://bugzilla.mozilla.org/show_bug.cgi?id=875674)

---

*Research complete. Features categorized for v1.4 CJK IME milestone.*
