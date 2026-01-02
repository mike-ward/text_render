#!/usr/bin/env -S v

fn sh(cmd string) {
	println('❯ ${cmd}')
	print(execute_or_exit(cmd).output)
}

unbuffer_stdout()
chdir(@DIR)!

sh('v fmt . -w')
sh('v -check -N -W ../examples/demo.v')
sh('v -check -N -W ../examples/new_api_demo.v')
sh('v -check -N -W ../examples/style_demo.v')
sh('v test .')
sh('v check-md .')
