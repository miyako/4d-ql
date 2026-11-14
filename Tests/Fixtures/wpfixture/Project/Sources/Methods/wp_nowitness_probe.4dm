var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $cell; $item; $section; $area; $reopened; $copy : Object
var $merge; $merges; $widths; $paddings; $letters : Collection
var $kind; $text : Text
var $row; $column; $headers; $columns; $rows; $cycle : Integer
var $width; $padding; $border : Variant
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
$letters:=New collection("A"; "B"; "C"; "D")
// Every shape has no merge-free row. Accepted candidates and native counterexamples are decided from the
// stored XML and the re-imported native column getters below, never from the requested arguments.
For each ($kind; New collection("alternate"; "header"; "two-headers"; "band"; "block"; "stair"; "rich"; "seam"; "border2"; "pad5"; "uneven"; "gap"; "pair"; "wide"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "NOWSTART"; wk replace)
	If ($kind="seam")
		$range:=WP Insert break($body; wk continuous section break; wk append)
		WP SET TEXT($body; "NOWSEAM"; wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
	$widths:=New collection(50; 70; 110)
	If ($kind="stair") | ($kind="gap")
		$widths:=New collection(30; 50; 40; 60)
	End if
	If ($kind="wide")
		$widths:=New collection(80; 90; 100)
	End if
	$columns:=$widths.length
	For ($row; 1; 26)
		If ($columns=4)
			$range:=WP Table append row($table; "R"+String($row)+"A"; "R"+String($row)+"B"; "R"+String($row)+"C"; "R"+String($row)+"D")
		Else
			$range:=WP Table append row($table; "R"+String($row)+"A"; "R"+String($row)+"B"; "R"+String($row)+"C")
		End if
	End for
	$headers:=0
	If ($kind="header") | ($kind="rich")
		$headers:=1
	End if
	If ($kind="two-headers")
		$headers:=2
	End if
	$border:="1pt"
	If ($kind="border2")
		$border:="2pt"
	End if
	WP SET ATTRIBUTES($table; wk header row count; $headers; wk border style; wk solid; wk border width; $border; wk border color; "#234567")
	$paddings:=New collection("3pt"; "3pt"; "3pt"; "3pt")
	If ($kind="pad5")
		$paddings:=New collection("5pt"; "5pt"; "5pt"; "5pt")
	End if
	If ($kind="uneven")
		$paddings:=New collection("2pt"; "5pt"; "3pt"; "3pt")
	End if
	For ($column; 1; $columns)
		WP SET ATTRIBUTES(WP Table get columns($table; $column); wk width; String($widths[$column-1])+"pt"; wk padding; $paddings[$column-1])
	End for
	$item:=New object("name"; $kind; "headers"; $headers; "columns"; $columns; "requestedWidths"; $widths; "requestedPaddings"; $paddings.slice(0; $columns); "requestedBorder"; $border; "before"; wp_web_stats($doc; False); "merges"; New collection(); "cells"; New collection(); "nativeColumns"; New collection(); "reopenedColumns"; New collection(); "reopenedCells"; New collection())
	WP EXPORT DOCUMENT($doc; $root.file("Output/nowitness-"+$kind+"-before.4wp").platformPath; wk 4wp)
	// Each merge is column; row; column count; row count (origin 1), applied in this order.
	$merges:=New collection()
	For ($row; 1; 26)
		Case of
			: ($kind="band")
				If (($row%2)=1)
					$merges.push(New collection(1; $row; 1; 2))
				End if
			: ($kind="block")
				$cycle:=$row%4
				If ($cycle=1)
					$merges.push(New collection(1; $row; 2; 2))
				End if
				If ($cycle=3) & ($row<26)
					$merges.push(New collection(2; $row; 2; 2))
				End if
			: ($kind="stair")
				$merges.push(New collection(($row-1)%3+1; $row; 2; 1))
			: ($kind="gap")
				If (($row%2)=1)
					$merges.push(New collection(1; $row; 2; 1))
					$merges.push(New collection(3; $row; 2; 1))
				Else
					$merges.push(New collection(1; $row; 3; 1))
				End if
			: ($kind="pair")
				$merges.push(New collection(1; $row; 2; 1))
			Else
				If (($row%2)=1)
					$merges.push(New collection(1; $row; 2; 1))
				Else
					$merges.push(New collection(2; $row; 2; 1))
				End if
		End case
	End for
	For each ($merge; $merges)
		WP TABLE MERGE CELLS($table; $merge[0]; $merge[1]; $merge[2]; $merge[3])
		$item.merges.push($merge)
	End for each
	// Observed in probe-01/02: full 4D removes a column that never separates from its neighbour in any row
	// (pair: B always joins A; gap: B always joins A), so no unresolvable column boundary is ever stored.
	If ($kind="pair") | ($kind="gap")
		$columns:=$columns-1
	End if
	$item.columns:=$columns
	If ($headers>0)
		WP SET ATTRIBUTES(WP Table get rows($table; 1; $headers); wk background color; "#DDEEFF"; wk font bold; wk true)
	End if
	If ($kind="rich")
		// Row 6 is [A][BC]; row 9 is [AB][C]: lists, a local picture, an inert formula and a link in merged cells.
		$cell:=WP Table get cells($table; 2; 6)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk disc; wk list font; "Arial"; wk margin left; "24pt"; wk font bold; wk true; wk text color; "#135724")
		$cell:=WP Table get cells($table; 1; 9)
		WP SET ATTRIBUTES(WP Paragraph range($cell); wk list style type; wk diamond; wk list font; "Arial"; wk margin left; "24pt")
		$cell:=WP Table get cells($table; 1; 3)
		$range:=WP Get elements($cell; wk type paragraph)[0]
		WP INSERT PICTURE($range; $picture; wk prepend)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "30pt"; wk height; "24pt")
		$cell:=WP Table get cells($table; 2; 12)
		$range:=WP Get elements($cell; wk type paragraph)[1]
		WP INSERT FORMULA($range; Formula(Uppercase("nowc")); wk prepend)
		$cell:=WP Table get cells($table; 1; 11)
		WP SET LINK(WP Text range($cell; wk start text; wk end text); New object("url"; "https://example.invalid/nowitness"))
		WP SET ATTRIBUTES($cell; wk font italic; wk true)
	End if
	$rows:=WP Get elements($table; wk type table row).length
	$item.rows:=$rows
	For ($column; 1; $columns)
		WP GET ATTRIBUTES(WP Table get columns($table; $column); wk width; $width; wk padding; $padding)
		$item.nativeColumns.push(New object("column"; $column; "width"; $width; "padding"; $padding))
	End for
	For ($row; 1; $rows)
		For ($column; 1; $columns)
			$cell:=WP Table get cells($table; $column; $row)
			WP GET ATTRIBUTES($cell; wk width; $width; wk padding; $padding)
			$item.cells.push(New object("row"; $row; "column"; $column; "width"; $width; "padding"; $padding; "text"; WP Get text($cell; wk expressions as source)))
		End for
	End for
	WP SET TEXT($body; "NOWEND"; wk append)
	If ($kind#"seam")
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "NOWDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		$section:=WP New subsection($section; wk first page)
		$area:=WP Get header($section)
		WP SET TEXT($area; "NOWFIRSTHEADER"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	$item.original:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/nowitness-"+$kind+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/nowitness-"+$kind+".pdf").platformPath; wk pdf)
	// Native column resolution from the stored file alone: import the exported original and read the column getters.
	$reopened:=WP Import document($root.file("Output/nowitness-"+$kind+"-original.4wp").platformPath)
	$copy:=WP Get elements(WP Get body($reopened); wk type table)[0]
	For ($column; 1; $columns)
		WP GET ATTRIBUTES(WP Table get columns($copy; $column); wk width; $width; wk padding; $padding)
		$item.reopenedColumns.push(New object("column"; $column; "width"; $width; "padding"; $padding))
	End for
	For ($row; 1; WP Get elements($copy; wk type table row).length)
		For ($column; 1; $columns)
			$cell:=WP Table get cells($copy; $column; $row)
			WP GET ATTRIBUTES($cell; wk width; $width)
			$item.reopenedCells.push(New object("row"; $row; "column"; $column; "width"; $width))
		End for
	End for
	WP EXPORT DOCUMENT($reopened; $root.file("Output/nowitness-"+$kind+"-reopened.pdf").platformPath; wk pdf)
	If ($kind#"seam")
		WP SET TEXT($area; "WEBNOW"; wk replace)
	Else
		WP SET TEXT(WP Text range($body; 1; 9); "WEBNOW"; wk replace)
	End if
	WP COMPUTE FORMULAS($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/nowitness-"+$kind+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/nowitness-report.json").setText(JSON Stringify($report; *))
