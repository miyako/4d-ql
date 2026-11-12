#DECLARE($target : Object) : Object
var $width; $height; $top; $right; $bottom; $left : Variant
var $orientation : Integer
WP GET ATTRIBUTES($target; wk page width; $width; wk page height; $height; wk page orientation; $orientation; wk page margin top; $top; wk page margin right; $right; wk page margin bottom; $bottom; wk page margin left; $left)
return New object("width"; $width; "height"; $height; "orientation"; $orientation; "top"; $top; "right"; $right; "bottom"; $bottom; "left"; $left)
