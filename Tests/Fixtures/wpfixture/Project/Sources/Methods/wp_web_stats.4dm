#DECLARE($doc : Object; $probeImage : Boolean) : Object
var $title; $author; $subject; $company; $notes : Text
WP GET ATTRIBUTES($doc; wk title; $title; wk author; $author; wk subject; $subject; wk company; $company; wk notes; $notes)
var $result : Object:=New object("text"; WP Get text($doc; wk expressions as source); "metadata"; New object("title"; $title; "author"; $author; "subject"; $subject; "company"; $company; "notes"; $notes); "images"; WP Get elements($doc; wk type image).length; "tables"; WP Get elements($doc; wk type table).length; "formulas"; New collection(); "links"; New collection())
var $item : Object
$result.bookmarks:=New object()
ARRAY TEXT($bookmarkNames; 0)
WP GET BOOKMARKS($doc; $bookmarkNames)
var $i : Integer
For ($i; 1; Size of array($bookmarkNames))
	$item:=WP Bookmark range($doc; $bookmarkNames{$i})
	$result.bookmarks[$bookmarkNames{$i}]:=New object("start"; $item.start; "end"; $item.end; "text"; WP Get text($item; wk expressions as source))
End for
For each ($item; WP Get formulas($doc))
	$result.formulas.push(New object("source"; $item.formula.source; "name"; $item.name))
End for each
For each ($item; WP Get links($doc))
	$result.links.push(New object("url"; $item.url; "method"; $item.method; "bookmark"; $item.bookmark))
End for each
If ($probeImage)
	var $picture : Picture
	var $width; $height : Integer
	WP GET ATTRIBUTES(WP Get elements($doc; wk type image)[0]; wk image; $picture)
	PICTURE PROPERTIES($picture; $width; $height)
	$result.imagePixels:=New object("width"; $width; "height"; $height)
End if
var $range : Object:=WP Text range(WP Get body($doc); 1; 2)
var $firstText : Text:=WP Get text($range; wk expressions as source)
If (Length($firstText)>0)
	var $firstCode : Integer:=Character code($firstText)
	If (($firstCode>=55296) & ($firstCode<=56319))
		$range:=WP Text range(WP Get body($doc); 1; 3)
	End if
End if
var $bold; $italic; $underline; $strike; $size; $color; $background : Variant
WP GET ATTRIBUTES($range; wk font bold; $bold; wk font italic; $italic; wk text underline style; $underline; wk text linethrough style; $strike; wk font size; $size; wk text color; $color; wk background color; $background)
$result.first:=New object("text"; WP Get text($range; wk expressions as source); "bold"; $bold=wk true; "italic"; $italic=wk true; "underline"; $underline#wk none; "strike"; $strike#wk none; "size"; $size; "color"; $color; "background"; $background)
return $result
