# SVG textPath Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task.

**Goal:** Parse SVG `<textPath>` elements and render text along
arbitrary curves using vglyph's `draw_layout_placed()`.

**Architecture:** New `SvgTextPath` struct parsed from SVG, arc-length
parameterized path sampling in `svg_textpath.v`, new
`DrawLayoutPlaced` renderer variant. All code in gui; no vglyph
changes.

**Tech Stack:** V, gui SVG parser, vglyph `TextSystem`/`Layout`/
`GlyphPlacement`

**Design doc:** `docs/plans/2026-02-15-svg-textpath-design.md`

---

### Task 1: Add `SvgTextPath` struct and data plumbing

**Files:**
- Modify: `/Users/mike/.vmodules/gui/svg_vector.v:84-134`
- Modify: `/Users/mike/.vmodules/gui/svg.v:18-22`
- Modify: `/Users/mike/.vmodules/gui/svg_load.v:7-26`

**Step 1: Add `SvgTextPath` struct to `svg_vector.v`**

After `SvgText` (line 84), add:

```v ignore
// SvgTextPath holds a parsed <textPath> for text-on-curve.
pub struct SvgTextPath {
pub:
	text             string
	path_id          string
	start_offset     f32
	is_percent       bool
	anchor           u8
	spacing          u8
	method           u8
	side             u8
	font_family      string
	font_size        f32
	bold             bool
	italic           bool
	color            Color
	opacity          f32 = 1.0
	filter_id        string
	fill_gradient_id string
	letter_spacing   f32
	stroke_color     Color = color_transparent
	stroke_width     f32
}
```

**Step 2: Add `text_paths` to `SvgFilteredGroup`**

In `SvgFilteredGroup` (line 96-101), add after `texts`:

```v ignore
	text_paths []SvgTextPath
```

**Step 3: Add `defs_paths` and `text_paths` to `VectorGraphic`**

In `VectorGraphic` (line 122-134), add after `texts`:

```v ignore
	text_paths  []SvgTextPath
	defs_paths  map[string]string // id -> raw d attribute
```

**Step 4: Add `text_paths` to `ParseState`**

In `ParseState` (svg.v:18-22), add:

```v ignore
	text_paths []SvgTextPath
```

**Step 5: Add fields to `CachedFilteredGroup` and `CachedSvg`**

In `CachedFilteredGroup` (svg_load.v:7-14), add:

```v ignore
	text_paths []SvgTextPath
```

In `CachedSvg` (svg_load.v:17-26), add:

```v ignore
	text_paths []SvgTextPath
	defs_paths map[string]string
```

**Step 6: Run `v fmt -w` on modified files**

```
v fmt -w /Users/mike/.vmodules/gui/svg_vector.v
v fmt -w /Users/mike/.vmodules/gui/svg.v
v fmt -w /Users/mike/.vmodules/gui/svg_load.v
```

**Step 7: Verify compilation**

```
v -check-syntax /Users/mike/.vmodules/gui/svg_vector.v
v -check-syntax /Users/mike/.vmodules/gui/svg.v
v -check-syntax /Users/mike/.vmodules/gui/svg_load.v
```

**Step 8: Run existing SVG tests to verify no regression**

```
v test /Users/mike/.vmodules/gui/_svg_test.v
```

Expected: all pass.

**Step 9: Commit**

```
git add svg_vector.v svg.v svg_load.v
git commit -m "add SvgTextPath struct and data plumbing"
```

---

### Task 2: Parse `<path>` defs and `<textPath>` elements

**Files:**
- Modify: `/Users/mike/.vmodules/gui/svg.v:88-132, 306-407`
- Test: `/Users/mike/.vmodules/gui/_svg_textpath_test.v` (new)

**Step 1: Write failing tests for defs path extraction**

Create `/Users/mike/.vmodules/gui/_svg_textpath_test.v`:

