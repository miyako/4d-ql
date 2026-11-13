#DECLARE($doc : Object) : Object
var $result : Object:=New object("body"; wp_range_stats($doc); "sections"; New collection(); "breaks"; New collection(); "associations"; New collection())
var $section; $item; $header; $footer : Object
var $name : Text
For each ($section; WP Get sections($doc))
	WP GET ATTRIBUTES($section; wk section name; $name)
	$item:=New object("index"; $section.index; "name"; $name; "geometry"; wp_page_stats($section))
	$header:=WP Get header($section)
	$footer:=WP Get footer($section)
	If ($header#Null)
		$item.header:=WP Get text($header; wk expressions as source)
	End if
	If ($footer#Null)
		$item.footer:=WP Get text($footer; wk expressions as source)
	End if
	$result.sections.push($item)
End for each
For each ($item; WP Get breaks(WP Get body($doc)))
	$result.breaks.push(New object("start"; $item.start; "end"; $item.end; "type"; $item.breakType))
End for each
var $anchorSection; $anchorPage; $anchorLayout : Variant
For each ($item; WP Get elements($doc; wk type image))
	WP GET ATTRIBUTES($item; wk anchor layout; $anchorLayout)
	If ($anchorLayout=wk inline with text)
		$result.associations.push(New object("layout"; $anchorLayout))
	Else
		WP GET ATTRIBUTES($item; wk anchor section; $anchorSection; wk anchor page; $anchorPage)
		$result.associations.push(New object("section"; $anchorSection; "page"; $anchorPage; "layout"; $anchorLayout))
	End if
End for each
return $result
