var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $section; $area; $item : Object
var $kind; $text; $gap : Text
var $index; $count : Integer
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("two"; "three"; "four"; "breaks"; "mixed"; "rule"; "narrow"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	$count:=2
	$gap:="18pt"
	If ($kind="three")
		$count:=3
		$gap:="0pt"
	End if
	If ($kind="four")
		$count:=4
	End if
	If ($kind="narrow")
		$count:=5
	End if
	WP SET ATTRIBUTES($doc; wk page width; "480pt"; wk page height; "420pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "36pt"; wk page margin right; "36pt"; wk font; "Arial"; wk font size; "12pt"; wk column count; $count; wk column spacing; $gap)
	WP SET TEXT($body; "COLUMNSTART"; wk replace)
	$range:=WP Insert break($body; wk paragraph break; wk append)
	If ($kind="breaks")
		WP SET TEXT($body; "COLA"; wk append)
		$range:=WP Insert break($body; wk column break; wk append)
		WP SET TEXT($body; "COLB"; wk append)
		$range:=WP Insert break($body; wk column break; wk append)
		WP SET TEXT($body; "COLC"; wk append)
		$range:=WP Insert break($body; wk page break; wk append)
		WP SET TEXT($body; "PAGED"; wk append)
	Else
		$text:=""
		For ($index; 0; 119)
			$text:=$text+"COLTOKEN"+String($index)+" word word "
		End for
		$text:=$text+"日"+Char(0x1F600)+"e"+Char(0x0301)
		WP SET TEXT($body; $text; wk append)
		WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk font bold; wk true; wk text color; "#135724")
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP SET TEXT($body; "LISTONE"; wk append)
		WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk list style type; wk decimal; wk margin left; "18pt")
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP SET TEXT($body; "LISTTWO"; wk append)
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP RESET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk list style type)
		WP INSERT PICTURE($body; $picture; wk append)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "36pt"; wk height; "30pt")
		WP INSERT FORMULA($body; Formula("COLUMNCACHE"); wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "COLUMNEND"; wk append)
	WP NEW BOOKMARK(WP Text range($body; 2; 8); "column_anchor")
	$section:=WP Get section($doc; 1)
	If ($kind="rule")
		WP SET ATTRIBUTES($section; wk column rule style; wk solid; wk column rule width; "1pt"; wk column rule color; "#234567")
	End if
	$area:=WP New header($section)
	WP SET TEXT($area; "COLDEFAULTHEADER"; wk replace)
	WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	$area:=WP New footer($section)
	WP SET TEXT($area; "COLDEFAULTFOOTER"; wk replace)
	WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	$area:=WP Get header(WP New subsection($section; wk first page))
	WP SET TEXT($area; "COLFIRSTHEADER"; wk replace)
	$area:=WP Get header(WP New subsection($section; wk left page))
	WP SET TEXT($area; "COLLEFTHEADER"; wk replace)
	$area:=WP Get header(WP Get subsection($section; wk right page))
	WP SET TEXT($area; "COLRIGHTHEADER"; wk replace)
	If ($kind="mixed")
		$range:=WP Insert break($body; wk section break; wk append)
		WP SET TEXT($body; "SECONDSECTION"; wk append)
		$section:=WP Get section($doc; 2)
		WP SET ATTRIBUTES($section; wk column count; 3; wk column spacing; "12pt"; wk page orientation; wk landscape)
		$area:=WP Get header($section)
		WP SET TEXT($area; "SECONDHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
	End if
	$item:=New object("name"; $kind; "layout"; wp_layout_stats($doc); "sections"; wp_section_stats($doc); "original"; wp_web_stats($doc; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-column-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-column-"+$kind+".pdf").platformPath; wk pdf)
	$section:=WP Get section($doc; 1)
	$area:=WP Get header(WP Get subsection($section; wk first page))
	WP SET TEXT($area; "WEBCOLUMN"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-column-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/paged-column-report.json").setText(JSON Stringify($report; *))
