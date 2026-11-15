var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $section; $sub; $area; $item; $spec; $case; $geometry : Object
var $kind; $prefix; $variant; $text; $key : Text
var $index; $sectionIndex : Integer
var $cases; $variants : Collection
// Continuous section breaks into a section whose page geometry differs (margins, orientation; section paper width/height setters raise
// error 205, so paper size is document-level and has no native continuous shape). Each shape
// lists its sections (stored areas, body paragraph count, optional section geometry overrides, optional text suffix)
// and the joins between them ("C" continuous). Body paragraphs carry CG<section>BODY<n> words and every area a unique
// CG<section><VARIANT><HEADER|FOOTER> word. The base document is 300 x 360 pt with 60/30/60/30 pt margins. The native
// PDF, read page by page (page size, body words and their x positions), decides whether 4D starts a new page or
// changes geometry mid-page, which geometry each page uses and which section's header and footer it draws.
$cases:=New collection()
$cases.push(New object("name"; "margin-left"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("left"; "72pt")))))
$cases.push(New object("name"; "margin-right"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("right"; "72pt")))))
$cases.push(New object("name"; "margin-top"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "100pt")))))
$cases.push(New object("name"; "margin-bottom"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("bottom"; "100pt")))))
$cases.push(New object("name"; "margin-all"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "90pt"; "right"; "50pt"; "bottom"; "90pt"; "left"; "50pt")))))
$cases.push(New object("name"; "margin-sides"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "none"; "length"; 2); New object("areas"; "none"; "length"; 30; "geometry"; New object("right"; "60pt"; "left"; "60pt")))))
$cases.push(New object("name"; "orientation"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("orientation"; "landscape")))))
$cases.push(New object("name"; "orientation-back"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2; "geometry"; New object("orientation"; "landscape")); New object("areas"; "default"; "length"; 30))))
$cases.push(New object("name"; "orientation-margin"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("orientation"; "landscape"; "left"; "72pt")))))
$cases.push(New object("name"; "orientation-first"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first-facing"; "length"; 2); New object("areas"; "first-facing"; "length"; 30; "geometry"; New object("orientation"; "landscape")))))
$cases.push(New object("name"; "orientation-none"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "none"; "length"; 2); New object("areas"; "none"; "length"; 30; "geometry"; New object("orientation"; "landscape")))))
$cases.push(New object("name"; "margin-left-first"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first-facing"; "length"; 2); New object("areas"; "first-facing"; "length"; 30; "geometry"; New object("left"; "72pt")))))
$cases.push(New object("name"; "orientation-long"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "first-facing"; "length"; 24); New object("areas"; "first-facing"; "length"; 30; "geometry"; New object("orientation"; "landscape")))))
$cases.push(New object("name"; "margin-left-long"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 24); New object("areas"; "default"; "length"; 30; "geometry"; New object("left"; "72pt")))))
$cases.push(New object("name"; "margin-top-long"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 24); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "100pt")))))
$cases.push(New object("name"; "margin-bottom-long"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 24); New object("areas"; "default"; "length"; 30; "geometry"; New object("bottom"; "100pt")))))
$cases.push(New object("name"; "orientation-chain"; "joins"; New collection("C"; "C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "first"; "length"; 2; "geometry"; New object("orientation"; "landscape")); New object("areas"; "default"; "length"; 24))))
$cases.push(New object("name"; "margin-chain"; "joins"; New collection("C"; "C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 2; "geometry"; New object("left"; "72pt")); New object("areas"; "default"; "length"; 24))))
$cases.push(New object("name"; "unicode"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2; "text"; " Ünïcødé"); New object("areas"; "default"; "length"; 30; "text"; " 日本語 Ελληνικά"; "geometry"; New object("orientation"; "landscape")))))
// Section margin setters default every unset side to 2.5cm (not the document margins): these shapes restate all four sides.
$cases.push(New object("name"; "margin-top-only"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 24); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "100pt"; "right"; "30pt"; "bottom"; "60pt"; "left"; "30pt")))))
$cases.push(New object("name"; "margin-bottom-only"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 24); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "60pt"; "right"; "30pt"; "bottom"; "100pt"; "left"; "30pt")))))
$cases.push(New object("name"; "margin-wider"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2); New object("areas"; "default"; "length"; 30; "geometry"; New object("top"; "60pt"; "right"; "10pt"; "bottom"; "60pt"; "left"; "10pt")))))
$cases.push(New object("name"; "margin-wrap"; "joins"; New collection("C"); "sections"; New collection(New object("areas"; "default"; "length"; 2; "text"; " alpha beta gamma delta epsilon zeta eta theta iota kappa"); New object("areas"; "default"; "length"; 12; "text"; " alpha beta gamma delta epsilon zeta eta theta iota kappa"; "geometry"; New object("top"; "60pt"; "right"; "120pt"; "bottom"; "60pt"; "left"; "30pt")))))
$cases.push(New object("name"; "mixed-chain"; "joins"; New collection("C"; "C"); "sections"; New collection(New object("areas"; "first"; "length"; 2); New object("areas"; "first"; "length"; 2; "geometry"; New object("left"; "72pt")); New object("areas"; "first-facing"; "length"; 24; "geometry"; New object("orientation"; "landscape")))))
For each ($case; $cases)
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "CGSTART"; wk replace)
	For ($sectionIndex; 1; $case.sections.length)
		$spec:=$case.sections[$sectionIndex-1]
		$text:=Choose(OB Is defined($spec; "text"); $spec.text; "")
		For ($index; 1; $spec.length)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; "CG"+String($sectionIndex)+"BODY"+String($index)+" word word"+$text; wk append)
		End for
		If ($sectionIndex<$case.sections.length)
			$range:=WP Insert break($body; wk continuous section break; wk append)
		End if
	End for
	For ($sectionIndex; 1; WP Get sections($doc).length)
		$spec:=$case.sections[$sectionIndex-1]
		$section:=WP Get section($doc; $sectionIndex)
		WP SET ATTRIBUTES($section; wk section name; "Continuous geometry "+String($sectionIndex))
		If (OB Is defined($spec; "geometry"))
			$geometry:=$spec.geometry
			For each ($key; $geometry)
				Case of
					: ($key="left")
						WP SET ATTRIBUTES($section; wk page margin left; $geometry.left)
					: ($key="right")
						WP SET ATTRIBUTES($section; wk page margin right; $geometry.right)
					: ($key="top")
						WP SET ATTRIBUTES($section; wk page margin top; $geometry.top)
					: ($key="bottom")
						WP SET ATTRIBUTES($section; wk page margin bottom; $geometry.bottom)
					: ($key="orientation")
						WP SET ATTRIBUTES($section; wk page orientation; Choose($geometry.orientation="landscape"; wk landscape; wk portrait))
				End case
			End for each
		End if
		$prefix:="CG"+String($sectionIndex)
		$text:=Choose(OB Is defined($spec; "text"); $spec.text; "")
		If ($spec.areas#"none")
			$area:=WP New header($section)
			WP SET TEXT($area; $prefix+"DEFAULTHEADER"+$text; wk replace)
			WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
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
	WP EXPORT DOCUMENT($doc; $root.file("Output/contgeom-"+$case.name+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/contgeom-"+$case.name+".pdf").platformPath; wk pdf)
	// The stored file alone must carry the geometry and areas: re-import it and export its own PDF.
	$range:=WP Import document($root.file("Output/contgeom-"+$case.name+"-original.4wp").platformPath)
	$item.reopened:=wp_section_stats($range)
	WP EXPORT DOCUMENT($range; $root.file("Output/contgeom-"+$case.name+"-reopened.pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 8); "WEBCG"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/contgeom-"+$case.name+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/contgeom-report.json").setText(JSON Stringify($report; *))
