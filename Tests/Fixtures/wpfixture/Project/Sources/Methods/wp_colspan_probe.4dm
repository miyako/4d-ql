var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $cell; $item; $section; $area : Object
var $kind : Text
var $row; $column; $headers; $columns; $rows : Integer
var $width : Variant
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("plain"; "header"; "two-headers"; "late-witness"; "rich"; "seam"; "no-witness"; "vertical"; "mixed"; "overflow"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "SPANSTART"; wk replace)
	If ($kind="seam")
		$range:=WP Insert break($body; wk continuous section break; wk append)
		WP SET TEXT($body; "SPANSEAM"; wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
	For ($row; 1; 26)
		$range:=WP Table append row($table; "R"+String($row)+"A"; "R"+String($row)+"B"; "R"+String($row)+"C")
	End for
	$headers:=0
	If ($kind="header") | ($kind="rich")
		$headers:=1
	End if
	If ($kind="two-headers") | ($kind="overflow")
		$headers:=2
	End if
	WP SET ATTRIBUTES($table; wk header row count; $headers; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
	WP SET ATTRIBUTES(WP Table get columns($table; 1); wk width; "50pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 2); wk width; "70pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 3); wk width; "110pt"; wk padding; "3pt")
	$item:=New object("name"; $kind; "headers"; $headers; "before"; wp_web_stats($doc; False); "cells"; New collection())
	WP EXPORT DOCUMENT($doc; $root.file("Output/colspan-"+$kind+"-before.4wp").platformPath; wk 4wp)
	For ($row; 1; 26)
		If (($row%2)=1)
			WP TABLE MERGE CELLS($table; 1; $row; 2; 1)
		Else
			If (($row%4)=0) | ($kind="no-witness") | (($row=2) & (($kind="two-headers") | ($kind="overflow")))
				WP TABLE MERGE CELLS($table; 2; $row; 2; 1)
			End if
		End if
	End for
	If ($kind="late-witness")
		WP TABLE MERGE CELLS($table; 1; 2; 3; 1)
	End if
	If ($kind="vertical")
		WP TABLE MERGE CELLS($table; 3; 5; 1; 2)
	End if
	If ($kind="mixed")
		WP TABLE MERGE CELLS($table; 1; 5; 2; 2)
	End if
	If ($headers>0)
		WP SET ATTRIBUTES(WP Table get rows($table; 1; $headers); wk background color; "#DDEEFF"; wk font bold; wk true)
	End if
	If ($kind="rich") | ($kind="overflow")
		$cell:=WP Table get cells($table; 1; 1)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk disc; wk list font; "Arial"; wk margin left; "24pt"; wk font bold; wk true; wk text color; "#135724")
		$cell:=WP Table get cells($table; 2; 4)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk diamond; wk list font; "Arial"; wk margin left; "24pt")
		$cell:=WP Table get cells($table; 1; 7)
		$range:=WP Get elements($cell; wk type paragraph)[0]
		WP INSERT PICTURE($range; $picture; wk prepend)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "30pt"; wk height; "24pt")
		$cell:=WP Table get cells($table; 1; 9)
		$range:=WP Get elements($cell; wk type paragraph)[0]
		WP INSERT FORMULA($range; Formula(Uppercase("spancache")); wk prepend)
		$cell:=WP Table get cells($table; 1; 11)
		WP SET LINK(WP Text range($cell; wk start text; wk end text); New object("url"; "https://example.invalid/span"))
		WP SET ATTRIBUTES($cell; wk font italic; wk true; wk text underline style; wk solid)
		$cell:=WP Table get cells($table; 1; 13)
		WP SET TEXT($cell; "R13A wrapped words across several lines in the merged cell\rR13B"; wk replace)
	End if
	$rows:=WP Get elements($table; wk type table row).length
	$columns:=3
	For ($row; 1; $rows)
		For ($column; 1; $columns)
			$cell:=WP Table get cells($table; $column; $row)
			WP GET ATTRIBUTES($cell; wk width; $width)
			$item.cells.push(New object("row"; $row; "column"; $column; "width"; $width; "text"; WP Get text($cell; wk expressions as source)))
		End for
	End for
	WP SET TEXT($body; "SPANEND"; wk append)
	If ($kind#"seam")
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "SPANDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		$section:=WP New subsection($section; wk first page)
		$area:=WP Get header($section)
		WP SET TEXT($area; "SPANFIRSTHEADER"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	$item.original:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/colspan-"+$kind+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/colspan-"+$kind+".pdf").platformPath; wk pdf)
	If ($kind#"seam")
		WP SET TEXT($area; "WEBSPAN"; wk replace)
	Else
		WP SET TEXT(WP Text range($body; 1; 10); "WEBSPAN"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/colspan-"+$kind+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP TABLE SPLIT CELLS($table; 1; 1)
	$item.split:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/colspan-"+$kind+"-split.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/colspan-report.json").setText(JSON Stringify($report; *))
