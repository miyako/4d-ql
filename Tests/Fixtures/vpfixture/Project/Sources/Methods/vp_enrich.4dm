#DECLARE($area : Text; $params : Object)
// Probe unsupported-by-wrapper attributes through the documented object import API.
var $book; $sheet; $cell : Object
$book:=VP Export to object($area)
$sheet:=$book.spreadJS.sheets["Hidden candidate"]
$sheet.visible:=0
$sheet:=$book.spreadJS.sheets["Very hidden candidate"]
$sheet.visible:=2
$sheet:=$book.spreadJS.sheets["First"]
$cell:={value: {richText: [{text: "Bold"; style: {font: "bold 12pt Arial"; foreColor: "#ff0000"}}; {text: " plain"; style: {font: "12pt Arial"}}]}}
$sheet.data.dataTable["2"]:=New object("0"; $cell)
VP IMPORT FROM OBJECT($area; $book; $params)