```v ignore
module gui

fn test_parse_defs_paths_basic() {
	content := '<svg><defs>
		<path id="curve1" d="M0 0 L100 0"/>
		<path id="curve2" d="M10 20 Q50 0 90 20"/>
	</defs></svg>'
	paths := parse_defs_paths(content)
	assert paths.len == 2
	assert paths['curve1'] == 'M0 0 L100 0'
	assert paths['curve2'] == 'M10 20 Q50 0 90 20'
}

fn test_parse_defs_paths_no_id() {
	content := '<svg><defs>
		<path d="M0 0 L100 0"/>
	</defs></svg>'
	paths := parse_defs_paths(content)
	assert paths.len == 0
}

fn test_parse_defs_paths_fill_none_ignored() {
	// Paths with fill="none" are common for textPath refs
	content := '<svg><defs>
		<path id="cp" d="M40 220 Q200 160 360 220" fill="none"/>
	</defs></svg>'
	paths := parse_defs_paths(content)
	assert paths.len == 1
	assert paths['cp'] == 'M40 220 Q200 160 360 220'
}
```

**Step 2: Run tests to verify they fail**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: FAIL — `parse_defs_paths` not defined.

**Step 3: Implement `parse_defs_paths`**

In `svg.v`, after `parse_defs_filters` (around line 2150), add:

```v ignore
// parse_defs_paths extracts <path> elements with id attributes
// from <defs> blocks. Returns map of id -> d attribute string.
fn parse_defs_paths(content string) map[string]string {
	mut paths := map[string]string{}
	mut pos := 0
	for pos < content.len {
		// Find <defs> block
		defs_start := find_index(content, '<defs', pos) or { break }
		defs_tag_end := find_index(content, '>', defs_start) or {
			break
		}
		is_self_closing := content[defs_tag_end - 1] == `/`
		if is_self_closing {
			pos = defs_tag_end + 1
			continue
		}
		defs_content_start := defs_tag_end + 1
		defs_end := find_closing_tag(content, 'defs',
			defs_content_start)
		if defs_end <= defs_content_start {
			pos = defs_tag_end + 1
			continue
		}
		defs_body := content[defs_content_start..defs_end]
		// Find <path> elements inside defs
		mut ppos := 0
		for ppos < defs_body.len {
			p_start := find_index(defs_body, '<path', ppos) or {
				break
			}
			p_end := find_index(defs_body, '>', p_start) or {
				break
			}
			p_elem := defs_body[p_start..p_end + 1]
			pid := find_attr(p_elem, 'id') or {
				ppos = p_end + 1
				continue
			}
			d := find_attr(p_elem, 'd') or {
				ppos = p_end + 1
				continue
			}
			paths[pid] = d
			ppos = p_end + 1
		}
		close_end := find_index(content, '>', defs_end) or { break }
		pos = close_end + 1
	}
	return paths
}
```

**Step 4: Call `parse_defs_paths` from `parse_svg`**

In `svg.v`, after line 91 (`vg.filters = parse_defs_filters(content)`),
add:

```v ignore
	vg.defs_paths = parse_defs_paths(content)
```

**Step 5: Run tests to verify they pass**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: PASS.

**Step 6: Write failing tests for textPath parsing**

Append to `_svg_textpath_test.v`:

