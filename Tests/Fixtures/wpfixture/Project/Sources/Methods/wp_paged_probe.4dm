var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $section; $target; $area; $break; $item : Object
var $kind; $prefix : Text
var $index; $sectionIndex; $variant : Integer
For each ($kind; New collection("right"; "left"; "mixed"; "missing"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	If ($kind="left")
		WP SET ATTRIBUTES($doc; wk page first right; wk false)
	End if
	WP SET TEXT($body; "PAGED1"; wk replace)
	For ($index; 2; 6)
		If ($index=4)
			$break:=WP Insert break($body; wk section break; wk append)
		Else
			$break:=WP Insert break($body; wk page break; wk append)
		End if
		WP SET TEXT($body; "PAGED"+String($index); wk append)
	End for
	For ($sectionIndex; 1; 2)
		$section:=WP Get section($doc; $sectionIndex)
		If ($kind="mixed") & ($sectionIndex=2)
			WP SET ATTRIBUTES($section; wk page orientation; wk landscape)
		End if
		If ($kind#"missing") | ($sectionIndex=1)
			$area:=WP New header($section)
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTHEADER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
			$area:=WP New footer($section)
			WP SET TEXT($area; "S"+String($sectionIndex)+"DEFAULTFOOTER"; wk replace)
			WP SET ATTRIBUTES($area; wk margin top; "10pt"; wk margin right; "30pt"; wk margin bottom; "10pt"; wk margin left; "30pt")
			For each ($variant; New collection(wk first page; wk left page; wk right page))
				If ($variant=wk right page)
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
				$area:=WP Get footer($target)
				WP SET TEXT($area; "S"+String($sectionIndex)+$prefix+"FOOTER"; wk replace)
			End for each
			If ($kind="missing")
				$target:=WP Get subsection($section; wk first page)
				WP DELETE HEADER($target)
				$target:=WP Get subsection($section; wk right page)
				WP DELETE FOOTER($target)
			End if
		End if
	End for
	WP NEW BOOKMARK(WP Text range($body; 1; 5); "paged_anchor")
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-"+$kind+".pdf").platformPath; wk pdf)
	$item:=New object("name"; $kind; "sections"; wp_section_stats($doc); "stages"; New collection(New object("name"; "original"; "stats"; wp_header_stats($doc))))
	$section:=WP Get section($doc; 1)
	$target:=WP Get subsection($section; wk first page)
	$area:=WP Get footer($target)
	WP SET TEXT($area; "WEBPAGED"; wk replace)
	WP EXPORT DOCUMENT($doc; $root.file("Output/paged-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$item.stages.push(New object("name"; "edited"; "stats"; wp_header_stats($doc)))
	$report.cases.push($item)
End for each
$root.file("Output/paged-report.json").setText(JSON Stringify($report; *))
