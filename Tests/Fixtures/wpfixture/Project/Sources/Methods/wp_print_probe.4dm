var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $section; $table; $item : Object
var $kind; $text; $token : Text
var $index : Integer
var $tokens : Collection
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("portrait"; "landscape"; "wide"; "mixed"; "columns"; "tabs"; "rich"; "associated"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "612pt"; wk page height; "792pt"; wk page margin top; "24pt"; wk page margin right; "30pt"; wk page margin bottom; "36pt"; wk page margin left; "42pt"; wk font; "Arial"; wk font size; "12pt")
	$tokens:=New collection("FIRST"; "SECOND"; "THIRD")
	WP SET TEXT($body; "FIRST"; wk replace)
	If ($kind="landscape")
		WP SET ATTRIBUTES($doc; wk page orientation; wk landscape)
	End if
	If ($kind="wide")
		WP SET ATTRIBUTES($doc; wk page width; "900pt"; wk page height; "500pt")
	End if
	If ($kind="columns")
		WP SET ATTRIBUTES($doc; wk column count; 2; wk column spacing; "18pt")
	End if
	If ($kind="tabs")
		WP SET ATTRIBUTES($doc; wk tabs; New collection(New object(wk type; wk right; wk offset; "144pt"; wk leading; ".")); wk tab default; "18pt")
		WP SET TEXT($body; Char(9)+"TABVALUE"; wk append)
		$tokens.push("TABVALUE")
	End if
	$range:=WP Insert break($body; wk page break; wk append)
	WP SET TEXT($body; "SECOND"; wk append)
	$range:=WP Insert break($body; wk section break; wk append)
	WP SET TEXT($body; "THIRD"; wk append)
	If ($kind="mixed")
		$section:=WP Get section($doc; 2)
		WP SET ATTRIBUTES($section; wk page orientation; wk landscape; wk page margin; "30pt")
		$range:=WP Insert break($body; wk continuous section break; wk append)
		WP SET TEXT($body; "FOURTH"; wk append)
		$tokens.push("FOURTH")
		$section:=WP Get section($doc; 3)
		WP SET ATTRIBUTES($section; wk page orientation; wk portrait; wk page margin; "36pt")
	End if
	If ($kind="associated")
		$section:=WP Get section($doc; 2)
		var $header : Object:=WP New header($section)
		WP SET TEXT($header; "NATIVE HEADER"; wk replace)
	End if
	If ($kind="rich") | ($kind="columns")
		For ($index; 0; 79)
			$token:="TEXT"+String($index)
			$tokens.push($token)
			$range:=WP Insert break($body; wk paragraph break; wk append)
			WP SET TEXT($body; $token+" word word word word word word"; wk append)
		End for
		$range:=WP Insert break($body; wk paragraph break; wk append)
		$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
		For ($index; 0; 39)
			$token:="ROW"+String($index)
			$tokens.push($token+"LEFT"; $token+"RIGHT")
			$range:=WP Table append row($table; $token+"LEFT"; $token+"RIGHT")
		End for
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP INSERT PICTURE($body; $picture; wk append)
		WP INSERT FORMULA($body; Formula("PRINTCACHE"); wk append)
		WP SET TEXT($body; "TAILEND"; wk append)
		$tokens.push("TAILEND")
	End if
	WP NEW BOOKMARK(WP Text range($body; 1; 3); "print_anchor")
	WP NEW BOOKMARK(WP Text range($body; wk start text; wk end text); "whole")
	$item:=New object("name"; $kind; "tokens"; $tokens; "sections"; wp_section_stats($doc); "flow"; wp_layout_stats($doc); "document"; wp_web_stats($doc; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/print-"+$kind+".4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/print-"+$kind+".pdf").platformPath; wk pdf)
	$report.cases.push($item)
End for each
$root.file("Output/print-report.json").setText(JSON Stringify($report; *))
