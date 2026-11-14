var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $cell; $item; $section; $area : Object
var $merge : Collection
var $kind : Text
var $row; $column; $headers; $columns; $rows : Integer
var $width : Variant
var $merges : Collection
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("vertical"; "header"; "two-headers"; "mixed"; "unicode"; "lists"; "rich"; "media"; "seam"; "chain"; "tall"; "header-cross"; "no-witness"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "ROWSTART"; wk replace)
	If ($kind="seam")
		$range:=WP Insert break($body; wk continuous section break; wk append)
		WP SET TEXT($body; "ROWSEAM"; wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
	For ($row; 1; 26)
		If ($kind="unicode")
			$range:=WP Table append row($table; "R"+String($row)+"A ü"; "R"+String($row)+"B 日本"; "R"+String($row)+"C 🚃é")
		Else
			$range:=WP Table append row($table; "R"+String($row)+"A"; "R"+String($row)+"B"; "R"+String($row)+"C")
		End if
	End for
	$headers:=0
	If ($kind="header") | ($kind="rich") | ($kind="media") | ($kind="header-cross") | ($kind="tall")
		$headers:=1
	End if
	If ($kind="two-headers")
		$headers:=2
	End if
	WP SET ATTRIBUTES($table; wk header row count; $headers; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
	WP SET ATTRIBUTES(WP Table get columns($table; 1); wk width; "50pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 2); wk width; "70pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 3); wk width; "110pt"; wk padding; "3pt")
	$item:=New object("name"; $kind; "headers"; $headers; "before"; wp_web_stats($doc; False); "merges"; New collection(); "cells"; New collection())
	WP EXPORT DOCUMENT($doc; $root.file("Output/rowspan-"+$kind+"-before.4wp").platformPath; wk 4wp)
	// Each merge is column; row; column count; row count (origin 1), applied in this order.
	$merges:=New collection()
	Case of
		: ($kind="tall")
			$merges.push(New collection(3; 3; 1; 18))
		: ($kind="header-cross")
			$merges.push(New collection(1; 1; 1; 2))
			$merges.push(New collection(3; 9; 1; 2))
		: ($kind="no-witness")
			For ($row; 1; 25; 2)
				$merges.push(New collection(1; $row; 1; 2))
			End for
		: ($kind="chain")
			$merges.push(New collection(1; 5; 1; 3))
			$merges.push(New collection(2; 7; 1; 3))
			$merges.push(New collection(3; 14; 1; 2))
			$merges.push(New collection(1; 15; 1; 2))
		: ($kind="mixed")
			$merges.push(New collection(1; 3; 2; 1))
			$merges.push(New collection(1; 5; 2; 2))
			$merges.push(New collection(2; 9; 2; 1))
			$merges.push(New collection(3; 11; 1; 3))
			$merges.push(New collection(1; 17; 3; 2))
		Else
			If ($kind="two-headers")
				$merges.push(New collection(1; 1; 1; 2))
			End if
			$merges.push(New collection(3; 5; 1; 2))
			$merges.push(New collection(1; 9; 1; 3))
			$merges.push(New collection(2; 15; 1; 2))
			$merges.push(New collection(3; 21; 1; 4))
	End case
	For each ($merge; $merges)
		WP TABLE MERGE CELLS($table; $merge[0]; $merge[1]; $merge[2]; $merge[3])
		$item.merges.push($merge)
	End for each
	If ($headers>0)
		WP SET ATTRIBUTES(WP Table get rows($table; 1; $headers); wk background color; "#DDEEFF"; wk font bold; wk true)
	End if
	If ($kind="lists") | ($kind="rich")
		$cell:=WP Table get cells($table; 3; 21)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk disc; wk list font; "Arial"; wk margin left; "24pt"; wk font bold; wk true; wk text color; "#135724")
		$cell:=WP Table get cells($table; 2; 15)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk diamond; wk list font; "Arial"; wk margin left; "24pt")
	End if
	If ($kind="rich") | ($kind="media")
		$cell:=WP Table get cells($table; 3; 5)
		$range:=WP Get elements($cell; wk type paragraph)[0]
		WP INSERT PICTURE($range; $picture; wk prepend)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "30pt"; wk height; "24pt")
		// rich: formula beside the disc list in the 4-row band; media: formula after the picture in the 2-row band.
		$cell:=WP Table get cells($table; 3; Choose($kind="rich"; 21; 5))
		$range:=WP Get elements($cell; wk type paragraph)[Choose($kind="rich"; 0; 1)]
		WP INSERT FORMULA($range; Formula(Uppercase("rowc")); wk prepend)
		$cell:=WP Table get cells($table; 1; 9)
		WP SET LINK(WP Text range($cell; wk start text; wk end text); New object("url"; "https://example.invalid/row"))
		WP SET ATTRIBUTES($cell; wk font italic; wk true)
	End if
	$rows:=WP Get elements($table; wk type table row).length
	$item.rows:=$rows
	$columns:=3
	For ($row; 1; $rows)
		For ($column; 1; $columns)
			$cell:=WP Table get cells($table; $column; $row)
			WP GET ATTRIBUTES($cell; wk width; $width)
			$item.cells.push(New object("row"; $row; "column"; $column; "width"; $width; "text"; WP Get text($cell; wk expressions as source)))
		End for
	End for
	WP SET TEXT($body; "ROWEND"; wk append)
	If ($kind#"seam")
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "ROWDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		$section:=WP New subsection($section; wk first page)
		$area:=WP Get header($section)
		WP SET TEXT($area; "ROWFIRSTHEADER"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	$item.original:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/rowspan-"+$kind+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/rowspan-"+$kind+".pdf").platformPath; wk pdf)
	If ($kind#"seam")
		WP SET TEXT($area; "WEBROW"; wk replace)
	Else
		WP SET TEXT(WP Text range($body; 1; 9); "WEBROW"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/rowspan-"+$kind+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/rowspan-report.json").setText(JSON Stringify($report; *))