```v ignore
fn test_parse_textpath_href() {
	content := '<svg><defs>
		<path id="cp" d="M0 0 L100 0"/>
	</defs>
	<text font-family="Arial" font-size="14" fill="#3399cc">
		<textPath href="#cp">Hello Curve</textPath>
	</text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.text_paths.len == 1
	tp := vg.text_paths[0]
	assert tp.path_id == 'cp'
	assert tp.text == 'Hello Curve'
	assert tp.font_family == 'Arial'
	assert tp.font_size > 13.0 && tp.font_size < 15.0
	assert tp.color.r == 0x33
	assert tp.color.g == 0x99
	assert tp.color.b == 0xcc
}

fn test_parse_textpath_xlink_href() {
	content := '<svg><defs>
		<path id="xp" d="M0 0 L50 50"/>
	</defs>
	<text font-size="12">
		<textPath xlink:href="#xp">XLink</textPath>
	</text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.text_paths.len == 1
	assert vg.text_paths[0].path_id == 'xp'
	assert vg.text_paths[0].text == 'XLink'
}

fn test_parse_textpath_start_offset_percent() {
	content := '<svg><defs>
		<path id="p" d="M0 0 L100 0"/>
	</defs>
	<text><textPath href="#p" startOffset="50%"
		>Half</textPath></text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.text_paths.len == 1
	tp := vg.text_paths[0]
	assert tp.start_offset > 0.49 && tp.start_offset < 0.51
	assert tp.is_percent == true
}

fn test_parse_textpath_start_offset_absolute() {
	content := '<svg><defs>
		<path id="p" d="M0 0 L100 0"/>
	</defs>
	<text><textPath href="#p" startOffset="42"
		>Abs</textPath></text></svg>'
	vg := parse_svg(content) or { panic(err) }
	tp := vg.text_paths[0]
	assert tp.start_offset > 41.9 && tp.start_offset < 42.1
	assert tp.is_percent == false
}

fn test_parse_textpath_attributes() {
	content := '<svg><defs>
		<path id="p" d="M0 0 L100 0"/>
	</defs>
	<text><textPath href="#p" text-anchor="middle"
		spacing="exact" method="stretch" side="right"
		>Attrs</textPath></text></svg>'
	vg := parse_svg(content) or { panic(err) }
	tp := vg.text_paths[0]
	assert tp.anchor == 1 // middle
	assert tp.spacing == 1 // exact
	assert tp.method == 1 // stretch
	assert tp.side == 1 // right
}

fn test_parse_textpath_inherits_font() {
	content := '<svg><defs>
		<path id="p" d="M0 0 L100 0"/>
	</defs>
	<text font-family="Helvetica" font-size="20"
		font-weight="bold" fill="#ff0000"
		stroke="#00ff00" stroke-width="2">
		<textPath href="#p">Inherited</textPath>
	</text></svg>'
	vg := parse_svg(content) or { panic(err) }
	tp := vg.text_paths[0]
	assert tp.font_family == 'Helvetica'
	assert tp.font_size > 19.0 && tp.font_size < 21.0
	assert tp.bold == true
	assert tp.color.r == 0xff
	assert tp.stroke_color.g == 0xff
	assert tp.stroke_width > 1.9 && tp.stroke_width < 2.1
}
```

**Step 7: Run tests to verify they fail**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: FAIL.

**Step 8: Implement textPath parsing in `parse_text_element`**

In `svg.v`, modify `parse_text_element` (line 306). Before the
tspan check at line 378, add textPath detection:

```v ignore
	// Check for textPath children
	if body.contains('<textPath') {
		parse_textpath_element(body, font_family, scaled_size,
			bold, italic, color, fill_gradient_id, opacity,
			letter_spacing, stroke_color, stroke_width, style,
			mut state)
		return
	}
```

Then add the `parse_textpath_element` function after
`parse_tspan_elements` (after line 546):

