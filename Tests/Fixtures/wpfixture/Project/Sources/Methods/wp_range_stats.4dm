#DECLARE($doc : Object) : Object
var $result : Object:=New object("text"; WP Get text($doc; wk expressions as source); "bookmarks"; New object(); "units"; New collection())
var $body : Object:=WP Get body($doc)
var $all : Object:=WP Text range($body; wk start text; wk end text)
$result.start:=$all.start
$result.end:=$all.end
ARRAY TEXT($names; 0)
WP GET BOOKMARKS($doc; $names)
var $i : Integer
var $range : Object
For ($i; 1; Size of array($names))
	$range:=WP Bookmark range($doc; $names{$i})
	$result.bookmarks[$names{$i}]:=New object("start"; $range.start; "end"; $range.end; "text"; WP Get text($range; wk expressions as source))
End for
For ($i; 0; $all.end-1)
	$range:=WP Text range($body; $i; $i+1)
	var $text : Text:=WP Get text($range; wk expressions as source)
	var $code : Integer:=0
	If (Length($text)>0)
		$code:=Character code($text)
	End if
	$result.units.push(New object("start"; $range.start; "end"; $range.end; "code"; $code))
End for
return $result
