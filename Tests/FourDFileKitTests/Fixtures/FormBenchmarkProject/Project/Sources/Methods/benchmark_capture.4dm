var $param : Text
LOG EVENT(Into system standard outputs; "BENCHMARK ENTER"; Information message)
Get database parameter(User param value; $param)
var $parts : Collection
$parts:=Split string($param; ":")
SET APPLICATION COLOR SCHEME($parts[0])
var $formName : Text
$formName:=$parts[1]
var $page : Integer
$page:=Num($parts[2])
var $file : 4D.File
$file:=File($parts.slice(3).join(":"))
$file.parent.create()
var $width; $height; $pages : Integer
FORM GET PROPERTIES($formName; $width; $height; $pages)
var $context : Object
$context:={mode: "named-static"; form: $formName; page: $page; width: $width; height: $height; pages: $pages; applicationScheme: Get Application color scheme}
LOG EVENT(Into system standard outputs; "BENCHMARK THEME PROBE"; Information message)
FORM LOAD("Typography")
$context.themeProbeForm:="Typography"
$context.loadedTheme:=FORM theme
$context.loadedScheme:=FORM Get color scheme
FORM UNLOAD
LOG EVENT(Into system standard outputs; "BENCHMARK NAMED SCREENSHOT"; Information message)
var $picture : Picture
FORM SCREENSHOT($formName; $picture; $page)
WRITE PICTURE FILE($file.platformPath; $picture)
LOG EVENT(Into system standard outputs; "BENCHMARK PNG WRITTEN"; Information message)
File($file.path+".json").setText(JSON Stringify($context; *))
LOG EVENT(Into system standard outputs; JSON Stringify($context; *); Information message)
QUIT 4D
