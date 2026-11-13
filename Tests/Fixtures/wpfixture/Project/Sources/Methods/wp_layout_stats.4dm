#DECLARE($doc : Object) : Object
var $result : Object:=New object("sections"; New collection(); "paragraphs"; New collection())
var $target; $item; $range : Object
var $count : Integer
var $gap : Text
var $tabs : Collection
var $default : Object
For each ($target; WP Get sections($doc))
	WP GET ATTRIBUTES($target; wk column count; $count; wk column spacing; $gap)
	$result.sections.push(New object("count"; $count; "gap"; $gap))
End for each
WP GET ATTRIBUTES($doc; wk column count; $count; wk column spacing; $gap)
$result.defaults:=New object("count"; $count; "gap"; $gap)
For each ($target; WP Get elements(WP Get body($doc); wk type paragraph))
	WP GET ATTRIBUTES($target; wk tabs; $tabs; wk tab default; $default)
	$range:=WP Text range($target; wk start text; wk end text)
	$item:=New object("start"; $range.start; "end"; $range.end; "tabs"; $tabs; "default"; $default)
	$result.paragraphs.push($item)
End for each
return $result
