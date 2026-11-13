#DECLARE($doc : Object; $rows : Integer; $columns : Integer) : Object
var $table : Object:=WP Get elements(WP Get body($doc); wk type table)[0]
var $headers; $row; $column : Integer
var $width; $padding; $color; $background; $bold : Variant
WP GET ATTRIBUTES($table; wk header row count; $headers)
var $result : Object:=New object("headers"; $headers; "cells"; New collection())
var $cell : Object
For ($row; 1; $rows)
	For ($column; 1; $columns)
		$cell:=WP Table get cells($table; $column; $row)
		WP GET ATTRIBUTES($cell; wk width; $width; wk padding; $padding; wk text color; $color; wk background color; $background; wk font bold; $bold)
		$result.cells.push(New object("row"; $row; "column"; $column; "width"; $width; "padding"; $padding; "color"; $color; "background"; $background; "bold"; $bold; "text"; WP Get text($cell; wk expressions as source)))
	End for
End for
return $result
