var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $kind; $token : Text
var $doc; $body; $table; $range; $item; $cell; $section; $area : Object
var $row; $column; $headers : Integer
var $width : Variant
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("plain"; "headers"; "mixed"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "TABLESTART"; wk replace)
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
	$headers:=Choose($kind="plain"; 0; 1)
	If ($kind="headers")
		$headers:=2
	End if
	If ($headers>0)
		$range:=WP Table append row($table; "HEADA"; "HEADB")
	End if
	If ($headers=2)
		$range:=WP Table append row($table; "HEAD2A"; "HEAD2B")
	End if
	For ($row; 0; 39)
		$token:="TABROW"+String($row)
		$range:=WP Table append row($table; $token; "VALUE"+String($row)+" word")
	End for
	WP SET ATTRIBUTES($table; wk header row count; $headers; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
	WP SET ATTRIBUTES(WP Table get columns($table; 1); wk width; "70pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 2); wk width; "130pt"; wk padding; "3pt")
	If ($headers>0)
		WP SET ATTRIBUTES(WP Table get rows($table; 1; $headers); wk background color; "#DDEEFF"; wk font bold; wk true)
	End if
	$cell:=WP Table get cells($table; 1; $headers+2)
	WP SET ATTRIBUTES($cell; wk text color; "#135724"; wk font bold; wk true)
	WP NEW BOOKMARK(WP Text range($cell; wk start text; wk end text); "table_cell")
	If ($kind="mixed")
		$cell:=WP Table get cells($table; 2; $headers+3)
		WP INSERT PICTURE(WP Text range($cell; wk end text; wk end text); $picture; wk append)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "30pt"; wk height; "24pt")
		$cell:=WP Table get cells($table; 2; $headers+5)
		WP INSERT FORMULA($cell; Formula("TABLECACHE"); wk append)
	End if
	WP SET TEXT($body; "TABLEEND"; wk append)
	If ($kind="mixed")
		$range:=WP Insert break($body; wk section break; wk append)
		WP SET TEXT($body; "SECONDSECTION"; wk append)
		$section:=WP Get section($doc; 2)
		WP SET ATTRIBUTES($section; wk page orientation; wk landscape)
	End if
	$section:=WP Get section($doc; 1)
	$area:=WP New header($section)
	WP SET TEXT($area; "TABLEDEFAULTHEADER"; wk replace)
	WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
	$section:=WP New subsection($section; wk first page)
	$area:=WP Get header($section)
	WP SET TEXT($area; "TABLEFIRSTHEADER"; wk replace)
	$item:=New object("name"; $kind; "headers"; $headers; "cells"; New collection(); "original"; wp_web_stats($doc; False))
	For ($row; 1; 40+$headers)
		For ($column; 1; 2)
			$cell:=WP Table get cells($table; $column; $row)
			WP GET ATTRIBUTES($cell; wk width; $width)
			$item.cells.push(New object("row"; $row; "column"; $column; "width"; $width; "text"; WP Get text($cell; wk expressions as source)))
		End for
	End for
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-table-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-table-"+$kind+".pdf").platformPath; wk pdf)
	WP SET TEXT($area; "WEBTABLE"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-table-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/paged-table-report.json").setText(JSON Stringify($report; *))
