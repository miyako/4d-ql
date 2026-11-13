var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $section; $area; $item : Object
var $kind; $text : Text
var $index; $part; $sectionIndex; $length : Integer
For each ($kind; New collection("compatible"; "explicit"; "overflow"; "chain"; "newpage"; "columns"; "column-change"; "margin-change"; "orientation-change"; "areas"; "variants"; "empty-variants"; "areas-overflow"; "variants-overflow"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "480pt"; wk page height; "420pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "36pt"; wk page margin right; "36pt"; wk font; "Arial"; wk font size; "12pt")
	If (($kind="columns") | ($kind="column-change"))
		WP SET ATTRIBUTES($doc; wk column count; 2; wk column spacing; "18pt")
	End if
	WP SET TEXT($body; "SEAMSTART"; wk replace)
	$range:=WP Insert break($body; wk paragraph break; wk append)
	For ($part; 1; 2)
		$text:=""
		$length:=5
		If (Position("overflow"; $kind)>0)
			$length:=119
		End if
		For ($index; 0; $length)
			$text:=$text+"SEAM"+String($part)+"TOKEN"+String($index)+" word word "
		End for
		WP SET TEXT($body; $text; wk append)
		WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk font bold; wk true; wk text color; "#135724")
		If ($part=1)
			If ($kind="explicit")
				$range:=WP Insert break($body; wk page break; wk append)
				WP SET TEXT($body; "BEFORESEAM"; wk append)
			End if
			$range:=WP Insert break($body; wk continuous section break; wk append)
		End if
	End for
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "SEAMEND"; wk append)
	If (($kind="chain") | ($kind="newpage"))
		$range:=WP Insert break($body; Choose($kind="chain"; wk continuous section break; wk section break); wk append)
		WP SET TEXT($body; "THIRDSECTION"; wk append)
	End if
	WP NEW BOOKMARK(WP Text range($body; wk end text; wk end text); "seam_tail")
	For ($sectionIndex; 1; WP Get sections($doc).length)
		$section:=WP Get section($doc; $sectionIndex)
		WP SET ATTRIBUTES($section; wk section name; "Native seam "+String($sectionIndex))
		If (($kind="areas") | ($kind="variants") | ($kind="areas-overflow") | ($kind="variants-overflow") | (($kind="newpage") & ($sectionIndex=3)))
			$area:=WP New header($section)
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTHEADER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
			$area:=WP New footer($section)
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTFOOTER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin; "10pt 36pt")
		End if
		If (($kind="variants") | ($kind="empty-variants") | ($kind="variants-overflow"))
			$area:=WP Get header(WP New subsection($section; wk first page))
			If ($kind#"empty-variants")
				WP SET TEXT($area; "S"+String($sectionIndex)+"FIRSTHEADER"; wk replace)
			End if
			$area:=WP Get header(WP New subsection($section; wk left page))
			If ($kind#"empty-variants")
				WP SET TEXT($area; "S"+String($sectionIndex)+"LEFTHEADER"; wk replace)
				$area:=WP Get header(WP Get subsection($section; wk right page))
				WP SET TEXT($area; "S"+String($sectionIndex)+"RIGHTHEADER"; wk replace)
			End if
		End if
	End for
	$section:=WP Get section($doc; 2)
	Case of
		: ($kind="column-change")
			WP SET ATTRIBUTES($section; wk column count; 3; wk column spacing; "12pt")
		: ($kind="margin-change")
			WP SET ATTRIBUTES($section; wk page margin left; "72pt")
		: ($kind="orientation-change")
			WP SET ATTRIBUTES($section; wk page orientation; wk landscape)
		: ($kind="compatible")
			WP SET ATTRIBUTES($section; wk page margin top; "60pt"; wk page margin right; "36pt"; wk page margin bottom; "60pt"; wk page margin left; "36pt"; wk column count; 1)
	End case
	$item:=New object("name"; $kind; "layout"; wp_layout_stats($doc); "sections"; wp_section_stats($doc); "original"; wp_web_stats($doc; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/continuous-paged-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/continuous-paged-"+$kind+".pdf").platformPath; wk pdf)
	$item.editScope:="body"
	Case of
		: ($kind="newpage")
			$area:=WP Get header(WP Get section($doc; 3))
			$item.editScope:="section3Header"
		: (($kind="areas") | ($kind="areas-overflow"))
			$area:=WP Get header(WP Get section($doc; 1))
			$item.editScope:="section1Header"
		: (($kind="variants") | ($kind="variants-overflow"))
			$area:=WP Get header(WP Get subsection(WP Get section($doc; 1); wk first page))
			$item.editScope:="section1FirstHeader"
	End case
	If ($item.editScope="body")
		WP SET TEXT(WP Text range($body; 1; 10); "WEBSEAM"; wk replace)
	Else
		WP SET TEXT($area; "WEBSEAM"; wk replace)
	End if
	$item.edited:=wp_web_stats($doc; False)
	$item.editedSections:=wp_section_stats($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/continuous-paged-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/continuous-paged-report.json").setText(JSON Stringify($report; *))
