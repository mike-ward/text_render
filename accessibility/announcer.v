module accessibility

import time

// LineBoundary indicates cursor at line start/end
pub enum LineBoundary {
	beginning
	end
}

// DocBoundary indicates cursor at document start/end
pub enum DocBoundary {
	beginning
	end
}

// AccessibilityAnnouncer provides explicit VoiceOver announcements.
// Follows verbosity decisions from Phase 17 CONTEXT.md.
pub struct AccessibilityAnnouncer {
mut:
	last_announcement_time i64
	debounce_ms            i64 = 150 // Per screen reader research (150-200ms)
	last_line              int = -1  // Track line changes
}

pub fn new_accessibility_announcer() AccessibilityAnnouncer {
	return AccessibilityAnnouncer{}
}

// announce_character - character only, no phonetic spelling (per CONTEXT.md)
// Punctuation/whitespace: symbolic names
// Emoji: short name if available (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_character(ch rune) string {
	if !ann.should_announce() {
		return ''
	}
	message := match ch {
		` ` {
			'space'
		}
		`\t` {
			'tab'
		}
		`\n` {
			'newline'
		}
		`.` {
			'period'
		}
		`,` {
			'comma'
		}
		`;` {
			'semicolon'
		}
		`:` {
			'colon'
		}
		`!` {
			'exclamation'
		}
		`?` {
			'question'
		}
		`'` {
			'apostrophe'
		}
		`"` {
			'quote'
		}
		`(` {
			'open paren'
		}
		`)` {
			'close paren'
		}
		`[` {
			'open bracket'
		}
		`]` {
			'close bracket'
		}
		`{` {
			'open brace'
		}
		`}` {
			'close brace'
		}
		else {
			// Check for emoji short name (per CONTEXT.md: short name if available)
			emoji_name := get_emoji_name(ch)
			if emoji_name.len > 0 {
				emoji_name
			} else {
				ch.str() // Plain character
			}
		}
	}
	ann.log_announcement(message)
	return message
}

// announce_word_jump - brief context preview: 'moved to: word' (per CONTEXT.md)
// CONTEXT.md specifies: "Word jump / Home/End: brief context preview ('moved to: hello world')"
pub fn (mut ann AccessibilityAnnouncer) announce_word_jump(word string) string {
	if !ann.should_announce() {
		return ''
	}
	message := 'moved to: ${word}'
	ann.log_announcement(message)
	return message
}

// announce_line_boundary - 'beginning of line' / 'end of line' (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_line_boundary(boundary LineBoundary) string {
	if !ann.should_announce() {
		return ''
	}
	message := match boundary {
		.beginning { 'beginning of line' }
		.end { 'end of line' }
	}
	ann.log_announcement(message)
	return message
}

// announce_line_number - always announce on line change (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_line_number(line int) string {
	if line == ann.last_line {
		return '' // Same line, don't announce
	}
	ann.last_line = line
	if !ann.should_announce() {
		return ''
	}
	message := 'line ${line}'
	ann.log_announcement(message)
	return message
}

// announce_document_boundary - 'beginning of document' / 'end of document' (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_document_boundary(boundary DocBoundary) string {
	if !ann.should_announce() {
		return ''
	}
	message := match boundary {
		.beginning { 'beginning of document' }
		.end { 'end of document' }
	}
	ann.log_announcement(message)
	return message
}

// announce_selection - read short (<= 20 chars), count long (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_selection(selected_text string) string {
	if !ann.should_announce() {
		return ''
	}
	message := if selected_text.len <= 20 {
		selected_text // Read the actual text
	} else {
		char_count := selected_text.runes().len
		'${char_count} characters selected'
	}
	ann.log_announcement(message)
	return message
}

// announce_selection_extended - 'added: X' (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_selection_extended(added_text string) string {
	if !ann.should_announce() {
		return ''
	}
	message := 'added: ${added_text}'
	ann.log_announcement(message)
	return message
}

// announce_selection_cleared - 'deselected' (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_selection_cleared() string {
	if !ann.should_announce() {
		return ''
	}
	message := 'deselected'
	ann.log_announcement(message)
	return message
}

// announce_dead_key - announce dead key character (per CONTEXT.md)
// CONTEXT.md: "Dead key sequences: announce dead key ('grave accent'), then final result"
pub fn (mut ann AccessibilityAnnouncer) announce_dead_key(dead_key rune) string {
	if !ann.should_announce() {
		return ''
	}
	message := match dead_key {
		`\`` { 'grave accent' }
		`´` { 'acute accent' }
		`^` { 'circumflex' }
		`~` { 'tilde' }
		`¨` { 'umlaut' }
		`¸` { 'cedilla' }
		else { 'dead key' }
	}
	ann.log_announcement(message)
	return message
}

// announce_dead_key_result - announce the final composed character (per CONTEXT.md)
// CONTEXT.md: "Dead key sequences: announce dead key ('grave accent'), then final result"
// Called after composition commits to announce what was actually inserted
pub fn (mut ann AccessibilityAnnouncer) announce_dead_key_result(ch rune) string {
	// Don't debounce result - always announce after dead key
	message := ch.str()
	ann.log_announcement(message)
	return message
}

// announce_composition_cancelled - 'composition cancelled' (per CONTEXT.md)
pub fn (mut ann AccessibilityAnnouncer) announce_composition_cancelled() string {
	if !ann.should_announce() {
		return ''
	}
	message := 'composition cancelled'
	ann.log_announcement(message)
	return message
}

// should_announce checks debounce timing
fn (mut ann AccessibilityAnnouncer) should_announce() bool {
	now := time.now().unix_milli()
	if now - ann.last_announcement_time < ann.debounce_ms {
		return false // Too soon
	}
	ann.last_announcement_time = now
	return true
}

// log_announcement outputs to stderr and posts to VoiceOver
fn (ann AccessibilityAnnouncer) log_announcement(message string) {
	eprintln('[VoiceOver] ${message}')
	// Post to VoiceOver via NSAccessibility
	$if darwin {
		announce_to_voiceover(message)
	}
}
