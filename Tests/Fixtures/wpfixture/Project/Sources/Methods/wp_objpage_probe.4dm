var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $box; $image; $section; $target; $area; $range; $item; $spec : Object
var $kind; $step; $filler : Text
var $page; $variant : Integer
var $breaks; $objects : Collection
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
$filler:="Body filler text for anchored object pagination, Ünïcødé 日本語 Ελληνικά."
// Each shape is: page/section breaks between body pages ("P" page, "S" section, "C" continuous section, "A" one
// long paragraph that paginates automatically) and anchored objects with their requested target and layer. The
// native PDF, not this table, decides on which pages each object is drawn. Object tokens are unique words.
For each ($kind; New collection("doc-front"; "doc-behind"; "section-front"; "section-behind"; "square"; "variants"; "unicode"; "page-target"; "section-page"; "continuous"; "auto"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	Case of
		: ($kind="variants")
			$breaks:=New collection("P"; "P"; "P"; "S"; "P")
		: ($kind="unicode")
			$breaks:=New collection("P"; "S")
		: ($kind="continuous")
			$breaks:=New collection("P"; "C"; "P")
		: ($kind="auto")
			$breaks:=New collection("A")
		Else
			$breaks:=New collection("P"; "S"; "P")
	End case
	WP SET TEXT($body; "OBJP1"; wk replace)
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; $filler; wk append)
	$page:=1
	For each ($step; $breaks)
		If ($step="A")
			For ($variant; 1; 40)
				$range:=WP Insert break($body; wk paragraph break; wk append)
				WP SET TEXT($body; "OBJAUTO"+String($variant)+" "+$filler; wk append)
			End for
		Else
			Case of
				: ($step="P")
					$range:=WP Insert break($body; wk page break; wk append)
				: ($step="S")
					$range:=WP Insert break($body; wk section break; wk append)
				: ($step="C")
					$range:=WP Insert break($body; wk continuous section break; wk append)
			End case
			$page:=$page+1
			WP SET TEXT($body; "OBJP"+String($page); wk append)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; $filler; wk append)
		End if
	End for each
	If ($kind="square")
		For ($variant; 1; 6)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; "OBJWRAP"+String($variant)+" "+$filler; wk append)
		End for
	End if
	If ($kind="variants")
		$section:=WP Get section($doc; 1)
		$area:=WP New header($section)
		WP SET TEXT($area; "OBJDEFAULTHEADER"; wk replace)
		WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
		For each ($variant; New collection(wk first page; wk left page; wk right page))
			If ($variant=wk right page)
				$target:=WP Get subsection($section; $variant)
			Else
				$target:=WP New subsection($section; $variant)
			End if
			$area:=WP Get header($target)
			WP SET ATTRIBUTES($area; wk margin; "10pt 30pt")
			Case of
				: ($variant=wk first page)
					WP SET TEXT($area; "OBJFIRSTHEADER"; wk replace)
				: ($variant=wk left page)
					WP SET TEXT($area; "OBJLEFTHEADER"; wk replace)
				: ($variant=wk right page)
					WP SET TEXT($area; "OBJRIGHTHEADER"; wk replace)
			End case
		End for each
	End if
	// Object specs: kind (box/picture), token, section (0 = all), page (0 = all), layer.
	Case of
		: ($kind="doc-front")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXDOC"; "section"; 0; "page"; 0; "layout"; "front"); New object("kind"; "picture"; "section"; 0; "page"; 0; "layout"; "front"))
		: ($kind="doc-behind")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXDOC"; "section"; 0; "page"; 0; "layout"; "behind"); New object("kind"; "picture"; "section"; 0; "page"; 0; "layout"; "behind"))
		: ($kind="section-front")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXSECTION"; "section"; 2; "page"; 0; "layout"; "front"); New object("kind"; "picture"; "section"; 1; "page"; 0; "layout"; "front"))
		: ($kind="section-behind")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXSECTION"; "section"; 1; "page"; 0; "layout"; "behind"); New object("kind"; "picture"; "section"; 2; "page"; 0; "layout"; "behind"))
		: ($kind="square")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXSQUARE"; "section"; 0; "page"; 0; "layout"; "square"); New object("kind"; "picture"; "section"; 2; "page"; 0; "layout"; "square"))
		: ($kind="variants")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXVARIANT"; "section"; 1; "page"; 0; "layout"; "front"); New object("kind"; "picture"; "section"; 0; "page"; 0; "layout"; "behind"))
		: ($kind="unicode")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJUNIFRONT"; "text"; "OBJUNIFRONT 日本語テキスト Ünïcødé ✓"; "section"; 0; "page"; 0; "layout"; "front"); New object("kind"; "box"; "token"; "OBJUNIBEHIND"; "text"; "OBJUNIBEHIND Ελληνικά العربية"; "section"; 2; "page"; 0; "layout"; "behind"); New object("kind"; "picture"; "section"; 1; "page"; 0; "layout"; "front"))
		: ($kind="page-target")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXPAGE"; "section"; 0; "page"; 2; "layout"; "front"); New object("kind"; "picture"; "section"; 0; "page"; 3; "layout"; "behind"))
		: ($kind="section-page")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXSECTIONPAGE"; "section"; 2; "page"; 1; "layout"; "front"))
		: ($kind="continuous")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXSEAM"; "section"; 2; "page"; 0; "layout"; "front"); New object("kind"; "picture"; "section"; 1; "page"; 0; "layout"; "behind"))
		: ($kind="auto")
			$objects:=New collection(New object("kind"; "box"; "token"; "OBJBOXAUTO"; "section"; 0; "page"; 0; "layout"; "front"); New object("kind"; "picture"; "section"; 0; "page"; 0; "layout"; "behind"))
	End case
	$item:=New object("name"; $kind; "breaks"; $breaks; "requested"; $objects; "objects"; New collection())
	For each ($spec; $objects)
		If ($spec.kind="box")
			$box:=WP New text box($doc; 1)
			WP SET TEXT($box; Choose(OB Is defined($spec; "text"); $spec.text; $spec.token); wk replace)
			WP SET ATTRIBUTES($box; wk width; "120pt"; wk height; "40pt"; wk anchor horizontal offset; "150pt"; wk anchor vertical offset; "200pt")
		Else
			$box:=WP Add picture($doc; $picture)
			WP SET ATTRIBUTES($box; wk width; "48pt"; wk height; "32pt"; wk anchor horizontal offset; "40pt"; wk anchor vertical offset; "280pt")
		End if
		WP SET ATTRIBUTES($box; wk anchor section; Choose($spec.section=0; wk anchor all; $spec.section); wk anchor page; Choose($spec.page=0; wk anchor all; $spec.page))
		Case of
			: ($spec.layout="front")
				WP SET ATTRIBUTES($box; wk anchor layout; wk in front of text)
			: ($spec.layout="behind")
				WP SET ATTRIBUTES($box; wk anchor layout; wk behind text)
			: ($spec.layout="square")
				WP SET ATTRIBUTES($box; wk anchor layout; wk text wrap square)
		End case
		$item.objects.push($box.id)
	End for each
	$item.original:=wp_web_stats($doc; False)
	$item.stats:=wp_media_stats($doc)
	$item.sections:=wp_section_stats($doc)
	WP EXPORT DOCUMENT($doc; $root.file("Output/objpage-"+$kind+"-original.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/objpage-"+$kind+".pdf").platformPath; wk pdf)
	// The stored file alone must carry the association: re-import it and export its own PDF and getters.
	$target:=WP Import document($root.file("Output/objpage-"+$kind+"-original.4wp").platformPath)
	$item.reopened:=wp_media_stats($target)
	WP EXPORT DOCUMENT($target; $root.file("Output/objpage-"+$kind+"-reopened.pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 6); "WEBOBJ"; wk replace)
	WP EXPORT DOCUMENT($doc; $root.file("Output/objpage-"+$kind+"-edited.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	$report.cases.push($item)
End for each
$root.file("Output/objpage-report.json").setText(JSON Stringify($report; *))
