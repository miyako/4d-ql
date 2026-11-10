// Compiles the project and prints errors, so a typo in a probe never fails silently.
var $result : Object:=Compile project()
var $e : Object
For each ($e; $result.errors)
	wp_log(($e.isError ? "COMPILE ERROR " : "COMPILE WARNING ")+$e.code.path+":"+String($e.lineInFile)+" "+$e.message)
End for each
wp_log("COMPILE "+($result.success ? "OK" : "FAILED"))
