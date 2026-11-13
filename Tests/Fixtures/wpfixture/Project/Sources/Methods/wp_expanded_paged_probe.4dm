var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $range; $item : Object
var $kind; $text; $token : Text
var $index : Integer
var $tokens : Collection
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($kind; New collection("paragraphs"; "lists"; "images"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk page width; "300pt"; wk page height; "360pt"; wk page margin top; "60pt"; wk page margin bottom; "60pt"; wk page margin left; "30pt"; wk page margin right; "30pt"; wk font; "Arial"; wk font size; "12pt")
	WP SET TEXT($body; "EXPANDED"; wk replace)
	$range:=WP Insert break($body; wk paragraph break; wk append)
	$tokens:=New collection("EXPANDED")
	$text:=""
	For ($index; 0; 59)
		$token:="FLOW"+String($index)
		$tokens.push($token)
		$text:=$text+$token+"  word word word "
	End for
	$text:=$text+"日"+Char(0x1F600)+"e"+Char(0x0301)
	WP SET TEXT($body; $text; wk append)
	$range:=WP Text range($body; 10; 10+Length($text))
	WP SET ATTRIBUTES($range; wk font bold; wk true; wk text color; "#135724")
	If ($kind="lists")
		WP SET ATTRIBUTES($range; wk list style type; wk decimal; wk margin left; "24pt")
		$range:=WP Insert break($body; wk paragraph break; wk append)
		WP SET TEXT($body; "LEVELTWO"; wk append)
		WP SET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk list style type; wk square; wk margin left; "48pt")
		$tokens.push("LEVELTWO")
	End if
	If ($kind="images")
		WP INSERT PICTURE(WP Text range($body; 220; 220); $picture; wk replace)
		WP SET ATTRIBUTES(WP Get elements($body; wk type image)[0]; wk width; "90pt"; wk height; "72pt")
		WP INSERT FORMULA($body; Formula("EXPANDEDCACHE"); wk append)
	End if
	$range:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "TAILEND"; wk append)
	WP RESET ATTRIBUTES(WP Paragraph range(WP Text range($body; wk end text; wk end text)); wk list style type)
	$tokens.push("TAILEND")
	WP NEW BOOKMARK(WP Text range($body; 12; 24); "fragment_anchor")
	WP NEW BOOKMARK(WP Text range($body; 220; 221); "atom_anchor")
	$item:=New object("name"; $kind; "tokens"; $tokens; "original"; wp_web_stats($doc; False))
	WP EXPORT DOCUMENT($doc; $root.file("Output/expanded-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/expanded-"+$kind+".pdf").platformPath; wk pdf)
	WP SET TEXT(WP Text range($body; 1; 9); "WEBEXPANDED"; wk replace)
	$item.edited:=wp_web_stats($doc; False)
	WP EXPORT DOCUMENT($doc; $root.file("Output/expanded-"+$kind+"-edited.4wp").platformPath; wk 4wp)
	$report.cases.push($item)
End for each
$root.file("Output/expanded-report.json").setText(JSON Stringify($report; *))