```v ignore
// parse_textpath_element extracts <textPath> from text body.
fn parse_textpath_element(body string, parent_family string,
	parent_size f32, parent_bold bool, parent_italic bool,
	parent_color Color, parent_gradient_id string,
	parent_opacity f32, parent_letter_spacing f32,
	parent_stroke_color Color, parent_stroke_width f32,
	style GroupStyle, mut state ParseState) {
	tp_start := find_index(body, '<textPath', 0) or { return }
	tag_end := find_index(body, '>', tp_start) or { return }
	tp_elem := body[tp_start..tag_end + 1]
	is_self_closing := body[tag_end - 1] == `/`
	// Extract text content
	text := if is_self_closing {
		''
	} else {
		content_start := tag_end + 1
		content_end := find_index(body, '</textPath',
			content_start) or { body.len }
		body[content_start..content_end].trim_space()
	}
	if text.len == 0 {
		return
	}
	// Extract href (try href first, then xlink:href)
	href_raw := find_attr(tp_elem, 'href') or {
		find_attr(tp_elem, 'xlink:href') or { return }
	}
	path_id := if href_raw.starts_with('#') {
		href_raw[1..]
	} else {
		href_raw
	}
	// startOffset
	offset_str := find_attr(tp_elem, 'startOffset') or { '0' }
	is_percent := offset_str.ends_with('%')
	start_offset := if is_percent {
		offset_str[..offset_str.len - 1].f32() / 100.0
	} else {
		parse_length(offset_str)
	}
	// text-anchor (textPath overrides parent)
	anchor_str := find_attr_or_style(tp_elem,
		'text-anchor') or { 'start' }
	anchor := match anchor_str {
		'middle' { u8(1) }
		'end' { u8(2) }
		else { u8(0) }
	}
	// Extended attributes
	spacing_str := find_attr(tp_elem, 'spacing') or { 'auto' }
	spacing := if spacing_str == 'exact' { u8(1) } else { u8(0) }
	method_str := find_attr(tp_elem, 'method') or { 'align' }
	method := if method_str == 'stretch' { u8(1) } else { u8(0) }
	side_str := find_attr(tp_elem, 'side') or { 'left' }
	side := if side_str == 'right' { u8(1) } else { u8(0) }
	// Per-textPath overrides
	fill_str := find_attr_or_style(tp_elem, 'fill') or { '' }
	tp_gradient_id := parse_fill_url(fill_str) or { '' }
	fill_gradient_id_ := if tp_gradient_id.len > 0 {
		tp_gradient_id
	} else {
		parent_gradient_id
	}
	color := if tp_gradient_id.len > 0 {
		black
	} else if fill_str.len > 0 && fill_str != 'none' {
		parse_svg_color(fill_str)
	} else {
		parent_color
	}
	fw := find_attr_or_style(tp_elem, 'font-weight') or { '' }
	bold := if fw.len > 0 {
		fw == 'bold' || fw.f32() >= 600
	} else {
		parent_bold
	}
	fi := find_attr_or_style(tp_elem, 'font-style') or { '' }
	italic := if fi.len > 0 {
		fi == 'italic' || fi == 'oblique'
	} else {
		parent_italic
	}
	ls_str := find_attr_or_style(tp_elem,
		'letter-spacing') or { '' }
	letter_spacing := if ls_str.len > 0 {
		scale := extract_transform_scale(style.transform)
		parse_length(ls_str) * scale
	} else {
		parent_letter_spacing
	}
	ts_stroke_str := find_attr_or_style(tp_elem,
		'stroke') or { '' }
	stroke_color := if ts_stroke_str.len > 0
		&& ts_stroke_str != 'none' {
		parse_svg_color(ts_stroke_str)
	} else if ts_stroke_str == 'none' {
		color_transparent
	} else {
		parent_stroke_color
	}
	ts_sw_str := find_attr_or_style(tp_elem,
		'stroke-width') or { '' }
	stroke_width := if ts_sw_str.len > 0 {
		parse_length(ts_sw_str)
	} else {
		parent_stroke_width
	}
	font_family_raw := find_attr_or_style(tp_elem,
		'font-family') or { '' }
	font_family := if font_family_raw.len > 0 {
		if font_family_raw.contains(',') {
			font_family_raw.all_before(',').trim_space().trim(
				'\'"')
		} else {
			font_family_raw.trim_space().trim('\'"')
		}
	} else {
		parent_family
	}
	state.text_paths << SvgTextPath{
		text:             text
		path_id:          path_id
		start_offset:     start_offset
		is_percent:       is_percent
		anchor:           anchor
		spacing:          spacing
		method:           method
		side:             side
		font_family:      font_family
		font_size:        parent_size
		bold:             bold
		italic:           italic
		color:            color
		opacity:          parent_opacity
		filter_id:        style.filter_id
		fill_gradient_id: fill_gradient_id_
		letter_spacing:   letter_spacing
		stroke_color:     stroke_color
		stroke_width:     stroke_width
	}
}
```

**Step 9: Add text_paths filter partitioning**

In `parse_svg` (svg.v), after the texts partitioning loop
(lines 115-122), add parallel partitioning for text_paths:

```v ignore
		// Partition text_paths by filter_id
		mut filtered_text_paths := map[string][]SvgTextPath{}
		for tp in state.text_paths {
			if tp.filter_id.len > 0 && tp.filter_id in vg.filters {
				filtered_text_paths[tp.filter_id] << tp
			} else {
				vg.text_paths << tp
			}
		}
```

In the `SvgFilteredGroup` construction (lines 123-128), add:

```v ignore
				text_paths: filtered_text_paths[fid]
```

In the else branch (lines 130-132), add:

```v ignore
		vg.text_paths = state.text_paths
```

**Step 10: Propagate in `load_svg`**

In `svg_load.v`, in the `CachedFilteredGroup` construction
(around line 90), add:

```v ignore
			text_paths: fg.text_paths
```

