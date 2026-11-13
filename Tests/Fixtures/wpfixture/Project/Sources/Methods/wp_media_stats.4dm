#DECLARE($doc : Object) : Object
var $body : Object:=WP Get body($doc)
var $result : Object
var $item; $row : Object
var $width; $height; $horizontal; $vertical; $displayMode : Variant
var $page; $section; $origin; $hAlign; $vAlign; $layout : Integer
$result:=New object("body"; wp_range_stats($doc); "objects"; New collection())
For each ($item; WP Get elements($doc; wk type image anchored).concat(WP Get elements($doc; wk type text box)))
	$row:=New object("id"; $item.id; "attributes"; New object())
	If ($item.type=wk type text box)
		$row.text:=WP Get text($item; wk expressions as source)
	End if
	WP GET ATTRIBUTES($item; wk width; $width; wk height; $height; wk anchor page; $page; wk anchor section; $section; wk anchor origin; $origin; wk anchor horizontal offset; $horizontal; wk anchor vertical offset; $vertical; wk anchor horizontal align; $hAlign; wk anchor vertical align; $vAlign; wk anchor layout; $layout)
	$row.attributes:=New object("width"; $width; "height"; $height; "page"; $page; "section"; $section; "origin"; $origin; "horizontal"; $horizontal; "vertical"; $vertical; "hAlign"; $hAlign; "vAlign"; $vAlign; "layout"; $layout)
	If ($item.type#wk type text box)
		WP GET ATTRIBUTES($item; wk image display mode; $displayMode)
		$row.attributes.displayMode:=$displayMode
	End if
	$result.objects.push($row)
End for each
return $result
