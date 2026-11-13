var wpWebErrors : Collection:=New collection()
ON ERR CALL("wp_web_error")
var $compilation : Object:=Compile project()
If ($compilation.success)
	wp_print_probe
	wp_paged_probe
	wp_expanded_paged_probe
Else
	wpWebErrors.push(New object("message"; "Probe compilation failed"; "details"; $compilation.errors))
End if
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
$root.file("Output/print-errors.json").setText(JSON Stringify(wpWebErrors; *))
ON ERR CALL("")
QUIT 4D