In both `CachedSvg` constructions (lines 113-122 and 124-136),
add:

```v ignore
		text_paths: vg.text_paths
		defs_paths: vg.defs_paths
```

**Step 11: Format and verify**

```
v fmt -w /Users/mike/.vmodules/gui/svg.v
v fmt -w /Users/mike/.vmodules/gui/svg_vector.v
v fmt -w /Users/mike/.vmodules/gui/svg_load.v
v fmt -w /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

**Step 12: Run all tests**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
v test /Users/mike/.vmodules/gui/_svg_test.v
```

Expected: all pass.

**Step 13: Commit**

```
git add svg.v svg_vector.v svg_load.v _svg_textpath_test.v
git commit -m "parse defs paths and textPath elements"
```

---

### Task 3: Arc-length parameterization

**Files:**
- Create: `/Users/mike/.vmodules/gui/svg_textpath.v`
- Modify: `/Users/mike/.vmodules/gui/_svg_textpath_test.v`

**Step 1: Write failing tests for arc-length math**

Append to `_svg_textpath_test.v`:

```v ignore
import math

fn test_build_arc_length_table_straight() {
	// Horizontal line: (0,0) -> (3,0) -> (7,0)
	poly := [f32(0), 0, 3, 0, 7, 0]
	table := build_arc_length_table(poly)
	assert table.len == 3
	assert table[0] == 0
	assert math.abs(table[1] - 3.0) < 0.01
	assert math.abs(table[2] - 7.0) < 0.01
}

fn test_build_arc_length_table_diagonal() {
	// 3-4-5 triangle: (0,0) -> (3,4)
	poly := [f32(0), 0, 3, 4]
	table := build_arc_length_table(poly)
	assert table.len == 2
	assert table[0] == 0
	assert math.abs(table[1] - 5.0) < 0.01
}

fn test_sample_path_at_endpoints() {
	poly := [f32(0), 0, 100, 0]
	table := build_arc_length_table(poly)
	x0, y0, _ := sample_path_at(poly, table, 0)
	assert math.abs(x0) < 0.01
	assert math.abs(y0) < 0.01
	x1, y1, _ := sample_path_at(poly, table, 100)
	assert math.abs(x1 - 100) < 0.01
	assert math.abs(y1) < 0.01
}

fn test_sample_path_at_midpoint() {
	poly := [f32(0), 0, 100, 0]
	table := build_arc_length_table(poly)
	x, y, _ := sample_path_at(poly, table, 50)
	assert math.abs(x - 50) < 0.01
	assert math.abs(y) < 0.01
}

fn test_sample_path_at_angle_horizontal() {
	poly := [f32(0), 0, 100, 0]
	table := build_arc_length_table(poly)
	_, _, angle := sample_path_at(poly, table, 50)
	assert math.abs(angle) < 0.01 // 0 radians = rightward
}

fn test_sample_path_at_angle_l_shape() {
	// Right then up: (0,0) -> (10,0) -> (10,10)
	poly := [f32(0), 0, 10, 0, 10, 10]
	table := build_arc_length_table(poly)
	// Sample in first segment — angle should be 0 (rightward)
	_, _, a1 := sample_path_at(poly, table, 5)
	assert math.abs(a1) < 0.01
	// Sample in second segment — angle should be pi/2 (upward)
	_, _, a2 := sample_path_at(poly, table, 15)
	assert math.abs(a2 - math.pi / 2) < 0.01
}

fn test_sample_path_clamp_beyond() {
	poly := [f32(0), 0, 10, 0]
	table := build_arc_length_table(poly)
	// Beyond end: should clamp to last point
	x, _, _ := sample_path_at(poly, table, 999)
	assert math.abs(x - 10) < 0.01
	// Before start: should clamp to first point
	x2, _, _ := sample_path_at(poly, table, -5)
	assert math.abs(x2) < 0.01
}
```

**Step 2: Run tests to verify they fail**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: FAIL — functions not defined.

**Step 3: Implement arc-length functions**

Create `/Users/mike/.vmodules/gui/svg_textpath.v`:

