module main

import gg
import vglyph

const window_width = 800
const window_height = 600

struct RichTextApp {
mut:
	gg &gg.Context
	ts &vglyph.TextSystem
}

fn main() {
	mut app := &RichTextApp{
		gg: unsafe { nil }
		ts: unsafe { nil }
	}

	app.gg = gg.new_context(
		bg_color:      gg.white
		width:         window_width
		height:        window_height
		window_title:  'VGlyph Rich Text Demo'
		init_fn:       init
		frame_fn:      frame
		user_data:     app
		create_window: true
	)

	app.gg.run()
}

fn init(mut app RichTextApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }
}

fn frame(mut app RichTextApp) {
	app.gg.begin()

	base_cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 20'
			color:     gg.black
		}
	}

	// 1. Simple Rich Text
	// "This is a " (Normal)
	// "RichText" (Bold Blue)
	// " example with " (Normal)
	// "bold" (Bold)
	// " and " (Normal)
	// "red" (Red)
	// " words." (Normal)

	runs1 := [
		vglyph.StyleRun{
			text: 'This is a '
		},
		vglyph.StyleRun{
			text:  'RichText'
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 20'
				color:     gg.blue
			}
		},
		vglyph.StyleRun{
			text: ' example with '
		},
		vglyph.StyleRun{
			text:  'bold'
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 20'
			}
		},
		vglyph.StyleRun{
			text: ' and '
		},
		vglyph.StyleRun{
			text:  'red'
			style: vglyph.TextStyle{
				color: gg.red
			}
		},
		vglyph.StyleRun{
			text: ' words.'
		},
	]

	rt1 := vglyph.RichText{
		runs: runs1
	}

	layout1 := app.ts.layout_rich_text(rt1, base_cfg) or { return }
	app.ts.draw_layout(layout1, 50, 50)

	// 2. Decorations and Variations
	runs2 := [
		vglyph.StyleRun{
			text:  'Underline'
			style: vglyph.TextStyle{
				underline: true
				color:     gg.hex(0x008800)
			}
		},
		vglyph.StyleRun{
			text: ', '
		},
		vglyph.StyleRun{
			text:  'Strikethrough'
			style: vglyph.TextStyle{
				strikethrough: true
				color:         gg.hex(0x880000)
			}
		},
		vglyph.StyleRun{
			text: ', and '
		},
		vglyph.StyleRun{
			text:  'Variable Weight'
			style: vglyph.TextStyle{
				font_name: 'Sans 20'
				features:  &vglyph.FontFeatures{
					variation_axes: {
						'wght': f32(900.0)
					}
				}
			}
		},
	]

	rt2 := vglyph.RichText{
		runs: runs2
	}

	layout2 := app.ts.layout_rich_text(rt2, base_cfg) or { return }
	app.ts.draw_layout(layout2, 50, 150)

	app.gg.end()
	app.ts.commit()
}
