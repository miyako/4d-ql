var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $table; $range; $section; $area; $case; $item; $target; $reopened : Object
var $cases; $sections : Collection
var $index; $row; $column; $count : Integer
var $style; $width; $color; $gap : Variant
// Rules between columns (M4d). The base document is 480 x 420 pt with 60/36 pt margins, Arial 10pt, a default
// header and footer (10pt 36pt margins). Each shape lists its column count/gap and rule (style, width, colour; a
// missing key is left unset), the number of one-line "CL<n> word word word" paragraphs, optional breaks after a given
// line (column/page), an optional table, second section or continuous seam. The native PDF vector content (read
// with pdftocairo -svg) decides on which pages a rule is drawn, between which columns (inside which gap) and its
// vertical extent relative to the body; exact coordinates are not an oracle.
$cases:=New collection()
$cases.push(New object("name"; "solid"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 120))
$cases.push(New object("name"; "lastboth"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 80))
$cases.push(New object("name"; "short"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 10))
$cases.push(New object("name"; "three"; "count"; 3; "gap"; "12pt"; "style"; wk solid; "width"; "1pt"; "color"; "#7A1F3D"; "lines"; 100))
$cases.push(New object("name"; "three-two"; "count"; 3; "gap"; "12pt"; "style"; wk solid; "width"; "1pt"; "color"; "#7A1F3D"; "lines"; 130))
$cases.push(New object("name"; "four"; "count"; 4; "gap"; "6pt"; "style"; wk solid; "width"; "1pt"; "color"; "#1F7A3D"; "lines"; 150))
$cases.push(New object("name"; "dotted"; "count"; 2; "gap"; "18pt"; "style"; wk dotted; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "dashed"; "count"; 2; "gap"; "18pt"; "style"; wk dashed; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "double"; "count"; 2; "gap"; "18pt"; "style"; wk double; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "groove"; "count"; 2; "gap"; "18pt"; "style"; wk groove; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "ridge"; "count"; 2; "gap"; "18pt"; "style"; wk ridge; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "inset"; "count"; 2; "gap"; "18pt"; "style"; wk inset; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "outset"; "count"; 2; "gap"; "18pt"; "style"; wk outset; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "none"; "count"; 2; "gap"; "18pt"; "style"; wk none; "width"; "3pt"; "color"; "#C00000"; "lines"; 60))
$cases.push(New object("name"; "default"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "lines"; 60))
$cases.push(New object("name"; "thin"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "0.5pt"; "color"; "#336699"; "lines"; 60))
$cases.push(New object("name"; "thick"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "6pt"; "color"; "#336699"; "lines"; 60))
$cases.push(New object("name"; "overgap"; "count"; 2; "gap"; "4pt"; "style"; wk solid; "width"; "8pt"; "color"; "#336699"; "lines"; 60))
$cases.push(New object("name"; "gap0"; "count"; 2; "gap"; "0pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60))
$cases.push(New object("name"; "colbreak"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 9; "breaks"; New collection(New object("after"; 3; "kind"; "column"); New object("after"; 6; "kind"; "page"))))
$cases.push(New object("name"; "pagebreak"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 70; "breaks"; New collection(New object("after"; 5; "kind"; "page"))))
$cases.push(New object("name"; "fullcol"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 40; "breaks"; New collection(New object("after"; 30; "kind"; "page"))))
$cases.push(New object("name"; "noareas"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60; "noareas"; True))
$cases.push(New object("name"; "table"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 2; "table"; 40))
$cases.push(New object("name"; "section2"; "count"; 2; "gap"; "18pt"; "lines"; 60; "second"; New object("count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60)))
$cases.push(New object("name"; "docdefault"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60; "document"; True))
$cases.push(New object("name"; "landscape"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60; "landscape"; True))
$cases.push(New object("name"; "single"; "count"; 1; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 40))
$cases.push(New object("name"; "continuous-in"; "count"; 1; "gap"; "18pt"; "lines"; 8; "second"; New object("count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60; "continuous"; True)))
$cases.push(New object("name"; "continuous-same"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 8; "second"; New object("count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 60; "continuous"; True)))
$cases.push(New object("name"; "three-partial"; "count"; 3; "gap"; "12pt"; "style"; wk solid; "width"; "1pt"; "color"; "#7A1F3D"; "lines"; 115))
$cases.push(New object("name"; "four-partial"; "count"; 4; "gap"; "6pt"; "style"; wk solid; "width"; "1pt"; "color"; "#1F7A3D"; "lines"; 76))
$cases.push(New object("name"; "skipcol"; "count"; 3; "gap"; "12pt"; "style"; wk solid; "width"; "1pt"; "color"; "#7A1F3D"; "lines"; 6; "breaks"; New collection(New object("after"; 3; "kind"; "column2"))))
$cases.push(New object("name"; "emptycol"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 6; "breaks"; New collection(New object("after"; 3; "kind"; "column2"))))
$cases.push(New object("name"; "cmwidth"; "count"; 2; "gap"; "18pt"; "style"; wk dashed; "width"; "0.1cm"; "color"; "#336699"; "lines"; 60))
$cases.push(New object("name"; "table-wide"; "count"; 2; "gap"; "18pt"; "style"; wk solid; "width"; "1pt"; "color"; "#234567"; "lines"; 2; "table"; 40; "tablewidths"; New collection(124; 128; 132)))
For each ($case; $cases)
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "480pt"; wk page height; "420pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "36pt"; wk page margin right; "36pt"; wk font; "Arial"; wk font size; "10pt"; wk column count; $case.count; wk column spacing; $case.gap)
	If (Bool($case.landscape))
		WP SET ATTRIBUTES($doc; wk page orientation; wk landscape)
	End if
	WP SET TEXT($body; "CRSTART"; wk replace)
	$item:=New object("name"; $case.name; "requested"; $case; "lines"; New collection())
	$sections:=New collection($case)
	If (OB Is defined($case; "second"))
		$sections.push($case.second)
	End if
	$count:=0
	For each ($target; $sections)
		If ($count>0)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; "CRSECTION"; wk append)
			$range:=WP Insert break($body; Choose(Bool($target.continuous); wk continuous section break; wk section break); wk append)
			WP SET TEXT($body; "CRSECOND"; wk append)
		End if
		For ($index; 1; $target.lines)
			$count:=$count+1
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; "CL"+String($count)+" word word word"; wk append)
			$item.lines.push($count)
			If (OB Is defined($target; "breaks"))
				If ($target.breaks.query("after = :1"; $index).length>0)
					If ($target.breaks.query("after = :1"; $index)[0].kind="column2")
						// Two consecutive column breaks: the next column holds only an empty paragraph.
						$range:=WP Insert break($body; wk column break; wk append)
					End if
					$range:=WP Insert break($body; Choose($target.breaks.query("after = :1"; $index)[0].kind="page"; wk page break; wk column break); wk append)
					WP SET TEXT($body; "CRBREAK"+String($index); wk append)
				End if
			End if
		End for
		If (Num($target.table)>0)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
			For ($row; 1; $target.table)
				$range:=WP Table append row($table; "R"+String($row)+"A"; "R"+String($row)+"B"; "R"+String($row)+"C")
			End for
			WP SET ATTRIBUTES($table; wk border style; wk solid; wk border width; "1pt"; wk border color; "#234567")
			For ($column; 1; 3)
				// 4D evaluates operators left to right: the default widths are 34/38/42pt; "tablewidths" overrides them.
				If (OB Is defined($target; "tablewidths"))
					WP SET ATTRIBUTES(WP Table get columns($table; $column); wk width; String($target.tablewidths[$column-1])+"pt"; wk padding; "2pt")
				Else
					WP SET ATTRIBUTES(WP Table get columns($table; $column); wk width; String(30+($column*4))+"pt"; wk padding; "2pt")
				End if
			End for
		End if
	End for each
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "CREND"; wk append)
	$item.applied:=New collection()
	For ($index; 0; $sections.length-1)
		$target:=Choose(Bool($sections[$index].document); $doc; WP Get section($doc; $index+1))
		If ($index>0)
			WP SET ATTRIBUTES($target; wk column count; $sections[$index].count; wk column spacing; $sections[$index].gap)
		End if
		If (OB Is defined($sections[$index]; "style"))
			WP SET ATTRIBUTES($target; wk column rule style; $sections[$index].style)
		End if
		If (OB Is defined($sections[$index]; "width"))
			WP SET ATTRIBUTES($target; wk column rule width; $sections[$index].width)
		End if
		If (OB Is defined($sections[$index]; "color"))
			WP SET ATTRIBUTES($target; wk column rule color; $sections[$index].color)
		End if
	End for
	// Native effective rule getters of every section (after re-import too).
	For each ($target; WP Get sections($doc))
		WP GET ATTRIBUTES($target; wk column count; $count; wk column spacing; $gap; wk column rule style; $style; wk column rule width; $width; wk column rule color; $color)
		$item.applied.push(New object("index"; $target.index; "count"; $count; "gap"; $gap; "style"; $style; "width"; $width; "color"; $color))
	End for each
	If (Not(Bool($case.noareas)))
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "CRDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
		$area:=WP New footer($section)
		WP SET TEXT($area; "CRDEFAULTFOOTER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	End if
	$item.layout:=wp_layout_stats($doc)
	$item.sections:=wp_section_stats($doc)
	$item.original:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/colrule-"+$case.name+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/colrule-"+$case.name+".pdf").platformPath; wk pdf)
	// The stored file alone must carry the rule: re-import it, read its getters and export its own PDF.
	$reopened:=WP Import document($root.file("Output/colrule-"+$case.name+"-original.4wp").platformPath)
	$item.reopened:=New collection()
	For each ($target; WP Get sections($reopened))
		WP GET ATTRIBUTES($target; wk column count; $count; wk column spacing; $gap; wk column rule style; $style; wk column rule width; $width; wk column rule color; $color)
		$item.reopened.push(New object("index"; $target.index; "count"; $count; "gap"; $gap; "style"; $style; "width"; $width; "color"; $color))
	End for each
	WP EXPORT DOCUMENT($reopened; $root.file("Output/colrule-"+$case.name+"-reopened.pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 8); "WEBCR"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/colrule-"+$case.name+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/colrule-report.json").setText(JSON Stringify($report; *))