```v ignore
module gui

import math

// flatten_defs_path parses a path d attribute and flattens
// to a polyline with coordinates scaled by scale.
fn flatten_defs_path(d string, scale f32) []f32 {
	segments := parse_path_d(d)
	if segments.len == 0 {
		return []f32{}
	}
	path := VectorPath{
		segments:  segments
		transform: [scale, f32(0), 0, scale, 0, 0]!
	}
	tolerance := 0.5 / scale
	tol := if tolerance > 0.15 { tolerance } else { f32(0.15) }
	polylines := flatten_path(path, tol)
	if polylines.len == 0 {
		return []f32{}
	}
	return polylines[0]
}

// build_arc_length_table computes cumulative arc lengths along
// a polyline. polyline is [x0,y0, x1,y1, ...]. Returns array
// of same point count where table[i] = cumulative distance
// from point 0 to point i.
fn build_arc_length_table(polyline []f32) []f32 {
	n := polyline.len / 2
	if n < 1 {
		return []f32{}
	}
	mut table := []f32{len: n}
	table[0] = 0
	for i := 1; i < n; i++ {
		dx := polyline[i * 2] - polyline[(i - 1) * 2]
		dy := polyline[i * 2 + 1] - polyline[(i - 1) * 2 + 1]
		table[i] = table[i - 1] + math.sqrtf(dx * dx + dy * dy)
	}
	return table
}

// sample_path_at returns (x, y, angle) at distance dist along
// the polyline. Uses binary search on the arc-length table
// for O(log n) lookup. Clamps to endpoints if dist is out of
// range.
fn sample_path_at(polyline []f32, table []f32, dist f32) (f32, f32, f32) {
	n := table.len
	if n < 2 {
		if n == 1 {
			return polyline[0], polyline[1], 0
		}
		return 0, 0, 0
	}
	total := table[n - 1]
	// Clamp
	if dist <= 0 {
		dx := polyline[2] - polyline[0]
		dy := polyline[3] - polyline[1]
		return polyline[0], polyline[1], f32(math.atan2(dy, dx))
	}
	if dist >= total {
		last := (n - 1) * 2
		prev := (n - 2) * 2
		dx := polyline[last] - polyline[prev]
		dy := polyline[last + 1] - polyline[prev + 1]
		return polyline[last], polyline[last + 1],
			f32(math.atan2(dy, dx))
	}
	// Binary search for enclosing segment
	mut lo := 0
	mut hi := n - 1
	for lo < hi - 1 {
		mid := (lo + hi) / 2
		if table[mid] <= dist {
			lo = mid
		} else {
			hi = mid
		}
	}
	// Interpolate within segment lo..hi
	seg_len := table[hi] - table[lo]
	t := if seg_len > 0 {
		(dist - table[lo]) / seg_len
	} else {
		f32(0)
	}
	x0 := polyline[lo * 2]
	y0 := polyline[lo * 2 + 1]
	x1 := polyline[hi * 2]
	y1 := polyline[hi * 2 + 1]
	x := x0 + (x1 - x0) * t
	y := y0 + (y1 - y0) * t
	angle := f32(math.atan2(y1 - y0, x1 - x0))
	return x, y, angle
}
```

**Step 4: Format**

```
v fmt -w /Users/mike/.vmodules/gui/svg_textpath.v
v fmt -w /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

**Step 5: Run tests**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: all pass.

**Step 6: Commit**

```
git add svg_textpath.v _svg_textpath_test.v
git commit -m "add arc-length parameterization for textPath"
```

---

### Task 4: `DrawLayoutPlaced` renderer variant

**Files:**
- Modify: `/Users/mike/.vmodules/gui/render.v:153-181, 359-367`
- Modify: `/Users/mike/.vmodules/gui/print_pdf.v:449-451`

**Step 1: Add `DrawLayoutPlaced` struct**

In `render.v`, after `DrawLayoutTransformed` (line 159), add:

```v ignore
struct DrawLayoutPlaced {
	layout     &vglyph.Layout
	placements []vglyph.GlyphPlacement
}
```

**Step 2: Add to `Renderer` sumtype**

In the `Renderer` sumtype (line 163-181), add
`| DrawLayoutPlaced` after `| DrawLayoutTransformed`.

**Step 3: Add dispatch case in `renderer_draw`**

After the `DrawLayoutTransformed` match arm (around line 359-367),
add:

```v ignore
		DrawLayoutPlaced {
			window.text_system.draw_layout_placed(renderer.layout,
				renderer.placements)
		}
