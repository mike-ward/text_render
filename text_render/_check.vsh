#!/usr/bin/env -S v

fn sh(cmd string) {
	println('❯ ${cmd}')
	print(execute_or_exit(cmd).output)
}

unbuffer_stdout()
chdir(@DIR)!

sh('v fmt . -w')
sh('v -check -N ../examples/demo.v')
sh('v -check -N ../examples/new_api_demo.v')
sh('v -check -N ../examples/style_demo.v')
sh('v -check -N ../examples/atlas_debug.v')
sh('v -check -N ../examples/icon_font_grid.v')
sh('v test .')
sh('v check-md .')
