#DECLARE($doc : Object) : Object
var $result : Object:=New object("body"; wp_range_stats($doc); "geometry"; wp_page_stats($doc); "sections"; New collection())
var $section; $target; $area; $item; $scope; $range : Object
var $variant; $kind : Text
var $type; $index : Integer
var $top; $right; $bottom; $left : Variant
$index:=0
For each ($section; WP Get sections($doc))
	$index:=$index+1
	$item:=New object("index"; $index; "geometry"; wp_page_stats($section); "scopes"; New collection())
	For ($type; 0; 3)
		$target:=$section
		If ($type>0)
			$target:=WP Get subsection($section; $type)
		End if
		If ($target#Null)
			$scope:=New object("variant"; $type; "areas"; New collection())
			For each ($kind; New collection("header"; "footer"))
				If ($kind="header")
					$area:=WP Get header($target)
				Else
					$area:=WP Get footer($target)
				End if
				If ($area#Null)
					$range:=WP Text range($area; wk start text; wk end text)
					WP GET ATTRIBUTES($area; wk margin top; $top; wk margin right; $right; wk margin bottom; $bottom; wk margin left; $left)
					$scope.areas.push(New object("kind"; $kind; "text"; WP Get text($area; wk expressions as source); "start"; $range.start; "end"; $range.end; "first"; WP Get text(WP Text range($area; 1; 2); wk expressions as source); "margins"; New collection($top; $right; $bottom; $left)))
				End if
			End for each
			$item.scopes.push($scope)
		End if
	End for
	$result.sections.push($item)
End for each
return $result