```

**Step 4: Add no-op case in `print_pdf.v`**

In `pdf_render_stream` match (after `DrawLayoutTransformed` case
around line 449-451), add:

```v ignore
			DrawLayoutPlaced {}
```

Also in the alpha detection match (around lines 104-115), add:

```v ignore
			DrawLayoutPlaced {
				for item in renderer.layout.items {
					seen[item.color.a] = true
				}
			}
```

**Step 5: Format**

```
v fmt -w /Users/mike/.vmodules/gui/render.v
v fmt -w /Users/mike/.vmodules/gui/print_pdf.v
```

**Step 6: Verify compilation**

```
v -check-syntax /Users/mike/.vmodules/gui/render.v
v -check-syntax /Users/mike/.vmodules/gui/print_pdf.v
```

**Step 7: Run existing tests**

```
v test /Users/mike/.vmodules/gui/_svg_test.v
v test /Users/mike/.vmodules/gui/_render_test.v
```

Expected: all pass.

**Step 8: Commit**

```
git add render.v print_pdf.v
git commit -m "add DrawLayoutPlaced renderer variant"
```

---

### Task 5: `render_svg_text_path` and integration

**Files:**
- Modify: `/Users/mike/.vmodules/gui/svg_textpath.v`
- Modify: `/Users/mike/.vmodules/gui/render.v:1789-1832`

**Step 1: Implement `render_svg_text_path`**

Add to `svg_textpath.v`:

```v ignore
// render_svg_text_path places text along a referenced path
// and emits a DrawLayoutPlaced renderer.
fn render_svg_text_path(tp SvgTextPath,
	defs_paths map[string]string, shape_x f32, shape_y f32,
	scale f32, gradients map[string]SvgGradientDef,
	mut window Window) {
	d := defs_paths[tp.path_id] or { return }
	polyline := flatten_defs_path(d, scale)
	if polyline.len < 4 {
		return
	}
	table := build_arc_length_table(polyline)
	total_len := table[table.len - 1]
	if total_len <= 0 {
		return
	}
	// Build text config
	typeface := match true {
		tp.bold && tp.italic {
			vglyph.Typeface.bold_italic
		}
		tp.bold { vglyph.Typeface.bold }
		tp.italic { vglyph.Typeface.italic }
		else { vglyph.Typeface.regular }
	}
	cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			family:   tp.font_family
			size:     tp.font_size * scale
			typeface: typeface
			color:    tp.color.to_gx_color()
		}
	}
	layout := window.text_system.layout_text(tp.text,
		cfg) or { return }
	glyph_infos := layout.glyph_positions()
	if glyph_infos.len == 0 {
		return
	}
	// Compute total advance
	mut total_advance := f32(0)
	for gi in glyph_infos {
		total_advance += gi.advance
	}
	// Resolve startOffset
	mut offset := if tp.is_percent {
		tp.start_offset * total_len
	} else {
		tp.start_offset * scale
	}
	// text-anchor adjustment
	if tp.anchor == 1 {
		offset -= total_advance / 2
	} else if tp.anchor == 2 {
		offset -= total_advance
	}
	// method=stretch: scale advances
	advance_scale := if tp.method == 1 && total_advance > 0 {
		remaining := total_len - offset
		if remaining > 0 { remaining / total_advance } else { f32(1) }
	} else {
		f32(1)
	}
	// Place glyphs
	mut placements := []vglyph.GlyphPlacement{cap: glyph_infos.len}
	mut cur_advance := f32(0)
	for gi in glyph_infos {
		advance := gi.advance * advance_scale
		center_dist := offset + cur_advance + advance / 2
		px, py, angle := sample_path_at(polyline, table,
			center_dist)
		// Shift back by half advance along tangent
		cos_a := math.cosf(angle)
		sin_a := math.sinf(angle)
		gx := px - cos_a * advance / 2 + shape_x
		gy := py - sin_a * advance / 2 + shape_y
		mut final_angle := angle
		if tp.side == 1 {
			final_angle += math.pi
		}
		placements << vglyph.GlyphPlacement{
			x:     gx
			y:     gy
			angle: final_angle
		}
		cur_advance += advance
	}
	cloned := clone_layout_for_draw(&layout)
	window.renderers << DrawLayoutPlaced{
		layout:     cloned
		placements: placements
	}
}
```

Note: `clone_layout_for_draw` is already defined in render.v.
The function also needs `import math` and `import vglyph` at
the top of `svg_textpath.v` (vglyph is already imported by the
gui module).

**Step 2: Add render_svg calls**

In `render.v`, after the main texts loop (line 1793), add:

```v ignore
	// Emit textPath elements
	for tp in cached.text_paths {
		render_svg_text_path(tp, cached.defs_paths, shape.x,
			shape.y, cached.scale, cached.gradients, mut window)
	}
