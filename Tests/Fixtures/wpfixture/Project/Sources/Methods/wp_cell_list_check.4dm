var wpWebErrors : Collection:=New collection()
ON ERR CALL("wp_web_error")
var $compilation : Object:=Compile project()
If ($compilation.success)
	wp_cell_list_probe
Else
	wpWebErrors.push(New object("message"; "Probe compilation failed"; "details"; $compilation.errors))
End if
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
$root.file("Output/cell-list-errors.json").setText(JSON Stringify(wpWebErrors; *))
ON ERR CALL("")
QUIT 4D
