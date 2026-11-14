var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $section; $sub; $area; $item; $spec; $case : Object
var $kind; $prefix; $variant; $text : Text
var $index; $sectionIndex : Integer
var $cases; $variants : Collection
// Each shape lists its sections (stored areas, body paragraph count, optional explicit page break before paragraph N,
// optional space after the last paragraph) and the joins between them ("C" continuous, "S" new-page section). Body
// paragraphs carry CH<section>BODY<n> words and every area a unique CH<section><VARIANT><HEADER|FOOTER> word. The
// native PDF, read page by page, decides which section's header and footer are drawn on which page.
$cases:=New collection()
$cases.push(New object("name"; "default-both"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 40))))
$cases.push(New object("name"; "outgoing-only"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "none"; "length"; 40))))
$cases.push(New object("name"; "incoming-only"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "none"; "length"; 2); New object("areas"; "default"; "length"; 40))))
$cases.push(New object("name"; "first-incoming"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "first"; "length"; 40))))
$cases.push(New object("name"; "facing-incoming"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "facing"; "length"; 40))))
$cases.push(New object("name"; "first-facing-both"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first-facing"; "length"; 24); New object("areas"; "first-facing"; "length"; 40))))
$cases.push(New object("name"; "first-outgoing"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first"; "length"; 2); New object("areas"; "default"; "length"; 40))))
$cases.push(New object("name"; "chain-short"; "joins"; New collection("C"; "C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "first"; "length"; 2); New object("areas"; "default"; "length"; 40))))
$cases.push(New object("name"; "chain-long"; "joins"; New collection("C"; "C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "first"; "length"; 24); New object("areas"; "first"; "length"; 30))))
$cases.push(New object("name"; "page-break-incoming"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "first-facing"; "length"; 8; "pageBreak"; 4))))
$cases.push(New object("name"; "fresh-top"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 1; "spaceAfter"; "205pt"); New object("areas"; "first-facing"; "length"; 30))))
$cases.push(New object("name"; "single-page"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first"; "length"; 2); New object("areas"; "first"; "length"; 2))))
$cases.push(New object("name"; "unicode"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2; "text"; " Ünïcødé"); New object("areas"; "default"; "length"; 40; "text"; " 日本語 Ελληνικά"))))
$cases.push(New object("name"; "newpage-after"; "joins"; New collection("C"; "S"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 24); New object("areas"; "first"; "length"; 24))))
$cases.push(New object("name"; "footer-only"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "footer"; "length"; 2); New object("areas"; "footer"; "length"; 40))))
// Protected counterexamples: area-bearing seams that also change the incoming section's page geometry.
$cases.push(New object("name"; "margin-areas"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 40; "geometry"; "margin"))))
$cases.push(New object("name"; "orientation-areas"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 40; "geometry"; "orientation"))))
For each ($case; $cases)
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "CHSTART"; wk replace)
	For ($sectionIndex; 1; $case.sections.length)
		$spec:=$case.sections[$sectionIndex-1]
		For ($index; 1; $spec.length)
			If (($sectionIndex=1) | ($index>1))
				If (OB Is defined($spec; "pageBreak") && ($spec.pageBreak=$index))
					$range:=WP Insert break($body; wk page break; wk append)
				Else
					$range:=WP Insert break($body; wk paragraph break; wk append)
				End if
			End if
			WP SET TEXT($body; "CH"+String($sectionIndex)+"BODY"+String($index)+" word word"; wk append)
		End for
		If (OB Is defined($spec; "spaceAfter"))
			WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk margin bottom; $spec.spaceAfter)
		End if
		If ($sectionIndex<$case.sections.length)
			$range:=WP Insert break($body; Choose($case.joins[$sectionIndex-1]="C"; wk continuous section break; wk section break); wk append)
			If (OB Is defined($spec; "spaceAfter"))
				// New paragraphs inherit the preceding paragraph style: only the outgoing paragraph keeps the spacing.
				WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk margin bottom; "0pt")
			End if
		End if
	End for
	For ($sectionIndex; 1; WP Get sections($doc).length)
		$spec:=$case.sections[$sectionIndex-1]
		$section:=WP Get section($doc; $sectionIndex)
		WP SET ATTRIBUTES($section; wk section name; "Continuous areas "+String($sectionIndex))
		If (OB Is defined($spec; "geometry"))
			If ($spec.geometry="margin")
				WP SET ATTRIBUTES($section; wk page margin left; "72pt")
			Else
				WP SET ATTRIBUTES($section; wk page orientation; wk landscape)
			End if
		End if
		$prefix:="CH"+String($sectionIndex)
		$text:=Choose(OB Is defined($spec; "text"); $spec.text; "")
		If ($spec.areas#"none")
			If ($spec.areas#"footer")
				$area:=WP New header($section)
				WP SET TEXT($area; $prefix+"DEFAULTHEADER"+$text; wk replace)
				WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
			End if
			$area:=WP New footer($section)
			WP SET TEXT($area; $prefix+"DEFAULTFOOTER"+$text; wk replace)
			WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		End if
		$variants:=New collection()
		If (Position("first"; $spec.areas)>0)
			$variants.push("FIRST")
		End if
		If (Position("facing"; $spec.areas)>0)
			$variants.push("LEFT")
			$variants.push("RIGHT")
		End if
		For each ($variant; $variants)
			Case of
				: ($variant="FIRST")
					$sub:=WP New subsection($section; wk first page)
				: ($variant="LEFT")
					$sub:=WP New subsection($section; wk left page)
				Else
					$sub:=WP Get subsection($section; wk right page)
			End case
			For each ($kind; New collection("HEADER"; "FOOTER"))
				If ($kind="HEADER")
					$area:=WP Get header($sub)
				Else
					$area:=WP Get footer($sub)
				End if
				WP SET TEXT($area; $prefix+$variant+$kind+$text; wk replace)
				WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
			End for each
		End for each
	End for
	$item:=New object("name"; $case.name; "joins"; $case.joins; "requested"; $case.sections; "sections"; wp_section_stats($doc); "original"; wp_web_stats($doc; False); "areas"; New collection())
	// Independent native getters for every stored area, including first/left/right subsections.
	For ($sectionIndex; 1; WP Get sections($doc).length)
		$section:=WP Get section($doc; $sectionIndex)
		For each ($variant; New collection("DEFAULT"; "FIRST"; "LEFT"; "RIGHT"))
			Case of
				: ($variant="DEFAULT")
					$sub:=$section
				: ($variant="FIRST")
					$sub:=WP Get subsection($section; wk first page)
				: ($variant="LEFT")
					$sub:=WP Get subsection($section; wk left page)
				Else
					$sub:=WP Get subsection($section; wk right page)
			End case
			If ($sub#Null)
				For each ($kind; New collection("HEADER"; "FOOTER"))
					If ($kind="HEADER")
						$area:=WP Get header($sub)
					Else
						$area:=WP Get footer($sub)
					End if
					If ($area#Null)
						$item.areas.push(New object("section"; $sectionIndex; "variant"; $variant; "kind"; $kind; "text"; WP Get text($area; wk expressions as source)))
					End if
				End for each
			End if
		End for each
	End for
	WP EXPORT DOCUMENT($doc; $root.file("Output/contheader-"+$case.name+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/contheader-"+$case.name+".pdf").platformPath; wk pdf)
	// The stored file alone must carry the areas: re-import it and export its own PDF.
	$range:=WP Import document($root.file("Output/contheader-"+$case.name+"-original.4wp").platformPath)
	$item.reopened:=wp_section_stats($range)
	WP EXPORT DOCUMENT($range; $root.file("Output/contheader-"+$case.name+"-reopened.pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 8); "WEBCH"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/contheader-"+$case.name+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/contheader-report.json").setText(JSON Stringify($report; *))