```

In the filtered groups loop, after the filtered texts loop
(line 1830), add:

```v ignore
		// Emit textPath elements for filtered group
		for tp in fg.text_paths {
			render_svg_text_path(tp, cached.defs_paths, shape.x,
				shape.y, cached.scale, fg.gradients, mut window)
		}
```

**Step 3: Format**

```
v fmt -w /Users/mike/.vmodules/gui/svg_textpath.v
v fmt -w /Users/mike/.vmodules/gui/render.v
```

**Step 4: Run all tests**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
v test /Users/mike/.vmodules/gui/_svg_test.v
v test /Users/mike/.vmodules/gui/_render_test.v
```

Expected: all pass.

**Step 5: Commit**

```
git add svg_textpath.v render.v
git commit -m "render textPath text along curves"
```

---

### Task 6: Manual verification and edge cases

**Step 1: Run svg_viewer example**

```
v run /Users/mike/.vmodules/gui/examples/svg_viewer.v
```

Select "Text with Fonts". Verify "Text Following a Curved Path"
renders along the quadratic Bezier curve.

**Step 2: Test with custom SVG**

Create a test SVG with:
- Multi-segment path (line + cubic)
- `startOffset="0"` (text at start)
- `text-anchor="end"` (text aligned to end)
- `side="right"` (text on opposite side)

Verify each renders correctly.

**Step 3: Edge case tests**

Append to `_svg_textpath_test.v`:

```v ignore
fn test_parse_textpath_no_matching_path() {
	// textPath references non-existent path — should still parse
	content := '<svg>
	<text><textPath href="#missing">Ghost</textPath></text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.text_paths.len == 1
	assert vg.text_paths[0].path_id == 'missing'
}

fn test_parse_textpath_empty_text() {
	content := '<svg><defs>
		<path id="p" d="M0 0 L100 0"/>
	</defs>
	<text><textPath href="#p"></textPath></text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.text_paths.len == 0
}

fn test_parse_svg_with_textpath_full() {
	// Full SVG matching the example in svg_viewer.v
	content := '<svg viewBox="0 0 400 400">
	<defs>
		<path id="curvePath"
			d="M40 220 Q200 160 360 220" fill="none"/>
	</defs>
	<text font-family="Arial" font-size="13"
		fill="#3399cc" font-weight="600">
		<textPath href="#curvePath" startOffset="50%"
			text-anchor="middle"
			>Text Following a Curved Path</textPath>
	</text></svg>'
	vg := parse_svg(content) or { panic(err) }
	assert vg.defs_paths.len == 1
	assert 'curvePath' in vg.defs_paths
	assert vg.text_paths.len == 1
	tp := vg.text_paths[0]
	assert tp.path_id == 'curvePath'
	assert tp.text == 'Text Following a Curved Path'
	assert tp.is_percent == true
	assert tp.start_offset > 0.49 && tp.start_offset < 0.51
	assert tp.anchor == 1
	assert tp.bold == true // font-weight 600
	assert tp.font_family == 'Arial'
}
```

**Step 4: Run tests**

```
v test /Users/mike/.vmodules/gui/_svg_textpath_test.v
```

Expected: all pass.

**Step 5: Run full gui test suite**

```
v test /Users/mike/.vmodules/gui/_svg_test.v
v test /Users/mike/.vmodules/gui/_svg_clip_test.v
```

Expected: all pass (no regressions).

**Step 6: Commit**

```
git add _svg_textpath_test.v
git commit -m "add edge case tests for textPath"
```

---

## Unresolved Questions

- None. All decisions made during design phase.
