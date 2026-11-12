var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection(); "validation"; New collection())
var $doc; $body; $section; $break; $result : Object
var $kind : Text
For each ($kind; New collection("default"; "landscape"; "custom"; "widePortrait"; "fractional"; "points"; "sections"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET TEXT($body; "AB"; wk replace)
	WP INSERT FORMULA($body; Formula("PAGE"); wk append)
	WP SET TEXT($body; "CD"; wk append)
	WP NEW BOOKMARK(WP Text range($body; 1; 2); "page_anchor")
	Case of
		: ($kind="landscape")
			WP SET ATTRIBUTES($doc; wk page orientation; wk landscape)
		: ($kind="custom")
			WP SET ATTRIBUTES($doc; wk page width; "612pt"; wk page height; "792pt"; wk page margin; "36pt")
		: ($kind="widePortrait")
			WP SET ATTRIBUTES($doc; wk page width; "900pt"; wk page height; "500pt"; wk page orientation; wk portrait)
		: ($kind="fractional")
			WP SET ATTRIBUTES($doc; wk page width; "210mm"; wk page height; "297mm"; wk page margin top; "12.345mm"; wk page margin right; "0pt"; wk page margin bottom; "0.5in"; wk page margin left; "1.25cm")
		: ($kind="points")
			WP SET ATTRIBUTES($doc; wk page width; "600.125pt"; wk page height; "800.875pt")
		: ($kind="sections")
			$break:=WP Insert break($body; wk section break; wk append)
			WP SET TEXT($body; "SECOND"; wk append)
			$section:=WP Get section($doc; 2)
			WP SET ATTRIBUTES($section; wk page margin left; "40pt"; wk page orientation; wk landscape)
	End case
	$result:=New object("name"; $kind; "before"; wp_page_stats($doc); "section1"; wp_page_stats(WP Get section($doc; 1)))
	If ($kind="sections")
		$result.section2Before:=wp_page_stats(WP Get section($doc; 2))
		WP EXPORT DOCUMENT($doc; $root.file("Output/page-sections-original.4wp").platformPath; wk 4wp)
		WP SET ATTRIBUTES($doc; wk page width; "612pt"; wk page height; "792pt"; wk page orientation; wk landscape; wk page margin; "30pt")
		$result.after:=wp_page_stats($doc)
		$result.section1After:=wp_page_stats(WP Get section($doc; 1))
		$result.section2After:=wp_page_stats(WP Get section($doc; 2))
	End if
	WP EXPORT DOCUMENT($doc; $root.file("Output/page-"+$kind+".4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/page-"+$kind+".pdf").platformPath; wk pdf)
	$report.cases.push($result)
End for each
// Native-created expected targets, independent of the web model and browser.
For each ($kind; New collection("letterLandscape"; "customPortrait"; "a5"; "fractionalMargin"; "wide"; "sectionsTarget"))
	If ($kind="sectionsTarget")
		$doc:=WP Import document($root.file("Output/page-sections-original.4wp").platformPath)
	Else
		$doc:=WP Import document($root.file("Output/page-default.4wp").platformPath)
	End if
	wp_page_apply($doc; $kind)
	$result:=New object("name"; $kind; "document"; wp_page_stats($doc); "sections"; New collection())
	For each ($section; WP Get sections($doc))
		$result.sections.push(wp_page_stats($section))
	End for each
	WP EXPORT DOCUMENT($doc; $root.file("Output/page-target-"+$kind+".4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/page-target-"+$kind+".pdf").platformPath; wk pdf)
	$report.cases.push($result)
End for each
var $savedErrors : Collection:=wpWebErrors
var $value : Real
For each ($kind; New collection("width"; "margin"))
	For each ($value; New collection(-1; 0; 1; 10; 72; 1584; 2000; 10000))
		wpWebErrors:=New collection()
		$doc:=WP New()
		If ($kind="width")
			WP SET ATTRIBUTES($doc; wk page width; String($value)+"pt")
		Else
			WP SET ATTRIBUTES($doc; wk page margin left; String($value)+"pt")
		End if
		$report.validation.push(New object("attribute"; $kind; "value"; $value; "errors"; wpWebErrors; "effective"; wp_page_stats($doc)))
	End for each
End for each
wpWebErrors:=$savedErrors
$root.file("Output/page-report.json").setText(JSON Stringify($report; *))
