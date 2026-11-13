var wpWebErrors : Collection:=New collection()
ON ERR CALL("wp_web_error")
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $file : 4D.File
var $doc : Object
For each ($file; $root.folder("Input").files())
	$doc:=WP Import document($file.platformPath)
	$report.cases.push(New object("name"; $file.name; "stats"; wp_layout_stats($doc)))
	WP EXPORT DOCUMENT($doc; $root.file("Output/"+$file.name).platformPath; wk 4wp)
End for each
$root.file("Output/layout-input-report.json").setText(JSON Stringify($report; *))
$root.file("Output/layout-errors.json").setText(JSON Stringify(wpWebErrors; *))
ON ERR CALL("")
QUIT 4D
