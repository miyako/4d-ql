var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $cell; $item; $section; $area; $paragraph; $cellReport; $target : Object
var $kind : Text
var $long : Text
var $prefix : Text
var $row; $column; $style; $start; $rows; $headers; $sectionIndex; $variant : Integer
var $flow : Boolean
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
var $actualStyle; $actualStart; $indent; $font; $format : Variant
For each ($kind; New collection("decimal"; "bullet"; "latin"; "roman"; "format"; "flow"; "headers"; "two-headers"; "mixed"; "seam"; "disc"; "circle"; "hollow-square"; "diamond"; "upper-latin"; "lower-roman"; "limit"; "oversize"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "CELLSTART"; wk replace)
	If ($kind="seam")
		$range:=WP Insert break($body; wk continuous section break; wk append)
		WP SET TEXT($body; "CELLSEAM"; wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
	$flow:=New collection("flow"; "headers"; "two-headers"; "mixed"; "seam"; "limit"; "oversize").includes($kind)
	$rows:=Choose($flow; 26; 3)
	$headers:=0
	If ($kind="headers")
		$headers:=1
	End if
	If ($kind="two-headers")
		$headers:=2
	End if
	For ($row; 1; $rows)
		$range:=WP Table append row($table; "C"+String($row)+"A1\rC"+String($row)+"A2"; "C"+String($row)+"B1\rC"+String($row)+"B2")
	End for
	WP SET ATTRIBUTES($table; wk header row count; $headers; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
	WP SET ATTRIBUTES(WP Table get columns($table; 1); wk width; "90pt"; wk padding; "3pt")
	WP SET ATTRIBUTES(WP Table get columns($table; 2); wk width; "140pt"; wk padding; "3pt")
	$style:=wk decimal
	Case of
		: ($kind="bullet")
			$style:=wk square
		: ($kind="latin")
			$style:=wk lower latin
		: ($kind="roman")
			$style:=wk upper roman
		: ($kind="disc")
			$style:=wk disc
		: ($kind="circle")
			$style:=wk circle
		: ($kind="hollow-square")
			$style:=wk hollow square
		: ($kind="diamond")
			$style:=wk diamond
		: ($kind="upper-latin")
			$style:=wk upper latin
		: ($kind="lower-roman")
			$style:=wk lower roman
	End case
	$item:=New object("name"; $kind; "rows"; $rows; "headers"; $headers; "flow"; $flow; "cells"; New collection())
	For ($row; 1; $rows)
		For ($column; 1; 2)
			$cell:=WP Table get cells($table; $column; $row)
			$range:=WP Paragraph range($cell)
			$start:=Choose($column=1; 7; 12)
			WP SET ATTRIBUTES($range; wk list style type; $style; wk margin left; "24pt"; wk list font; "Arial"; wk font bold; wk true; wk text color; "#135724")
			If ($flow)
				WP SET ATTRIBUTES(WP Paragraph range(WP Text range($cell; wk start text; wk start text)); wk list start number; $start)
			Else
				WP SET ATTRIBUTES($range; wk list start number; $start)
			End if
			If ($kind="limit")
				WP SET ATTRIBUTES($range; wk margin left; "48pt")
				WP SET ATTRIBUTES(WP Paragraph range(WP Text range($cell; wk start text; wk start text)); wk list start number; 3998)
			End if
			If ($kind="format")
				WP SET ATTRIBUTES($range; wk list string format ltr; "(#)")
			End if
			WP GET ATTRIBUTES($range; wk list style type; $actualStyle; wk list start number; $actualStart; wk margin left; $indent; wk list font; $font; wk list string format ltr; $format)
			$item.cells.push(New object("row"; $row; "column"; $column; "text"; WP Get text($cell); "style"; $actualStyle; "start"; $actualStart; "indent"; $indent; "font"; $font; "format"; $format))
		End for
	End for
	If ($headers>0)
		WP SET ATTRIBUTES(WP Table get rows($table; 1; $headers); wk background color; "#DDEEFF")
	End if
	If ($kind="mixed")
		$cell:=WP Table get cells($table; 2; 3)
		WP INSERT PICTURE(WP Text range($cell; wk end text; wk end text); $picture; wk append)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "30pt"; wk height; "24pt")
		$cell:=WP Table get cells($table; 2; 5)
		WP INSERT FORMULA($cell; Formula("CELLCACHE"); wk append)
		$cell:=WP Table get cells($table; 2; 7)
		WP SET TEXT($cell; "C7B1 wrapped words across several lines in the narrow cell\rC7B2"; wk replace)
		$cell:=WP Table get cells($table; 2; 9)
		WP SET TEXT($cell; "C9B1\rC9B2\rCELLPARAGRAPH"; wk replace)
		WP SET ATTRIBUTES(WP Get elements($cell; wk type paragraph)[2]; wk list style type; wk none)
	End if
	If ($kind="oversize")
		$long:="C1A1"
		For ($start; 1; 100)
			$long:=$long+" wrapped"
		End for
		WP SET TEXT(WP Table get cells($table; 1; 1); $long+"\rC1A2"; wk replace)
	End if
	$item.finalCells:=New collection()
	For ($row; 1; $rows)
		For ($column; 1; 2)
			$cell:=WP Table get cells($table; $column; $row)
			$cellReport:=New object("row"; $row; "column"; $column; "text"; WP Get text($cell; wk expressions as source); "paragraphs"; New collection())
			For each ($paragraph; WP Get elements($cell; wk type paragraph))
				WP GET ATTRIBUTES($paragraph; wk list style type; $actualStyle; wk list start number; $actualStart; wk margin left; $indent; wk list font; $font; wk list string format ltr; $format)
				$cellReport.paragraphs.push(New object("text"; WP Get text($paragraph); "style"; $actualStyle; "start"; $actualStart; "indent"; $indent; "font"; $font; "format"; $format))
			End for each
			$item.finalCells.push($cellReport)
		End for
	End for
	WP SET TEXT($body; "CELLEND"; wk append)
	If ($kind="mixed")
		$range:=WP Insert break($body; wk section break; wk append)
		WP SET TEXT($body; "CELLSECONDSECTION"; wk append)
		$section:=WP Get section($doc; 2)
		WP SET ATTRIBUTES($section; wk page orientation; wk landscape)
	End if
	If ($kind#"seam")
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "CELLDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		$section:=WP New subsection($section; wk first page)
		$area:=WP Get header($section)
		WP SET TEXT($area; "CELLFIRSTHEADER"; wk replace)
	End if
	If ($kind="mixed")
		For ($sectionIndex; 1; 2)
			$section:=WP Get section($doc; $sectionIndex)
			$area:=WP Get header($section)
			If ($area=Null)
				$area:=WP New header($section)
			End if
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTHEADER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
			$area:=WP New footer($section)
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTFOOTER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
			For each ($variant; New collection(wk first page; wk left page; wk right page))
				If ($variant=wk right page) | (($variant=wk first page) & ($sectionIndex=1))
					$target:=WP Get subsection($section; $variant)
				Else
					$target:=WP New subsection($section; $variant)
				End if
				Case of
					: ($variant=wk first page)
						$prefix:="FIRST"
					: ($variant=wk left page)
						$prefix:="LEFT"
					: ($variant=wk right page)
						$prefix:="RIGHT"
				End case
				$area:=WP Get header($target)
				WP SET TEXT($area; "S"+String($sectionIndex)+$prefix+"HEADER"; wk replace)
				WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
				$area:=WP Get footer($target)
				If ($area=Null)
					$area:=WP New footer($target)
				End if
				WP SET TEXT($area; "S"+String($sectionIndex)+$prefix+"FOOTER"; wk replace)
				WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
			End for each
		End for
		$area:=WP Get header(WP Get subsection(WP Get section($doc; 1); wk first page))
	End if
	$item.sections:=wp_section_stats($doc)
	$item.areas:=wp_header_stats($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/cell-list-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/cell-list-"+$kind+".pdf").platformPath; wk pdf)
	If ($kind#"seam")
		WP SET TEXT($area; "WEBCELL"; wk replace)
	Else
		WP SET TEXT(WP Text range($body; 1; 10); "WEBCELL"; wk replace)
	End if
	WP EXPORT DOCUMENT($doc; $root.file("Output/cell-list-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/cell-list-report.json").setText(JSON Stringify($report; *))
