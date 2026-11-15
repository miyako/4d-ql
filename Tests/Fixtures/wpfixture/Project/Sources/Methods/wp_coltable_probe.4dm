var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $cell; $item; $section; $area; $case; $reopened; $spec : Object
var $merge; $cases; $widths; $letters; $values : Collection
var $text; $suffix : Text
var $row; $column; $index; $rows : Integer
var $width; $padding : Variant
$letters:=New collection("A"; "B"; "C")
// Tables inside multi-column sections (M4c). The base document is 480 x 420 pt with 60/36 pt margins, Arial 10pt;
// each shape lists its column count/gap, table column widths (2pt padding, 1pt solid borders), rows, header rows,
// merges (column; row; column count; row count, origin 1), cell lists, filler paragraphs before/after and an optional
// second section. Every cell carries a unique R<row><A|B|C> token. The native PDF, read page by page with word
// x/y positions, decides in which page and column each row and cell appears; exact coordinates are not an oracle.
$cases:=New collection()
$cases.push(New object("name"; "two"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40))
$cases.push(New object("name"; "three"; "count"; 3; "gap"; "12pt"; "widths"; New collection(30; 34; 38); "rows"; 60))
$cases.push(New object("name"; "header"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "headers"; 1))
$cases.push(New object("name"; "two-headers"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "headers"; 2))
$cases.push(New object("name"; "gap0"; "count"; 2; "gap"; "0pt"; "widths"; New collection(30; 34; 38); "rows"; 40))
$cases.push(New object("name"; "midcolumn"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 30; "before"; 12))
$cases.push(New object("name"; "short"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 6; "after"; 30))
$cases.push(New object("name"; "pages"; "count"; 2; "gap"; "18pt"; "widths"; New collection(40; 40; 40); "rows"; 100; "headers"; 1))
$cases.push(New object("name"; "rowspan"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "headers"; 1; "merges"; New collection(New collection(3; 5; 1; 2); New collection(1; 9; 1; 3); New collection(2; 15; 1; 2); New collection(3; 21; 1; 4); New collection(1; 30; 1; 3))))
$cases.push(New object("name"; "colspan"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "merges"; New collection(New collection(1; 5; 2; 1); New collection(2; 9; 2; 1); New collection(1; 15; 3; 1); New collection(2; 24; 2; 1))))
$cases.push(New object("name"; "nowitness"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "alternate"; True))
$cases.push(New object("name"; "lists"; "count"; 2; "gap"; "18pt"; "widths"; New collection(50; 50; 38); "rows"; 40; "headers"; 1; "lists"; True))
$cases.push(New object("name"; "unicode"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "suffix"; True))
$cases.push(New object("name"; "wide"; "count"; 2; "gap"; "18pt"; "widths"; New collection(80; 80; 80); "rows"; 40))
$cases.push(New object("name"; "four"; "count"; 4; "gap"; "6pt"; "widths"; New collection(30; 34); "rows"; 80))
$cases.push(New object("name"; "tallband"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "merges"; New collection(New collection(3; 3; 1; 24))))
$cases.push(New object("name"; "mixed"; "count"; 1; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 10; "second"; New object("count"; 2; "gap"; "18pt"; "rows"; 40; "headers"; 1)))
$cases.push(New object("name"; "center"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "headers"; 1; "align"; "center"))
$cases.push(New object("name"; "right"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 40; "headers"; 1; "align"; "right"))
$cases.push(New object("name"; "colbreak"; "count"; 2; "gap"; "18pt"; "widths"; New collection(30; 34; 38); "rows"; 30; "headers"; 1; "colbreak"; True))
For each ($case; $cases)
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "480pt"; wk page height; "420pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "36pt"; wk page margin right; "36pt"; wk font; "Arial"; wk font size; "10pt"; wk column count; $case.count; wk column spacing; $case.gap)
	WP SET TEXT($body; "CTSTART"; wk replace)
	$item:=New object("name"; $case.name; "requested"; $case; "tables"; New collection())
	For ($index; 1; Num($case.before))
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP SET TEXT($body; "CTFILL"+String($index)+" word word word"; wk append)
	End for
	$values:=New collection(New object("rows"; $case.rows; "headers"; Num($case.headers); "count"; $case.count; "first"; 1))
	If (OB Is defined($case; "second"))
		$values.push(New object("rows"; $case.second.rows; "headers"; Num($case.second.headers); "count"; $case.second.count; "first"; $case.rows+1))
	End if
	For each ($spec; $values)
		If ($spec.first>1)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; "CTSECTION"; wk append)
			$range:=WP Insert break($body; wk section break; wk append)
			WP SET TEXT($body; "CTSECOND"; wk append)
		End if
		If (Bool($case.colbreak))
			$range:=WP Insert break($body; wk column break; wk append)
			WP SET TEXT($body; "CTCOLUMN"; wk append)
		End if
		$range:=WP Insert break($body; wk paragraph break; wk append)
		$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
		$widths:=$case.widths
		For ($row; $spec.first; $spec.first+$spec.rows-1)
			$suffix:=Choose(Bool($case.suffix); " ü日本🚃é"; "")
			If ($widths.length=2)
				$range:=WP Table append row($table; "R"+String($row)+"A"+$suffix; "R"+String($row)+"B"+$suffix)
			Else
				$range:=WP Table append row($table; "R"+String($row)+"A"+$suffix; "R"+String($row)+"B"+$suffix; "R"+String($row)+"C"+$suffix)
			End if
		End for
		If (OB Is defined($case; "align"))
			WP SET ATTRIBUTES($table; wk table align; Choose($case.align="center"; wk center; wk right))
		End if
		WP SET ATTRIBUTES($table; wk header row count; $spec.headers; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
		For ($column; 1; $widths.length)
			WP SET ATTRIBUTES(WP Table get columns($table; $column); wk width; String($widths[$column-1])+"pt"; wk padding; "2pt")
		End for
		If ($spec.first=1)
			If (OB Is defined($case; "merges"))
				For each ($merge; $case.merges)
					WP TABLE MERGE CELLS($table; $merge[0]; $merge[1]; $merge[2]; $merge[3])
				End for each
			End if
			If (Bool($case.alternate))
				For ($row; 1; $spec.rows)
					WP TABLE MERGE CELLS($table; Choose(($row%2)=1; 1; 2); $row; 2; 1)
				End for
			End if
			If (Bool($case.lists))
				$cell:=WP Table get cells($table; 3; 6)
				WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk disc; wk list font; "Arial"; wk margin left; "14pt")
				$cell:=WP Table get cells($table; 2; 25)
				WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk diamond; wk list font; "Arial"; wk margin left; "14pt")
				$cell:=WP Table get cells($table; 1; 33)
				WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk decimal; wk margin left; "14pt")
			End if
		End if
		If ($spec.headers>0)
			WP SET ATTRIBUTES(WP Table get rows($table; 1; $spec.headers); wk background color; "#DDEEFF"; wk font bold; wk true)
		End if
		$rows:=WP Get elements($table; wk type table row).length
		$item.tables.push(New object("rows"; $rows; "headers"; $spec.headers; "first"; $spec.first; "cells"; New collection()))
		For ($row; 1; $rows)
			For ($column; 1; $widths.length)
				$cell:=WP Table get cells($table; $column; $row)
				WP GET ATTRIBUTES($cell; wk width; $width; wk padding; $padding)
				$item.tables[$item.tables.length-1].cells.push(New object("row"; $row; "column"; $column; "width"; $width; "padding"; $padding; "text"; WP Get text($cell; wk expressions as source)))
			End for
		End for
	End for each
	For ($index; 1; Num($case.after))
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP SET TEXT($body; "CTFILL"+String($index)+" word word word"; wk append)
	End for
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "CTEND"; wk append)
	If (OB Is defined($case; "second"))
		$section:=WP Get section($doc; 2)
		WP SET ATTRIBUTES($section; wk column count; $case.second.count; wk column spacing; $case.second.gap)
	End if
	$section:=WP Get section($doc; 1)
	$area:=WP New header($section)
	WP SET TEXT($area; "CTDEFAULTHEADER"; wk replace)
	WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	$area:=WP New footer($section)
	WP SET TEXT($area; "CTDEFAULTFOOTER"; wk replace)
	WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	$item.layout:=wp_layout_stats($doc)
	$item.sections:=wp_section_stats($doc)
	$item.original:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/coltable-"+$case.name+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/coltable-"+$case.name+".pdf").platformPath; wk pdf)
	// The stored file alone must carry the columns and tables: re-import it and export its own PDF.
	$reopened:=WP Import document($root.file("Output/coltable-"+$case.name+"-original.4wp").platformPath)
	$item.reopened:=wp_layout_stats($reopened)
	WP EXPORT DOCUMENT($reopened; $root.file("Output/coltable-"+$case.name+"-reopened.pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 8); "WEBCT"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/coltable-"+$case.name+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/coltable-report.json").setText(JSON Stringify($report; *))
