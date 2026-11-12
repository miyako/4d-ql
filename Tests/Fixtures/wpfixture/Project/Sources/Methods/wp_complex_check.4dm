var wpWebErrors : Collection:=New collection()
ON ERR CALL("wp_web_error")
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $compilation : Object:=Compile project()
If ($compilation.success)
	$root.file("Output/complex-report.json").setText(JSON Stringify(New object("version"; Application version(*); "cases"; wp_complex_probe); *))
Else
	wpWebErrors.push(New object("message"; "Probe compilation failed"; "details"; $compilation.errors))
End if
$root.file("Output/complex-errors.json").setText(JSON Stringify(wpWebErrors; *))
ON ERR CALL("")
QUIT 4D
